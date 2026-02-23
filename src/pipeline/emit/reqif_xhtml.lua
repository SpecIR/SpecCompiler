---ReqIF XHTML Cache Builder for SpecCompiler.
---Precomputes XHTML/HTML fragments needed by the ReqIF exporter.
---
---This handler is conditional: it runs only when any configured output has
---format="reqif".
---
---@module reqif_xhtml
local M = {
    name = "reqif_xhtml",
    prerequisites = {}  -- Runs first in EMIT phase (others may depend on it)
}

local function has_reqif_output(contexts)
    for _, ctx in ipairs(contexts or {}) do
        if ctx.output_format == "reqif" then
            return true
        end
        if ctx.outputs and type(ctx.outputs) == "table" then
            for _, o in ipairs(ctx.outputs) do
                if o and o.format == "reqif" then
                    return true
                end
            end
        end
    end
    return false
end

local INLINE_TYPES = {
    Str = true, Space = true, SoftBreak = true, LineBreak = true,
    Emph = true, Strong = true, Span = true, Underline = true, Strikeout = true,
    SmallCaps = true, Superscript = true, Subscript = true,
    Code = true, Link = true, Image = true, Math = true, RawInline = true,
    Quoted = true, Cite = true, Note = true,
}

local function ast_json_to_html5(ast_json)
    if not ast_json or ast_json == "" then
        return ""
    end

    local doc_json = nil

    -- Fast path: full Pandoc doc
    if ast_json:match('^%s*{%s*"pandoc%-api%-version"') then
        doc_json = ast_json
    else
        local ok, decoded = pcall(pandoc.json.decode, ast_json)
        if not ok or not decoded then
            return ""
        end

        if type(decoded) == "table" and decoded.blocks then
            -- Already full document-like table: re-encode and read.
            doc_json = pandoc.json.encode(decoded)
        elseif type(decoded) == "table" and decoded.t then
            -- Single block/inline encoded as {t=..., c=...}
            doc_json = '{"pandoc-api-version":[1,23,1],"meta":{},"blocks":[' .. ast_json .. ']}'
        elseif type(decoded) == "table" and decoded[1] and type(decoded[1]) == "table" and decoded[1].t then
            -- Array: blocks or inlines
            if INLINE_TYPES[decoded[1].t] then
                local para = pandoc.Para(decoded)
                local wrapped = pandoc.Pandoc({ para })
                return pandoc.write(wrapped, "html5")
            end
            doc_json = '{"pandoc-api-version":[1,23,1],"meta":{},"blocks":' .. ast_json .. '}'
        else
            -- Unknown structure - stringify via JSON read fallback.
            doc_json = '{"pandoc-api-version":[1,23,1],"meta":{},"blocks":[]}'
        end
    end

    local ok, doc = pcall(pandoc.read, doc_json, "json")
    if not ok or not doc then
        return ""
    end

    local write_ok, html5 = pcall(pandoc.write, doc, "html5")
    if not write_ok or not html5 then
        return ""
    end
    return html5
end

local Queries = require("db.queries")

function M.on_emit(data, contexts, diagnostics)
    if not contexts or #contexts == 0 then
        return
    end

    if not has_reqif_output(contexts) then
        return
    end

    local log = contexts[1].log or { debug = function() end, info = function() end, warn = function() end, error = function() end }

    for _, ctx in ipairs(contexts) do
        local spec_id = ctx.spec_id
        if not spec_id then
            goto continue
        end

        log.info("[REQIF] Building XHTML cache for %s", spec_id)

        -- spec_objects.content_xhtml
        local objects = data:query_all(Queries.content.select_objects_for_xhtml,
            { spec_id = spec_id })

        data:begin_transaction()
        for _, obj in ipairs(objects or {}) do
            local html5 = ast_json_to_html5(obj.ast)
            data:execute(Queries.content.update_object_xhtml,
                { content_xhtml = html5, id = obj.id })
        end
        data:commit()

        -- spec_attribute_values.xhtml_value (datatype='XHTML')
        local attrs = data:query_all(Queries.content.select_xhtml_attributes_by_spec,
            { spec_id = spec_id })

        data:begin_transaction()
        for _, av in ipairs(attrs or {}) do
            local html5 = ast_json_to_html5(av.ast)
            data:execute(Queries.content.update_attribute_xhtml,
                { xhtml_value = html5, id = av.id })
        end
        data:commit()

        ::continue::
    end
end

return M

