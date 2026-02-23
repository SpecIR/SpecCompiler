---@meta pipeline.shared.render_utils

---Render utilities for spec object handlers.
---Extracted from base_handler.lua to support direct on_render_SpecObject implementations.
---
---Usage: local render_utils = require("pipeline.shared.render_utils")

local M = {}

---Add a class to a Pandoc Div element safely.
---Handles both userdata (Pandoc List) and table formats for classes.
---@param div table Pandoc Div element
---@param class_name string Class to add
function M.add_class_to_div(div, class_name)
    if div.classes then
        -- Try List:insert method first (Pandoc List)
        if type(div.classes.insert) == "function" then
            div.classes:insert(class_name)
        else
            -- Fallback to table.insert
            table.insert(div.classes, class_name)
        end
    elseif div.attr and div.attr[2] then
        -- Access via attr: {id, classes, kvpairs}
        table.insert(div.attr[2], class_name)
    end
end

---Add page break based on starts_on value.
---@param blocks table Target blocks array
---@param starts_on string|nil "next" (regular), "odd", "even", or nil/"none" (no break)
function M.add_page_break(blocks, starts_on)
    if starts_on and starts_on ~= "none" then
        local marker = "page-break"
        if starts_on == "odd" or starts_on == "even" then
            marker = "page-break:" .. starts_on
        end
        table.insert(blocks, pandoc.RawBlock("speccompiler", marker))
    end
end

---Add header blocks with idempotency marking.
---Wraps blocks in Div with spec-object-header class to prevent accumulation
---when TRANSFORM runs on cached documents.
---@param blocks table Target blocks array
---@param header_result table|nil Header blocks from handler
function M.add_header_blocks(blocks, header_result)
    if not header_result then return end

    local result_type = type(header_result)
    if result_type ~= "table" and result_type ~= "userdata" then return end

    if header_result.t then
        -- Single Pandoc element
        if header_result.t == "Div" then
            -- Add marker class to existing Div (preserves original classes/styles)
            M.add_class_to_div(header_result, "spec-object-header")
            table.insert(blocks, header_result)
        else
            -- Wrap non-Div elements in marker Div
            local marker_div = pandoc.Div({header_result}, pandoc.Attr("", {"spec-object-header"}, {}))
            table.insert(blocks, marker_div)
        end
    else
        -- Array of elements
        for _, b in ipairs(header_result) do
            if b.t == "Div" then
                M.add_class_to_div(b, "spec-object-header")
                table.insert(blocks, b)
            else
                local marker_div = pandoc.Div({b}, pandoc.Attr("", {"spec-object-header"}, {}))
                table.insert(blocks, marker_div)
            end
        end
    end
end

---Add blocks to target array (handles single element or array).
---@param blocks table Target blocks array
---@param source table|nil Source blocks
function M.add_blocks(blocks, source)
    if not source then return end

    local result_type = type(source)
    if result_type ~= "table" and result_type ~= "userdata" then return end

    if source.t then
        -- Single Pandoc element
        table.insert(blocks, source)
    else
        -- Array of elements
        for _, b in ipairs(source) do
            table.insert(blocks, b)
        end
    end
end

return M
