---HTML Post-Processor.
---Generates a single-file documentation web app with embedded CSS, JS, and SQLite-WASM search.
---Supports model overlay: template-specific assets override default assets per-file.
---
---Architecture:
---  - Loads theme from html/themes/ (Lua module with light/dark color schemes)
---  - Concatenates modular CSS from html/css/ (base, layout, components, syntax)
---  - Concatenates modular JS from html/js/ (router, theme, sidebar, search, inspector, app)
---  - Uses Lua templates from html/templates/ for HTML structure
---  - Embeds SQLite DB + WASM binary for client-side full-text search
---  - Outputs a single self-contained index.html
---
---@module models.default.postprocessors.html5
local M = {}

-- ============================================================================
-- File Reading Utilities
-- ============================================================================

---Read a file's contents.
---@param path string Path to file
---@return string|nil File contents or nil if not found
local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read("*all")
    file:close()
    return content
end

---Get SPECCOMPILER_HOME directory.
---@return string Path to speccompiler-core directory
local function get_speccompiler_home()
    return os.getenv("SPECCOMPILER_HOME") or "."
end

---Get asset directory paths for a template (template-specific first, default fallback).
---@param template string Template name (e.g., "sw_docs", "abnt")
---@return string template_dir Path to template's model directory
---@return string default_dir Path to default model directory
local function get_asset_dirs(template)
    local home = get_speccompiler_home()
    local default_dir = home .. "/models/default"
    local template_dir = default_dir
    if template and template ~= "" and template ~= "default" then
        template_dir = home .. "/models/" .. template
    end
    return template_dir, default_dir
end

-- ============================================================================
-- Theme System
-- ============================================================================

---Load theme module with fallback.
---@param template string Template name (e.g., "sw_docs")
---@return table Theme table with light, dark, typography, layout
local function load_theme(template)
    local paths = {
        string.format("models.%s.html.themes.default", template),
        "models.default.html.themes.default",
    }

    for _, path in ipairs(paths) do
        local ok, theme = pcall(require, path)
        if ok and theme then
            return theme
        end
    end

    -- Minimal fallback
    return {
        light = {
            text = "#1a1a1a", text_muted = "#6b7280", text_inverse = "#ffffff",
            bg = "#ffffff", surface = "#f9fafb", surface_hover = "#f3f4f6",
            border = "#e5e7eb", border_strong = "#d1d5db",
            accent = "#2563eb", accent_hover = "#1d4ed8", accent_light = "#dbeafe",
            success = "#059669", warning = "#d97706", error = "#dc2626", info = "#0284c7",
            highlight = "#fef08a",
            card_bg = "#f9fafb", card_border = "#e5e7eb",
            code_bg = "#f8f8f8",
            sidebar_bg = "#ffffff", sidebar_active = "#2563eb",
            syntax_keyword = "#d73a49", syntax_string = "#032f62",
            syntax_comment = "#6a737d", syntax_number = "#005cc5",
            syntax_function = "#6f42c1", syntax_type = "#e36209",
            syntax_variable = "#24292e", syntax_operator = "#d73a49",
            syntax_builtin = "#005cc5", syntax_attribute = "#e36209",
        },
        dark = {
            text = "#e5e7eb", text_muted = "#9ca3af", text_inverse = "#111827",
            bg = "#111827", surface = "#1f2937", surface_hover = "#374151",
            border = "#374151", border_strong = "#4b5563",
            accent = "#60a5fa", accent_hover = "#93bbfd", accent_light = "#1e3a5f",
            success = "#34d399", warning = "#fbbf24", error = "#f87171", info = "#38bdf8",
            highlight = "#854d0e",
            card_bg = "#1f2937", card_border = "#374151",
            code_bg = "#1e293b",
            sidebar_bg = "#111827", sidebar_active = "#3b82f6",
            syntax_keyword = "#ff7b72", syntax_string = "#a5d6ff",
            syntax_comment = "#8b949e", syntax_number = "#79c0ff",
            syntax_function = "#d2a8ff", syntax_type = "#ffa657",
            syntax_variable = "#e5e7eb", syntax_operator = "#ff7b72",
            syntax_builtin = "#79c0ff", syntax_attribute = "#ffa657",
        },
        typography = {
            font_family = "Inter, Roboto, system-ui, sans-serif",
            font_mono = "monospace",
            font_size = "16px",
            line_height = 1.6,
        },
        layout = {
            content_width = "48rem",
            sidebar_width = "280px",
            inspector_width = "340px",
            header_height = "52px",
        },
    }
