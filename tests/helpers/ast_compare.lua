-- AST comparison utilities for Lua-based test oracles
-- Compares Pandoc AST structures with comprehensive mismatch reporting

local M = {}

--- Default comparison options
M.defaults = {
    ignore_data_pos = false,  -- Skip data-pos attribute comparison
    strip_spans = false,      -- Strip data-pos spans before comparison
    collect_all = true,       -- Collect all mismatches vs stop at first
    max_mismatches = 50,      -- Limit reported mismatches
}

-- ============================================================================
-- Tokenization Helpers (use Pandoc to ensure consistent tokenization)
-- ============================================================================

---Parse text as CommonMark and return inlines (properly tokenized by Pandoc)
---Uses commonmark_x for consistent parsing without citation extension
---@param text string CommonMark text (single line, inline content)
---@return table Array of Pandoc inline elements
function M.inlines(text)
    if not text or text == "" then return {} end
    -- Use commonmark_x for consistent parsing (no citations)
    local doc = pandoc.read(text, "commonmark_x")
    -- Extract inlines from first paragraph
    if doc.blocks[1] and doc.blocks[1].content then
        return doc.blocks[1].content
    end
    return {}
end

---Parse text as CommonMark and return blocks
---@param text string CommonMark text (can be multi-line)
---@return table Array of Pandoc block elements
function M.blocks(text)
    if not text or text == "" then return {} end
    local doc = pandoc.read(text, "commonmark_x")
    return doc.blocks or {}
end

---Parse text and return first block's content (inlines) - useful for Para content
---@param text string Markdown text
---@return table Array of Pandoc inline elements
function M.para_content(text)
    return M.inlines(text)
end

-- ============================================================================
-- Span Stripping (removes data-pos tracking spans)
-- ============================================================================

---Check if a Span is a sourcepos tracking span (not user-authored).
---Matches both pre-3.1.10 (data-pos only) and post-3.1.10 (data-pos + wrapper).
---@param elem table Pandoc element
---@return boolean
local function is_tracking_span(elem)
    if not elem or elem.t ~= "Span" then return false end

    -- Use Pandoc's accessor API
    local id = elem.identifier or ""
    local classes = elem.classes or {}
    local attrs = elem.attributes or {}

    -- Empty id, no classes
    if id ~= "" then return false end
    if #classes > 0 then return false end

    -- Check attributes - should only have data-pos (and optionally wrapper)
    -- attrs is a Pandoc AttributeList, iterate with pairs
    local attr_count = 0
    local has_data_pos = false
    for k, _ in pairs(attrs) do
        attr_count = attr_count + 1
        if k == "data-pos" then
            has_data_pos = true
        elseif k ~= "wrapper" then
            return false
        end
    end

    return has_data_pos and attr_count <= 2
end

---Merge adjacent Str tokens into single tokens
---@param inlines table Array of inline elements
---@return table Merged inlines
local function merge_adjacent_strs(inlines)
    if not inlines or type(inlines) ~= "table" then return inlines end

    local result = {}
    local pending_text = nil

    for _, inline in ipairs(inlines) do
        if inline.t == "Str" then
            -- Accumulate string text
            if pending_text then
                pending_text = pending_text .. inline.text
            else
                pending_text = inline.text
            end
        else
            -- Flush pending text before non-Str element
            if pending_text then
                table.insert(result, pandoc.Str(pending_text))
                pending_text = nil
            end
            table.insert(result, inline)
        end
    end

    -- Flush any remaining text
    if pending_text then
        table.insert(result, pandoc.Str(pending_text))
    end

    return result
end

