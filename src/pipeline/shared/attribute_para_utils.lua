---Shared helpers for attribute paragraph parsing.
---@module attribute_para_utils

local M = {}

local function unwrap_inline_span(inline)
    if not inline then
        return inline
    end
    if inline.t == "Span" then
        local span_content = inline.content or (inline.c and inline.c[2])
        if span_content and #span_content > 0 then
            return span_content[1]
        end
    end
    return inline
end

---Get text content from a Pandoc inline node.
---@param inline table
---@return string|nil
function M.get_inline_text(inline)
    local actual = unwrap_inline_span(inline)
    if not actual then return nil end
    if actual.t == "Str" then
        return actual.text or actual.c
    end
    if actual.t == "Space" or actual.t == "SoftBreak" then
        return " "
    end
    return nil
end

---Return attribute field name if paragraph starts with `name:`.
---@param para table
---@return string|nil
function M.get_field_name(para)
    local inlines = para and (para.c or para.content) or {}
    if #inlines == 0 then return nil end

    local first = unwrap_inline_span(inlines[1])
    if not first or first.t ~= "Str" then
        return nil
    end

    local text = first.text or first.c or ""
    local field = text:match("^([%w_]+):$")
    if field then
        return field
    end

    if not text:match("^[%w_]+$") then
        return nil
    end

    local parts = { text }
    for i = 2, #inlines do
        local inline_text = M.get_inline_text(inlines[i])
        if not inline_text then
            break
        end

        if inline_text == ":" then
            return table.concat(parts)
        elseif inline_text == "_" then
            parts[#parts + 1] = "_"
        elseif inline_text:match("^[%w_]+$") then
            parts[#parts + 1] = inline_text
        elseif inline_text:match("^([%w_]+):$") then
            parts[#parts + 1] = inline_text:match("^([%w_]+):$")
            return table.concat(parts)
        else
            break
        end
    end

    return nil
end

---@param para table
---@return boolean
function M.is_attribute_para(para)
    return M.get_field_name(para) ~= nil
end

---Extract value content after `name:`.
---@param para table
---@return string raw_value
---@return table|nil value_inlines
function M.extract_value_from_para(para)
    local inlines = para and (para.c or para.content) or {}
    local skip_count = 0
    local found_colon = false

    for i, inline in ipairs(inlines) do
        local text = M.get_inline_text(inline)
        if text then
            if text:match(":$") or text == ":" then
                found_colon = true
                skip_count = i
                if inlines[i + 1] and M.get_inline_text(inlines[i + 1]) == " " then
                    skip_count = i + 1
                end
                break
            end
        end
    end

    if not found_colon then
        return "", nil
    end

    local value_inlines = {}
    for i = skip_count + 1, #inlines do
        value_inlines[#value_inlines + 1] = inlines[i]
    end

    local raw_value = pandoc.utils.stringify(value_inlines)
    raw_value = raw_value:match("^%s*(.-)%s*$") or raw_value

    return raw_value, value_inlines
end

---Extract only string value (without returning inlines).
---@param para table
---@return string
function M.extract_para_value(para)
    local raw_value = M.extract_value_from_para(para)
    return raw_value
end

---Extract content blocks from a BlockQuote (unwraps Div sourcepos wrappers).
---@param bq table
---@return table
function M.extract_blocks_from_blockquote(bq)
    local blocks = {}
    local content = bq and (bq.c or bq.content) or {}

    for _, block in ipairs(content) do
        if block.t == "Div" then
            local div_content = block.c or block.content or {}
            if type(div_content[2]) == "table" then
                div_content = div_content[2]
            end
            for _, inner in ipairs(div_content) do
                blocks[#blocks + 1] = inner
            end
        else
            blocks[#blocks + 1] = block
        end
    end

    return blocks
end

---Collect paragraph blocks inside a BlockQuote.
---@param bq table
---@return table
function M.collect_paragraphs(bq)
    local paras = {}
    for _, block in ipairs(M.extract_blocks_from_blockquote(bq)) do
        if block.t == "Para" then
            paras[#paras + 1] = block
        end
    end
    return paras
end

return M
