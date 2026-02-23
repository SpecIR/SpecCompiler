---Listing type module for SpecCompiler.
---Handles code listings, quadros, and source code blocks.
---
---@module listing
local float_base = require("pipeline.shared.float_base")

local M = {}

M.float = {
    id = "LISTING",
    long_name = "Listing",
    description = "A code listing, source code block, or quadro (ABNT)",
    caption_format = "Listing",
    counter_group = "LISTING",  -- Own counter (Quadros in ABNT)
    aliases = { "listing", "src", "quadro", "code" },
    style_id = "LISTING",
}

-- ============================================================================
-- Syntax Highlighting Support
-- ============================================================================

local LANGUAGE_MAP = {
    c = "c",
    cpp = "cpp",
    cxx = "cpp",
    ["c++"] = "cpp",
    python = "python",
    py = "python",
    javascript = "javascript",
    js = "javascript",
    typescript = "typescript",
    ts = "typescript",
    lua = "lua",
    rust = "rust",
    rs = "rust",
    go = "go",
    java = "java",
    csharp = "csharp",
    cs = "csharp",
    sql = "sql",
    bash = "bash",
    sh = "bash",
    shell = "bash",
    yaml = "yaml",
    yml = "yaml",
    json = "json",
    xml = "xml",
    html = "html",
    css = "css",
    markdown = "markdown",
    md = "markdown",
}

local function normalize_language(lang)
    if not lang then return nil end
    return LANGUAGE_MAP[lang:lower()] or lang:lower()
end

-- ============================================================================
-- Handler
-- ============================================================================

-- Note: dkjson is used for decoding simple JSON (not Pandoc AST)
local dkjson = require("dkjson")

M.handler = {
    name = "listing_handler",
    prerequisites = {},

    on_transform = function(data, contexts, diagnostics)
        for _, ctx in ipairs(contexts) do
            local log = float_base.create_log(diagnostics)
            local floats = float_base.query_floats_by_type(data, ctx, "LISTING")

            for _, float in ipairs(floats or {}) do
                local content = float.raw_content or ""

                -- Extract language from attributes (stored during INITIALIZE phase)
                -- The float_handler stores language for src.c:label syntax
                local language = nil
                if float.pandoc_attributes then
                    local lang_match = float.pandoc_attributes:match('"language"%s*:%s*"([^"]+)"')
                    if lang_match then
                        language = normalize_language(lang_match)
                    end
                end

                -- Store resolved result with metadata
                local result = {
                    content = content,
                    language = language,
                    line_count = select(2, content:gsub("\n", "\n")) + 1,
                }

                local result_json = string.format(
                    '{"content":%q,"language":%s,"line_count":%d}',
                    content,
                    language and string.format('%q', language) or "null",
                    result.line_count
                )

                float_base.update_resolved_ast(data, float.id, result_json)

                log.debug("Processed listing %s (%s, %d lines)",
                    tostring(float.id),
                    language or "plain",
                    result.line_count
                )
            end
        end
    end,

    ---EMIT: Convert resolved_ast to Pandoc elements.
    ---@param block table Pandoc CodeBlock element
    ---@param ctx table Context with data, spec_id, log, preset
    ---@param float table Float record from database
    ---@param resolved string resolved_ast JSON string
    ---@return table|nil Pandoc element or nil
    on_render_CodeBlock = function(block, ctx, float, resolved)
        if not resolved or not pandoc then return nil end

        -- Parse our resolved_ast format: {"content":"...", "language":"...", "line_count":N}
        local listing_data, pos, err = dkjson.decode(resolved)
        if not listing_data or not listing_data.content then
            return nil
        end

        -- Create CodeBlock with language class for syntax highlighting
        -- Pandoc will render with SourceCode style
        local classes = listing_data.language and {listing_data.language} or {}
        return pandoc.CodeBlock(listing_data.content, pandoc.Attr("", classes))
    end
}

return M