---Strip tracking spans from inlines, returning unwrapped content
---@param inlines table Array of inline elements
---@return table Cleaned inlines
local function strip_spans_from_inlines(inlines)
    if not inlines or type(inlines) ~= "table" then return inlines end

    local result = {}
    for _, inline in ipairs(inlines) do
        if is_tracking_span(inline) then
            -- Unwrap span contents (use Pandoc accessor)
            local content = inline.content or {}
            for _, inner in ipairs(content) do
                table.insert(result, inner)
            end
        elseif inline.t == "Span" then
            -- Non-tracking span: recurse into content
            local content = inline.content or {}
            local stripped_content = strip_spans_from_inlines(content)
            -- Create new span with stripped content
            local new_span = pandoc.Span(stripped_content, inline.attr)
            table.insert(result, new_span)
        elseif inline.t == "Link" then
            -- Recurse into link content
            local content = inline.content or {}
            local stripped_content = strip_spans_from_inlines(content)
            local new_link = pandoc.Link(stripped_content, inline.target, inline.title, inline.attr)
            table.insert(result, new_link)
        elseif inline.t == "Image" then
            -- Recurse into image caption
            local content = inline.caption or {}
            local stripped_content = strip_spans_from_inlines(content)
            local new_img = pandoc.Image(stripped_content, inline.src, inline.title, inline.attr)
            table.insert(result, new_img)
        elseif inline.t == "Strong" then
            local stripped_content = strip_spans_from_inlines(inline.content or {})
            table.insert(result, pandoc.Strong(stripped_content))
        elseif inline.t == "Emph" then
            local stripped_content = strip_spans_from_inlines(inline.content or {})
            table.insert(result, pandoc.Emph(stripped_content))
        elseif inline.t == "Strikeout" then
            local stripped_content = strip_spans_from_inlines(inline.content or {})
            table.insert(result, pandoc.Strikeout(stripped_content))
        elseif inline.t == "Superscript" then
            local stripped_content = strip_spans_from_inlines(inline.content or {})
            table.insert(result, pandoc.Superscript(stripped_content))
        elseif inline.t == "Subscript" then
            local stripped_content = strip_spans_from_inlines(inline.content or {})
            table.insert(result, pandoc.Subscript(stripped_content))
        else
            table.insert(result, inline)
        end
    end

    -- Merge adjacent Str tokens after stripping
    return merge_adjacent_strs(result)
end

---Strip tracking spans from a single block, returning new block
---@param block table Pandoc block element
---@return table New block with stripped spans
local function strip_block(block)
    if not block then return block end

    if block.t == "Para" then
        local stripped = strip_spans_from_inlines(block.content or {})
        return pandoc.Para(stripped)
    elseif block.t == "Plain" then
        local stripped = strip_spans_from_inlines(block.content or {})
        return pandoc.Plain(stripped)
    elseif block.t == "Header" then
        local stripped = strip_spans_from_inlines(block.content or {})
        return pandoc.Header(block.level, stripped, block.attr)
    elseif block.t == "Div" then
        local new_content = {}
        for _, inner_block in ipairs(block.content or {}) do
            table.insert(new_content, strip_block(inner_block))
        end
        return pandoc.Div(new_content, block.attr)
    elseif block.t == "BlockQuote" then
        local new_content = {}
        for _, inner_block in ipairs(block.content or {}) do
            table.insert(new_content, strip_block(inner_block))
        end
        return pandoc.BlockQuote(new_content)
    elseif block.t == "BulletList" then
        local new_items = {}
        for _, item in ipairs(block.content or {}) do
            local new_item = {}
            for _, inner_block in ipairs(item) do
                table.insert(new_item, strip_block(inner_block))
            end
            table.insert(new_items, new_item)
        end
        return pandoc.BulletList(new_items)
    elseif block.t == "OrderedList" then
        local new_items = {}
        for _, item in ipairs(block.content or {}) do
            local new_item = {}
            for _, inner_block in ipairs(item) do
                table.insert(new_item, strip_block(inner_block))
            end
            table.insert(new_items, new_item)
        end
        return pandoc.OrderedList(new_items, block.listAttributes)
    else
        -- Return other blocks unchanged
        return block
    end
end

---Strip all data-pos tracking spans from a Pandoc document
---Returns modified document with spans unwrapped
---@param doc Pandoc.Pandoc
---@return Pandoc.Pandoc
function M.strip_tracking_spans(doc)
    if not doc then return doc end

    -- Process all blocks
    local new_blocks = {}
    for _, block in ipairs(doc.blocks or {}) do
        table.insert(new_blocks, strip_block(block))
    end

    -- Replace blocks in document
    doc.blocks = new_blocks
    return doc
end

--- Check if a value is an array (sequential integer keys starting at 1)
---@param t table
---@return boolean
local function is_array(t)
    if type(t) ~= "table" then return false end
    local i = 0
    for _ in pairs(t) do
        i = i + 1
        if t[i] == nil then return false end
    end
    return true
end

--- Check if a table represents a Pandoc Attr (id, classes, attributes)
---@param t table
---@return boolean
local function is_attr(t)
    if type(t) ~= "table" then return false end
    -- Attr is a 3-element array: [identifier, classes[], attributes[]]
    if #t ~= 3 then return false end
    if type(t[1]) ~= "string" then return false end
    if type(t[2]) ~= "table" then return false end
    if type(t[3]) ~= "table" then return false end
    return true
end

