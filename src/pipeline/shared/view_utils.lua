---View utilities for SpecCompiler.
---Shared functions for Pandoc JSON handling in views.
---
---@module view_utils
local M = {}

---Wrap MathML in HTML for Pandoc parsing.
---@param mathml string MathML content
---@return string html HTML document containing MathML
function M.wrap_mathml_as_html(mathml)
    return string.format('<!DOCTYPE html><html><body>%s</body></html>', mathml)
end

---Serialize a Pandoc element to JSON.
---@param element table Pandoc element (Block or Inline)
---@return string|nil json JSON string or nil on error
function M.to_pandoc_json(element)
    -- Wrap in document structure
    local doc
    if element.t and (element.t == "Para" or element.t == "Plain" or element.t:match("^Header")) then
        -- Already a block
        doc = pandoc.Pandoc({element})
    else
        -- Wrap inline in Para
        doc = pandoc.Pandoc({pandoc.Para({element})})
    end
    return pandoc.write(doc, "json")
end

---Deserialize JSON to Pandoc document.
---@param json string JSON string
---@return table|nil doc Pandoc document or nil on error
function M.from_pandoc_json(json)
    if not json then return nil end
    local ok, doc = pcall(pandoc.read, json, "json")
    if ok then return doc end
    return nil
end

---Look up resolved_ast from spec_views.
---@param data DataManager
---@param spec_id string Specification identifier
---@param view_type string View type (e.g., "MATH_INLINE", "ABBREV")
---@param raw_content string The raw_ast content to match
---@return string|nil resolved_ast The resolved AST or nil
function M.lookup_resolved_ast(data, spec_id, view_type, raw_content)
    local result = data:query_one([[
        SELECT resolved_ast FROM spec_views
        WHERE specification_ref = :spec_id
          AND view_type_ref = :view_type
          AND raw_ast = :raw_content
          AND resolved_ast IS NOT NULL
        LIMIT 1
    ]], {
        spec_id = spec_id,
        view_type = view_type,
        raw_content = raw_content
    })
    return result and result.resolved_ast or nil
end

return M