end

---Convert a color scheme table to CSS custom property declarations.
---@param scheme table Color key-value pairs (e.g., { text = "#1a1a1a", bg = "#fff" })
---@param prefix string CSS property prefix (e.g., "color")
---@return string CSS declarations (one per line, indented)
local function scheme_to_css(scheme, prefix)
    local lines = {}
    -- Sort keys for deterministic output
    local keys = {}
    for k in pairs(scheme) do
        -- Skip syntax_* keys (they get their own --syntax-* prefix)
        if not k:match("^syntax_") then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)

    for _, k in ipairs(keys) do
        -- Convert Lua underscores to CSS hyphens: card_bg -> card-bg
        local css_name = k:gsub("_", "-")
        lines[#lines + 1] = string.format("  --%s-%s: %s;", prefix, css_name, scheme[k])
    end
    return table.concat(lines, "\n")
end

---Generate CSS custom properties block from theme.
---@param theme table Theme with light, dark, typography, layout
---@return string CSS block with :root and [data-theme="dark"] selectors
local function generate_theme_css(theme)
    local typo = theme.typography or {}
    local layout = theme.layout or {}

    local parts = {
        ":root {",
        -- Typography
        string.format("  --font-family: %s;", typo.font_family or "system-ui, sans-serif"),
        string.format("  --font-mono: %s;", typo.font_mono or "monospace"),
        string.format("  --font-size: %s;", typo.font_size or "16px"),
        string.format("  --line-height: %s;", tostring(typo.line_height or 1.6)),
        -- Layout
        string.format("  --layout-content-width: %s;", layout.content_width or "48rem"),
        string.format("  --layout-sidebar-width: %s;", layout.sidebar_width or "280px"),
        string.format("  --layout-inspector-width: %s;", layout.inspector_width or "340px"),
        string.format("  --layout-header-height: %s;", layout.header_height or "52px"),
        -- Light mode colors (default)
        scheme_to_css(theme.light or {}, "color"),
        -- Syntax colors from light scheme
    }

    -- Extract syntax vars from light scheme (sorted for deterministic output)
    local light = theme.light or {}
    local light_syntax_keys = {}
    for k in pairs(light) do
        if k:match("^syntax_") then light_syntax_keys[#light_syntax_keys + 1] = k end
    end
    table.sort(light_syntax_keys)
    for _, k in ipairs(light_syntax_keys) do
        local css_name = k:gsub("^syntax_", ""):gsub("_", "-")
        parts[#parts + 1] = string.format("  --syntax-%s: %s;", css_name, light[k])
    end

    parts[#parts + 1] = "}"
    parts[#parts + 1] = ""

    -- Dark mode overrides
    parts[#parts + 1] = '[data-theme="dark"] {'
    parts[#parts + 1] = scheme_to_css(theme.dark or {}, "color")

    -- Syntax colors from dark scheme (sorted for deterministic output)
    local dark = theme.dark or {}
    local dark_syntax_keys = {}
    for k in pairs(dark) do
        if k:match("^syntax_") then dark_syntax_keys[#dark_syntax_keys + 1] = k end
    end
    table.sort(dark_syntax_keys)
    for _, k in ipairs(dark_syntax_keys) do
        local css_name = k:gsub("^syntax_", ""):gsub("_", "-")
        parts[#parts + 1] = string.format("  --syntax-%s: %s;", css_name, dark[k])
    end

    parts[#parts + 1] = "}"

    return table.concat(parts, "\n")
end

-- ============================================================================
-- Asset Concatenation
-- ============================================================================

---CSS files to load, in order.
local CSS_FILES = {
    "base.css",
    "layout.css",
    "components.css",
    "syntax.css",
}

---JS files to load, in order (dependency order matters).
local JS_FILES = {
    "router.js",
    "theme.js",
    "sidebar.js",
    "search.js",
    "inspector.js",
    "app.js",
}

---Read and concatenate asset files with overlay support.
---For each file, tries template_dir first, falls back to default_dir.
---@param template_dir string Template-specific model directory
---@param default_dir string Default model directory
---@param subdir string Subdirectory within html/ (e.g., "css", "js")
---@param files table Ordered list of filenames
---@param log table Logger
---@return string Concatenated content
local function concat_assets(template_dir, default_dir, subdir, files, log)
    local parts = {}
    for _, filename in ipairs(files) do
        local content
        local template_path = template_dir .. "/html/" .. subdir .. "/" .. filename
        local default_path = default_dir .. "/html/" .. subdir .. "/" .. filename
        content = read_file(template_path)
        if not content and template_dir ~= default_dir then
            content = read_file(default_path)
        end
        if content then
            parts[#parts + 1] = "/* === " .. filename .. " === */\n" .. content
        else
            log.warn('[HTML-POST] Asset file not found: %s', filename)
        end
    end
    return table.concat(parts, "\n\n")
end

-- ============================================================================
-- Template Loading
-- ============================================================================

---Load a Lua template with overlay: try template-specific first, fall back to default.
---@param template string Template name
---@param name string Template name (e.g., "shell", "header")
---@return table Template module
local function load_template(template, name)
    if template and template ~= "" and template ~= "default" then
        local ok, mod = pcall(require, string.format("models.%s.html.templates.%s", template, name))
        if ok and mod then return mod end
    end
    return require(string.format("models.default.html.templates.%s", name))
end

-- ============================================================================
-- WASM Embedding
-- ============================================================================

---Build WASM loader script section.
---@param wasm_js string|nil SQLite WASM JavaScript loader
---@param wasm_base64 string|nil Base64-encoded SQLite WASM binary
---@return string HTML script elements for WASM
local function build_wasm_section(wasm_js, wasm_base64)
    if wasm_js and wasm_base64 then
        return string.format([[
  <script id="sqlite-wasm-binary" type="application/octet-stream">%s</script>
  <script>
  // Override fetch for embedded WASM binary
  (function() {
    const wasmElement = document.getElementById('sqlite-wasm-binary');
    if (!wasmElement) return;
    const wasmBase64 = wasmElement.textContent.trim();
    const originalFetch = window.fetch;
    window.fetch = function(url, options) {
      if (typeof url === 'string' && url.endsWith('sqlite3.wasm')) {
        const binary = atob(wasmBase64);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) {
          bytes[i] = binary.charCodeAt(i);
        }
        return Promise.resolve(new Response(bytes.buffer, {
          status: 200,
          headers: { 'Content-Type': 'application/wasm' }
        }));
      }
      return originalFetch.apply(this, arguments);
    };
  })();
  </script>
  <script>%s</script>]], wasm_base64, wasm_js)
    end

	    return [[
	  <script>
		    // SQLite WASM not embedded - search requires building vendor dependencies.
		    window.sqlite3InitModule = function() {
		      return Promise.reject(new Error('SQLite WASM not available. Run scripts/build.sh --install (or scripts/install.sh) to enable search.'));
		    };
		  </script>]]
end

---Build embedded database script element.
---@param db_base64 string|nil Base64-encoded database
---@return string HTML script element or empty string
local function build_db_script(db_base64)
    if not db_base64 then return "" end
    return string.format(
        '<script id="speccompiler-db" type="application/octet-stream">%s</script>',
        db_base64
    )
end

-- ============================================================================
-- Content Extraction (preserved from original)
-- ============================================================================

---Extract body content from HTML file.
---@param path string Path to HTML file
---@return string|nil HTML content between body tags
local function extract_body_content(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("*all")
    file:close()
    return content:match("<body[^>]*>(.-)</body>")
end

---Read and encode database file as base64.
---@param db_path string Path to database file
---@return string|nil Base64-encoded content
local function encode_database(db_path)
    local file = io.open(db_path, "rb")
    if not file then return nil end
    local content = file:read("*all")
    file:close()

    local ok, encoded = pcall(function()
        return pandoc.pipe("base64", {"-w0"}, content)
    end)

    if ok then
        return encoded:gsub("%s+", "")
    end
    return nil
end

-- ============================================================================
-- File Utilities (preserved from original)
-- ============================================================================

---Get the output directory from a file path.
---@param file_path string Full path to a file
---@return string Directory path
local function get_directory(file_path)
    return file_path:match("(.+)/[^/]+$") or "."
end

---List HTML files in a directory (excludes index.html).
---@param dir string Directory path
---@return table Sorted list of HTML filenames
local function list_html_files(dir)
    local files = {}
    local ok, result = pcall(function()
        return pandoc.pipe("ls", {"-1", dir}, "")
    end)

    if ok and result then
        for file in result:gmatch("[^\n]+") do
            if file:match("%.html$") and file ~= "index.html" then
                table.insert(files, file)
            end
        end
    end

    table.sort(files)
    return files
end

-- ============================================================================
-- Public API
-- ============================================================================

---Per-file postprocessor (called after each HTML file is written).
---No-op since finalize() does all the work.
---@param out_path string Path to the just-written HTML file
---@param _config table Configuration from project.yaml
---@param log table Logger instance
function M.run(out_path, _config, log)
    log.debug('[HTML-POST] File written: %s (bundling deferred to finalize)', out_path)
end

---Finalize postprocessor (called after ALL HTML files are written).
---Assembles everything into a single index.html web app.
---@param output_paths table Array of paths to generated HTML files
---@param config table Configuration with template, project_root, output_dir, db_path
---@param log table Logger instance
function M.finalize(output_paths, config, log)
    log.info('[HTML-POST] Finalizing: assembling web app from modular assets')

    -- Determine output directory
    local out_dir
    if config.output_dir then
        out_dir = config.output_dir:gsub("/+$", "") .. "/www"
    elseif #output_paths > 0 then
        out_dir = get_directory(output_paths[1])
    else
        log.warn('[HTML-POST] No output directory available')
        return
    end

    -- Scan for ALL HTML files (handles caching where only new files are in output_paths)
    local all_html_files = list_html_files(out_dir)
    if #all_html_files == 0 then
        log.warn('[HTML-POST] No HTML files found in %s', out_dir)
        return
    end

    local all_paths = {}
    for _, filename in ipairs(all_html_files) do
        all_paths[#all_paths + 1] = out_dir .. "/" .. filename
    end

    log.info('[HTML-POST] Found %d HTML files to bundle', #all_paths)

    -- ----------------------------------------------------------------
    -- 1. Load theme
    -- ----------------------------------------------------------------
    local template = config.template or "default"
    local theme = load_theme(template)
    log.debug('[HTML-POST] Loaded theme: %s', theme.name or "default")

    -- ----------------------------------------------------------------
    -- 2. Generate CSS: theme variables + modular CSS files (with overlay)
    -- ----------------------------------------------------------------
    local template_dir, default_dir = get_asset_dirs(template)
    local theme_css = generate_theme_css(theme)
    local module_css = concat_assets(template_dir, default_dir, "css", CSS_FILES, log)
    local css = theme_css .. "\n\n" .. module_css
    log.debug('[HTML-POST] CSS assembled: %d bytes', #css)

    -- ----------------------------------------------------------------
    -- 3. Concatenate JS modules (with overlay)
    -- ----------------------------------------------------------------
    local js = concat_assets(template_dir, default_dir, "js", JS_FILES, log)
    log.debug('[HTML-POST] JS assembled: %d bytes', #js)

    -- ----------------------------------------------------------------
    -- 4. Load Lua templates (with overlay)
    -- ----------------------------------------------------------------
    local shell_tpl     = load_template(template, "shell")
    local header_tpl    = load_template(template, "header")
    local sidebar_tpl   = load_template(template, "sidebar")
    local content_tpl   = load_template(template, "content")
    local inspector_tpl = load_template(template, "inspector")

    -- ----------------------------------------------------------------
    -- 5. Build content from per-spec HTML files
    -- ----------------------------------------------------------------
    local doc_sections = {}
    local is_first = true

	    for _, path in ipairs(all_paths) do
	        local filename = path:match("([^/]+)$")
	        local spec_id = filename:match("^(.+)%.html$")

        if spec_id then
            local body = extract_body_content(path)
            if body then
                doc_sections[#doc_sections + 1] = content_tpl.render_section(
                    spec_id, body, is_first
                )
                is_first = false
            end
	        end
	    end

    -- ----------------------------------------------------------------
    -- 6. Get project name
    -- ----------------------------------------------------------------
    local project_name = "Documentation"
    if config.project and config.project.name then
        project_name = config.project.name
    end

    -- ----------------------------------------------------------------
    -- 7. Build body HTML from templates
    -- ----------------------------------------------------------------
	    local body_html = table.concat({
	        '<div class="app">',
	        header_tpl.render({ project_name = project_name }),
	        '<main class="main">',
	        sidebar_tpl.render(),
	        '<div class="pane-resizer pane-resizer-sidebar" id="resizer-sidebar" role="separator" aria-orientation="vertical" aria-label="Resize navigation"></div>',
	        '<div class="content">',
	        table.concat(doc_sections, "\n"),
        '</div>',
        '<div class="pane-resizer pane-resizer-inspector" id="resizer-inspector" role="separator" aria-orientation="vertical" aria-label="Resize inspector"></div>',
        inspector_tpl.render(),
        '</main>',
        '</div>',
    }, "\n")

    -- ----------------------------------------------------------------
    -- 8. Encode database for embedding
    -- ----------------------------------------------------------------
    local db_base64 = nil
    if config.db_path then
        db_base64 = encode_database(config.db_path)
        if db_base64 then
            log.debug('[HTML-POST] Encoded database: %d bytes', #db_base64)
        else
            log.warn('[HTML-POST] Could not encode database: %s', config.db_path)
        end
    end

    -- ----------------------------------------------------------------
    -- 9. Load WASM files for self-contained builds
    -- ----------------------------------------------------------------
    local speccompiler_dist = os.getenv("SPECCOMPILER_DIST") or get_speccompiler_home()
    local wasm_js_path = speccompiler_dist .. "/vendor/sqlite/wasm/sqlite3.js"
    local wasm_bin_path = speccompiler_dist .. "/vendor/sqlite/wasm/sqlite3.wasm"

    local wasm_js = read_file(wasm_js_path)
    local wasm_base64 = nil

    if wasm_js then
        log.debug('[HTML-POST] Loaded sqlite3.js from: %s', wasm_js_path)
        local wasm_binary = read_file(wasm_bin_path)
        if wasm_binary then
            local ok, encoded = pcall(function()
                return pandoc.pipe("base64", {"-w0"}, wasm_binary)
            end)
            if ok then
                wasm_base64 = encoded:gsub("%s+", "")
                log.debug('[HTML-POST] Encoded sqlite3.wasm: %d bytes', #wasm_base64)
            end
        end
    end

	    if not wasm_js or not wasm_base64 then
	        log.warn('[HTML-POST] WASM files not found, search will be unavailable')
	    end

    -- ----------------------------------------------------------------
    -- 10. Build embedded data section (DB + WASM)
    -- ----------------------------------------------------------------
    local embedded_data = table.concat({
        build_db_script(db_base64),
        build_wasm_section(wasm_js, wasm_base64),
    }, "\n")

    -- ----------------------------------------------------------------
    -- 11. Assemble final HTML via shell template
    -- ----------------------------------------------------------------
    local html = shell_tpl.render({
        title = project_name,
        css = css,
        body_html = body_html,
        embedded_data = embedded_data,
        js = js,
    })

    -- ----------------------------------------------------------------
    -- 12. Write index.html
    -- ----------------------------------------------------------------
    local index_path = out_dir .. "/index.html"
    local file = io.open(index_path, "w")
    if file then
        file:write(html)
        file:close()
        log.info('[HTML-POST] Generated web app: %s', index_path)
    else
        log.error('[HTML-POST] Failed to write: %s', index_path)
    end

end

return M