--- Format a path component
---@param base string
---@param key string|number
---@return string
local function format_path(base, key)
    if base == "" then
        if type(key) == "number" then
            return string.format("[%d]", key - 1)  -- 0-indexed for readability
        else
            return tostring(key)
        end
    end
    if type(key) == "number" then
        return string.format("%s[%d]", base, key - 1)
    else
        return string.format("%s.%s", base, key)
    end
end

--- Get the Pandoc element type tag
---@param elem table
---@return string|nil
local function get_tag(elem)
    if type(elem) ~= "table" then return nil end
    return elem.t or elem.tag
end

--- Convert attributes array [[k,v],...] to map for comparison
---@param attrs table
---@return table
local function attrs_to_map(attrs)
    local map = {}
    for _, pair in ipairs(attrs) do
        if type(pair) == "table" and #pair == 2 then
            map[pair[1]] = pair[2]
        end
    end
    return map
end

--- Compare attribute arrays as unordered sets
---@param actual table
---@param expected table
---@param path string
---@param mismatches table
---@param options table
local function compare_attrs_as_set(actual, expected, path, mismatches, options)
    local actual_map = attrs_to_map(actual)
    local expected_map = attrs_to_map(expected)

    -- Check for missing/different values in expected
    for k, v in pairs(expected_map) do
        -- Skip data-pos if configured
        if not (options.ignore_data_pos and k == "data-pos") then
            if actual_map[k] == nil then
                table.insert(mismatches, {
                    path = format_path(path, k),
                    type = "missing_key",
                    expected = v,
                    actual = "nil"
                })
            elseif actual_map[k] ~= v then
                table.insert(mismatches, {
                    path = format_path(path, k),
                    type = "value_mismatch",
                    expected = v,
                    actual = actual_map[k]
                })
            end
        end
    end

    -- Check for extra keys in actual
    for k, v in pairs(actual_map) do
        if not (options.ignore_data_pos and k == "data-pos") then
            if expected_map[k] == nil then
                table.insert(mismatches, {
                    path = format_path(path, k),
                    type = "extra_key",
                    expected = "nil",
                    actual = v
                })
            end
        end
    end
end

--- Compare two Pandoc Attr structures
---@param actual table
---@param expected table
---@param path string
---@param mismatches table
---@param options table
local function compare_attr(actual, expected, path, mismatches, options)
    -- Compare identifier (index 1)
    if actual[1] ~= expected[1] then
        table.insert(mismatches, {
            path = format_path(path, "id"),
            type = "value_mismatch",
            expected = expected[1],
            actual = actual[1]
        })
    end

    -- Compare classes (index 2) - order matters
    local actual_classes = actual[2] or {}
    local expected_classes = expected[2] or {}
    if #actual_classes ~= #expected_classes then
        table.insert(mismatches, {
            path = format_path(path, "classes"),
            type = "length_mismatch",
            expected = #expected_classes,
            actual = #actual_classes
        })
    else
        for i = 1, #expected_classes do
            if actual_classes[i] ~= expected_classes[i] then
                table.insert(mismatches, {
                    path = format_path(format_path(path, "classes"), i),
                    type = "value_mismatch",
                    expected = expected_classes[i],
                    actual = actual_classes[i]
                })
            end
        end
    end

    -- Compare attributes (index 3) - unordered
    compare_attrs_as_set(actual[3] or {}, expected[3] or {}, format_path(path, "attrs"), mismatches, options)
end

--- Compare Pandoc element attributes using accessor API
---@param actual userdata Pandoc element
---@param expected userdata Pandoc element
---@param path string
---@param mismatches table
---@param options table
local function compare_pandoc_attr(actual, expected, path, mismatches, options)
    -- Compare identifier
    if actual.identifier ~= expected.identifier then
        table.insert(mismatches, {
            path = format_path(path, "identifier"),
            type = "value_mismatch",
            expected = expected.identifier,
            actual = actual.identifier
        })
    end

    -- Compare classes
    local actual_classes = actual.classes or {}
    local expected_classes = expected.classes or {}
    if #actual_classes ~= #expected_classes then
        table.insert(mismatches, {
            path = format_path(path, "classes"),
            type = "length_mismatch",
            expected = #expected_classes,
            actual = #actual_classes
        })
    else
        for i = 1, #expected_classes do
            if actual_classes[i] ~= expected_classes[i] then
                table.insert(mismatches, {
                    path = format_path(format_path(path, "classes"), i),
                    type = "value_mismatch",
                    expected = expected_classes[i],
                    actual = actual_classes[i]
                })
            end
        end
    end

    -- Compare attributes (as unordered set, respecting ignore_data_pos)
    local actual_attrs = actual.attributes or {}
    local expected_attrs = expected.attributes or {}

    -- Check expected attributes exist in actual
    for k, v in pairs(expected_attrs) do
        if not (options.ignore_data_pos and k == "data-pos") then
            if actual_attrs[k] == nil then
                table.insert(mismatches, {
                    path = format_path(format_path(path, "attributes"), k),
                    type = "missing_key",
                    expected = v,
                    actual = "nil"
                })
            elseif actual_attrs[k] ~= v then
                table.insert(mismatches, {
                    path = format_path(format_path(path, "attributes"), k),
                    type = "value_mismatch",
                    expected = v,
                    actual = actual_attrs[k]
                })
            end
        end
    end

    -- Check for extra attributes in actual
    for k, v in pairs(actual_attrs) do
        if not (options.ignore_data_pos and k == "data-pos") then
            if expected_attrs[k] == nil then
                table.insert(mismatches, {
                    path = format_path(format_path(path, "attributes"), k),
                    type = "extra_key",
                    expected = "nil",
                    actual = v
                })
            end
        end
    end
