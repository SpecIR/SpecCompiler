---Listing type module for SpecCompiler.
---Handles code listings, quadros, and source code blocks.
---
---@module listing

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

---TRANSFORM: resolve a listing float to its custom JSON
---({content, language, line_count}) that the EMIT render hook decodes. Reads the
---language from the float's pandoc_attributes (stored at INITIALIZE).
---@param raw_content string
---@param float table Float record
---@param _log table|nil
---@return string resolved JSON string
local function transform(dctx)
    local raw_content = dctx.subject.raw_content
    local float = dctx.subject.float
    local content = raw_content or ""

    local language = nil
    if float.pandoc_attributes then
        local lang_match = float.pandoc_attributes:match('"language"%s*:%s*"([^"]+)"')
        if lang_match then
            language = normalize_language(lang_match)
        end
    end

    local line_count = select(2, content:gsub("\n", "\n")) + 1

    return string.format(
        '{"content":%q,"language":%s,"line_count":%d}',
        content,
        language and string.format('%q', language) or "null",
        line_count
    )
end

return {
    kind = "float",
    schema = {
        id = "LISTING",
        long_name = "Listing",
        description = "A code listing, source code block, or quadro (ABNT)",
        caption_format = "Listing",
        counter_group = "LISTING",  -- Own counter (Quadros in ABNT)
        aliases = { "listing", "src", "quadro", "code" },
    },
    hooks = {
        ---EMIT: convert the resolved listing AST into a Pandoc CodeBlock, from
        ---the canonical ctx (subject.resolved).
        ---@param ctx table Canonical ctx (subject.resolved, pandoc)
        ---@return table|nil Pandoc element or nil
        render = function(ctx)
            local resolved = ctx.subject.resolved
            local pandoc = ctx.pandoc
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
        end,

        -- TRANSFORM: resolve raw content to the listing JSON (decoded by render).
        transform = transform,
    },
}