end

--- Check if value is a Pandoc document
---@param v any
---@return boolean
local function is_pandoc_doc(v)
    if type(v) ~= "userdata" then return false end
    -- Pandoc documents have .blocks and .meta but no .t
    return v.blocks ~= nil and v.meta ~= nil and v.t == nil
end

--- Check if value is a Pandoc element (block or inline)
---@param v any
---@return boolean
local function is_pandoc_element(v)
    if type(v) ~= "userdata" then return false end
    return v.t ~= nil
end

--- Main comparison function (recursive)
---@param actual any
---@param expected any
---@param path string
---@param mismatches table
---@param options table
local function compare_impl(actual, expected, path, mismatches, options)
    -- Check max mismatches limit
    if #mismatches >= options.max_mismatches then
        return
    end

    -- Handle Pandoc documents specially
    if is_pandoc_doc(actual) and is_pandoc_doc(expected) then
        -- Compare blocks
        compare_impl(actual.blocks, expected.blocks, format_path(path, "blocks"), mismatches, options)
        -- Compare meta (skip for now, meta comparison is complex)
        -- compare_impl(actual.meta, expected.meta, format_path(path, "meta"), mismatches, options)
        return
    end

    -- Handle Pandoc elements (blocks/inlines)
    if is_pandoc_element(actual) and is_pandoc_element(expected) then
        local actual_tag = actual.t
        local expected_tag = expected.t

        if actual_tag ~= expected_tag then
            table.insert(mismatches, {
                path = path,
                type = "element_type_mismatch",
                expected = expected_tag,
                actual = actual_tag
            })
            return
        end

        -- Compare based on element type
        if actual_tag == "Str" then
            if actual.text ~= expected.text then
                table.insert(mismatches, {
                    path = format_path(path, "text"),
                    type = "value_mismatch",
                    expected = expected.text,
                    actual = actual.text
                })
            end
        elseif actual_tag == "Space" or actual_tag == "SoftBreak" or actual_tag == "LineBreak" then
            -- No content to compare
        elseif actual_tag == "Header" then
            if actual.level ~= expected.level then
                table.insert(mismatches, {
                    path = format_path(path, "level"),
                    type = "value_mismatch",
                    expected = expected.level,
                    actual = actual.level
                })
            end
            compare_pandoc_attr(actual, expected, path, mismatches, options)
            compare_impl(actual.content, expected.content, format_path(path, "content"), mismatches, options)
        elseif actual_tag == "Div" or actual_tag == "Span" then
            compare_pandoc_attr(actual, expected, path, mismatches, options)
            compare_impl(actual.content, expected.content, format_path(path, "content"), mismatches, options)
        elseif actual_tag == "Para" or actual_tag == "Plain" then
            compare_impl(actual.content, expected.content, format_path(path, "content"), mismatches, options)
        elseif actual_tag == "BlockQuote" then
            compare_impl(actual.content, expected.content, format_path(path, "content"), mismatches, options)
        elseif actual_tag == "Link" then
            compare_pandoc_attr(actual, expected, path, mismatches, options)
            compare_impl(actual.content, expected.content, format_path(path, "content"), mismatches, options)
            if actual.target ~= expected.target then
                table.insert(mismatches, {
                    path = format_path(path, "target"),
                    type = "value_mismatch",
                    expected = expected.target,
                    actual = actual.target
                })
            end
        else
            -- Generic element comparison - compare content if present
            if actual.content and expected.content then
                compare_impl(actual.content, expected.content, format_path(path, "content"), mismatches, options)
            end
        end
        return
    end

    -- Type check for non-Pandoc values
    local actual_type = type(actual)
    local expected_type = type(expected)

    if actual_type ~= expected_type then
        table.insert(mismatches, {
            path = path,
            type = "type_mismatch",
            expected = expected_type,
            actual = actual_type
        })
        return
    end

    -- Primitive comparison
    if actual_type ~= "table" then
        if actual ~= expected then
            table.insert(mismatches, {
                path = path,
                type = "value_mismatch",
                expected = tostring(expected),
                actual = tostring(actual)
            })
        end
        return
    end

    -- Both are tables - check Pandoc element types
    local actual_tag = get_tag(actual)
    local expected_tag = get_tag(expected)

    if actual_tag ~= expected_tag then
        table.insert(mismatches, {
            path = path,
            type = "element_type_mismatch",
            expected = expected_tag or "table",
            actual = actual_tag or "table"
        })
        return  -- Don't descend into mismatched element types
    end

    -- Special handling for Pandoc Attr
    if is_attr(actual) and is_attr(expected) then
        compare_attr(actual, expected, path, mismatches, options)
        return
    end

    -- Array comparison (ordered)
    if is_array(actual) and is_array(expected) then
        if #actual ~= #expected then
            table.insert(mismatches, {
                path = path,
                type = "length_mismatch",
                expected = #expected,
                actual = #actual
            })
        end
        local max_len = math.max(#actual, #expected)
        for i = 1, max_len do
            if actual[i] == nil then
                table.insert(mismatches, {
                    path = format_path(path, i),
                    type = "missing_element",
                    expected = tostring(expected[i]),
                    actual = "nil"
                })
            elseif expected[i] == nil then
                table.insert(mismatches, {
                    path = format_path(path, i),
                    type = "extra_element",
                    expected = "nil",
                    actual = tostring(actual[i])
                })
            else
                compare_impl(actual[i], expected[i], format_path(path, i), mismatches, options)
            end
            if #mismatches >= options.max_mismatches then
                return
            end
        end
        return
    end

    -- Object/table comparison
    local seen = {}

    -- Check expected keys
    for k, v in pairs(expected) do
        seen[k] = true
        local child_path = format_path(path, k)
        if actual[k] == nil then
            table.insert(mismatches, {
                path = child_path,
                type = "missing_key",
                expected = type(v) == "table" and (get_tag(v) or "table") or tostring(v),
                actual = "nil"
            })
        else
            compare_impl(actual[k], v, child_path, mismatches, options)
        end
        if #mismatches >= options.max_mismatches then
            return
        end
    end

    -- Check for extra keys in actual
    for k, v in pairs(actual) do
        if not seen[k] then
            table.insert(mismatches, {
                path = format_path(path, k),
                type = "extra_key",
                expected = "nil",
                actual = type(v) == "table" and (get_tag(v) or "table") or tostring(v)
            })
        end
        if #mismatches >= options.max_mismatches then
            return
        end
    end
end

--- Format mismatches into a readable report
---@param mismatches table[]
---@return string
function M.format_report(mismatches)
    if #mismatches == 0 then
        return "AST comparison passed"
    end

    local lines = {
        string.format("AST comparison failed with %d mismatch%s:\n",
            #mismatches,
            #mismatches == 1 and "" or "es")
    }

    for i, m in ipairs(mismatches) do
        table.insert(lines, string.format(
            "  [%d] %s: %s\n      Expected: %s\n      Actual:   %s",
            i,
            m.path,
            m.type,
            tostring(m.expected),
            tostring(m.actual)
        ))
    end

    return table.concat(lines, "\n")
end

--- Compare two AST structures and return mismatches
---@param actual table Actual Pandoc document or element
---@param expected table Expected Pandoc document or element
---@param options table|nil Comparison options
---@return table[] mismatches Array of mismatch objects
function M.compare(actual, expected, options)
    options = options or {}
    for k, v in pairs(M.defaults) do
        if options[k] == nil then
            options[k] = v
        end
    end

    local mismatches = {}
    compare_impl(actual, expected, "root", mismatches, options)
    return mismatches
end

--- Assert two AST structures are equal
---@param actual table Actual Pandoc document or element
---@param expected table Expected Pandoc document or element
---@param options table|nil Comparison options
---@return boolean success
---@return string|nil error_report
function M.assert_equal(actual, expected, options)
    local mismatches = M.compare(actual, expected, options)
    if #mismatches == 0 then
        return true, nil
    else
        return false, M.format_report(mismatches)
    end
end

return M
