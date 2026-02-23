---XML Utilities for SpecCompiler.
---Provides XML escaping, DOM construction, parsing, and manipulation.
---Uses SLAXML for DOM operations (parsing, modification, serialization).
---
---@module xml
local M = {}

-- ============================================================================
-- SLAXML DOM Support (lazy-loaded)
-- ============================================================================

local slaxdom = nil

---Lazy-load SLAXML DOM module (installed via Docker)
---@return table SLAXML DOM module
local function get_slaxdom()
    if not slaxdom then
        -- Try different require paths for SLAXML
        local ok, dom = pcall(require, "slaxdom")
        if not ok then
            ok, dom = pcall(require, "slaxml.slaxdom")
        end
        if ok then
            slaxdom = dom
        else
            error("SLAXML not found. Install via Docker or luarocks.")
        end
    end
    return slaxdom
end

-- ============================================================================
-- String Operations
-- ============================================================================

---Escape special XML characters in text content.
---Order is critical: & must be escaped first to avoid double-escaping.
---@param text any Value to escape (will be converted to string)
---@return string Escaped text safe for XML content
function M.escape(text)
    if text == nil then return "" end
    text = tostring(text)
    text = text:gsub("&", "&amp;")   -- Must be first
    text = text:gsub("<", "&lt;")
    text = text:gsub(">", "&gt;")
    text = text:gsub('"', "&quot;")
    text = text:gsub("'", "&apos;")
    return text
end

---Escape attribute value (same as content escaping).
---@param value any Attribute value to escape
---@return string Escaped value safe for XML attributes
M.escape_attr = M.escape

---Unescape XML entities back to original characters.
---@param text string Text with XML entities
---@return string Unescaped text
function M.unescape(text)
    if text == nil then return "" end
    text = tostring(text)
    text = text:gsub("&apos;", "'")
    text = text:gsub("&quot;", '"')
    text = text:gsub("&gt;", ">")
    text = text:gsub("&lt;", "<")
    text = text:gsub("&amp;", "&")  -- Must be last
    return text
end

-- ============================================================================
-- DOM Parsing and Serialization
-- ============================================================================

---Parse XML string to DOM tree.
---@param xml_string string XML content to parse
---@param opts table|nil Parse options (passed to SLAXML)
---@return table DOM tree with root element
function M.parse(xml_string, opts)
    opts = opts or {}
    local dom = get_slaxdom()
    return dom:dom(xml_string, opts)
end

---Serialize DOM tree back to XML string.
---@param doc table DOM tree from parse()
---@param opts table|nil Serialize options: {indent=number, sort=boolean}
---@return string Serialized XML
function M.serialize(doc, opts)
    opts = opts or {}
    local dom = get_slaxdom()
    return dom:xml(doc, {
        indent = opts.indent,
        sort = opts.sort or false
    })
end

---Serialize a single DOM element to XML string (without document wrapper).
---Unlike serialize(), this works with individual elements created via node().
---@param el table Element node
---@return string Serialized XML string
function M.serialize_element(el)
    local function serialize_node(node)
        if not node then return "" end

        -- Text node
        if node.type == "text" then
            return M.escape(node.value or "")
        end

        -- Raw node (pre-formed XML, inserted verbatim)
        if node.type == "raw" then
            return node.value or ""
        end

        -- Element node
        if node.type == "element" or node.name then
            local parts = {"<" .. (node.nsPrefix and (node.nsPrefix .. ":") or "") .. node.name}

            -- Serialize attributes
            if node.attr then
                -- Use indexed entries which preserve namespace prefixes
                for i, attr in ipairs(node.attr) do
                    if type(attr) == "table" and attr.name then
                        local attr_name = attr.nsPrefix and (attr.nsPrefix .. ":" .. attr.name) or attr.name
                        table.insert(parts, ' ' .. attr_name .. '="' .. M.escape_attr(attr.value) .. '"')
                    end
                end
            end

            -- Self-closing or with children
            local kids = node.kids or {}
            if #kids == 0 then
                table.insert(parts, "/>")
            else
                table.insert(parts, ">")
                for _, kid in ipairs(kids) do
                    table.insert(parts, serialize_node(kid))
                end
                table.insert(parts, "</" .. (node.nsPrefix and (node.nsPrefix .. ":") or "") .. node.name .. ">")
            end

            return table.concat(parts)
        end

        return ""
    end

    return serialize_node(el)
end

-- ============================================================================
-- DOM Construction
-- ============================================================================

---Create a text node.
---@param value string Text content
---@return table Text node
function M.text(value)
    return {
        type = "text",
        value = value or ""
    }
end

---Create a raw XML node (pre-formed content, not escaped).
---Use for embedding trusted, already-formed OOXML content (e.g., OMML math markup).
---WARNING: Content is inserted verbatim — caller must ensure well-formedness.
---@param content string Pre-formed XML content
---@return table Raw node
function M.raw(content)
    return {
        type = "raw",
        value = content or ""
    }
end

---Create a node with attributes and children in one call.
---Creates SLAXML-compatible element structure for proper serialization.
---@param tag string Element tag name (e.g., "w:p", "w:tbl")
---@param attributes table|nil Attributes table {["attr-name"]=value, ...}
---@param children table|nil Array of child nodes
---@return table New element node
function M.node(tag, attributes, children)
    -- Parse tag for namespace prefix
    local nsPrefix, localName = tag:match("^([^:]+):(.+)$")
    if not localName then
        localName = tag
        nsPrefix = nil
    end

    local el = {
        type = "element",
        name = localName,
        nsPrefix = nsPrefix,
        kids = children or {}
    }

    -- Build SLAXML-compatible attr table
    if attributes and next(attributes) then
        el.attr = {}
        local idx = 1
        for name, value in pairs(attributes) do
            -- Parse attribute name for namespace prefix
            local attrNsPrefix, attrLocalName = name:match("^([^:]+):(.+)$")
            if not attrLocalName then
                attrLocalName = name
                attrNsPrefix = nil
            end

            -- Direct access entry
            el.attr[attrLocalName] = value

            -- Indexed entry for SLAXML serialization
            el.attr[idx] = {
                type = "attribute",
                name = attrLocalName,
                value = value,
                nsPrefix = attrNsPrefix,
                parent = el
            }
            idx = idx + 1
        end
    end

    -- Set parent references for children
    for _, child in ipairs(el.kids) do
        child.parent = el
    end
    return el
end

---Create new element node (alias for node without children).
---@param name string Element tag name
---@param attrs table|nil Attributes table {name=value, ...}
---@param nsURI string|nil Namespace URI
---@return table New element node
function M.element(name, attrs, nsURI)
    local el = M.node(name, attrs)
    el.nsURI = nsURI
    return el
end

-- ============================================================================
-- DOM Queries
-- ============================================================================

---Helper: Check if element matches a tag name (handles namespace prefixes).
---@param node table Element node to check
---@param name string Tag name to match (may include namespace prefix)
---@return boolean true if node matches the name
local function element_matches_name(node, name)
    if node.type ~= "element" then return false end
    -- Direct name match
    if node.name == name then return true end
    -- Prefixed name match (SLAXML stores prefix separately)
    if node.nsPrefix then
        local full_name = node.nsPrefix .. ":" .. node.name
        if full_name == name then return true end
    end
    -- Match local name only (for namespaced queries)
    local search_local = name:match(":(.+)$") or name
    if node.name == search_local then return true end
    return false
end

---Find elements by tag name (recursive).
---@param parent table Parent element or DOM root to search from
---@param name string Tag name to find (may include namespace prefix)
---@return table Array of matching elements
function M.find_by_name(parent, name)
    local results = {}
    local kids = parent.kids or parent.el or {}

    for _, node in ipairs(kids) do
        if node.type == "element" then
            if element_matches_name(node, name) then
                table.insert(results, node)
            end
            -- Recurse into children
            local nested = M.find_by_name(node, name)
            for _, n in ipairs(nested) do
                table.insert(results, n)
            end
        end
    end
    return results
end

---Find elements by attribute value.
---@param parent table Parent element to search from
---@param attr_name string Attribute name to match
---@param attr_value string Attribute value to match
---@return table Array of matching elements
function M.find_by_attr(parent, attr_name, attr_value)
    local results = {}
    local kids = parent.kids or parent.el or {}

    for _, node in ipairs(kids) do
        if node.type == "element" then
            if node.attr and node.attr[attr_name] == attr_value then
                table.insert(results, node)
            end
            -- Recurse into children
            local nested = M.find_by_attr(node, attr_name, attr_value)
            for _, n in ipairs(nested) do
                table.insert(results, n)
            end
        end
    end
    return results
end

---Find a direct child by tag name (non-recursive).
---@param parent table Parent element
---@param name string Tag name to find (may include namespace prefix)
---@return table|nil First matching child or nil
function M.find_child(parent, name)
    local kids = parent.kids or parent.el or {}
    for _, node in ipairs(kids) do
        if element_matches_name(node, name) then
            return node
        end
    end
    return nil
end

---Find all direct children by tag name (non-recursive).
---@param parent table Parent element
---@param name string Tag name to find (may include namespace prefix)
---@return table Array of matching children
function M.find_children(parent, name)
    local results = {}
    local kids = parent.kids or parent.el or {}
    for _, node in ipairs(kids) do
        if element_matches_name(node, name) then
            table.insert(results, node)
        end
    end
    return results
end

-- ============================================================================
-- Attribute Operations
-- ============================================================================

---Get attribute value from element.
---@param el table Element to query
---@param name string Attribute name (may include namespace prefix like "w:val")
---@return string|nil Attribute value or nil if not found
function M.get_attr(el, name)
    if not el.attr then return nil end

    -- Try exact match first (direct key access)
    if el.attr[name] then return el.attr[name] end

    -- Try without namespace prefix (SLAXML stores attrs without prefix)
    local local_name = name:match(":(.+)$")
    if local_name and el.attr[local_name] then
        return el.attr[local_name]
    end

    -- SLAXML stores attributes in indexed array format when parsing XML
    for i, attr in ipairs(el.attr) do
        if type(attr) == "table" and attr.name then
            local attr_full_name = attr.nsPrefix and (attr.nsPrefix .. ":" .. attr.name) or attr.name
            if attr_full_name == name or attr.name == local_name then
                return attr.value
            end
        end
    end

    return nil
end

---Set attribute on element.
---@param el table Element to modify
---@param name string Attribute name (may include namespace prefix like "w:val")
---@param value string Attribute value
function M.set_attr(el, name, value)
    el.attr = el.attr or {}

    -- Parse namespace prefix from attribute name
    local nsPrefix, local_name = name:match("^([^:]+):(.+)$")
    if not local_name then
        local_name = name
        nsPrefix = nil
    end

    -- Update hash map (used for get_attr lookups)
    el.attr[local_name] = value

    -- Update array element (used for serialization)
    for i, attr_obj in ipairs(el.attr) do
        if type(attr_obj) == 'table' and attr_obj.type == 'attribute' then
            if attr_obj.name == local_name then
                attr_obj.value = value
                return
            end
        end
    end

    -- Attribute not found in array, add new entry for SLAXML serialization
    table.insert(el.attr, {
        type = "attribute",
        name = local_name,
        value = value,
        nsPrefix = nsPrefix,
        parent = el
    })
end

---Remove attribute from element.
---@param el table Element to modify
---@param name string Attribute name to remove
function M.remove_attr(el, name)
    if el.attr then
        el.attr[name] = nil
    end
end

-- ============================================================================
-- DOM Manipulation
-- ============================================================================

---Add child node to element.
---@param parent table Parent element
---@param child table Child node to add
function M.add_child(parent, child)
    local kids_key = parent.kids and "kids" or (parent.el and "el" or "kids")
    parent[kids_key] = parent[kids_key] or {}
    child.parent = parent
    table.insert(parent[kids_key], child)
end

---Insert child node at specific position.
---@param parent table Parent element
---@param child table Child node to insert
---@param position number 1-based position to insert at
function M.insert_child(parent, child, position)
    local kids_key = parent.kids and "kids" or (parent.el and "el" or "kids")
    parent[kids_key] = parent[kids_key] or {}
    child.parent = parent
    table.insert(parent[kids_key], position, child)
end

---Remove child node from parent.
---@param parent table Parent element
---@param child table Child node to remove
function M.remove_child(parent, child)
    local kids_key = parent.kids and "kids" or (parent.el and "el" or nil)
    if not kids_key then return end
    local kids = parent[kids_key]
    for i, node in ipairs(kids) do
        if node == child then
            table.remove(kids, i)
            child.parent = nil
            return
        end
    end
end

---Replace a child element by tag name.
---If no child with that name exists, the new child is appended.
---@param parent table Parent element
---@param name string Tag name of child to replace
---@param new_child table New child element to insert
---@return boolean true if replaced, false if appended
function M.replace_child(parent, name, new_child)
    local kids_key = parent.kids and "kids" or (parent.el and "el" or "kids")
    parent[kids_key] = parent[kids_key] or {}
    local kids = parent[kids_key]
    for i, node in ipairs(kids) do
        if element_matches_name(node, name) then
            node.parent = nil
            new_child.parent = parent
            kids[i] = new_child
            return true
        end
    end
    -- Not found, append
    M.add_child(parent, new_child)
    return false
end

---Replace a specific node in parent's children.
---@param parent table Parent element
---@param old_node table The node to replace
---@param new_node table The replacement node
---@return boolean true if replaced, false if not found
function M.replace_node(parent, old_node, new_node)
    local kids_key = parent.kids and "kids" or (parent.el and "el" or nil)
    if not kids_key then return false end
    local kids = parent[kids_key]
    for i, node in ipairs(kids) do
        if node == old_node then
            old_node.parent = nil
            new_node.parent = parent
            kids[i] = new_node
            return true
        end
    end
    return false
end

---Remove all children with a given tag name.
---@param parent table Parent element
---@param name string Tag name of children to remove
---@return number Count of removed children
function M.remove_children_by_name(parent, name)
    local kids_key = parent.kids and "kids" or (parent.el and "el" or nil)
    if not kids_key then return 0 end
    local kids = parent[kids_key]
    local count = 0
    local i = 1
    while i <= #kids do
        local node = kids[i]
        if element_matches_name(node, name) then
            table.remove(kids, i)
            node.parent = nil
            count = count + 1
        else
            i = i + 1
        end
    end
    return count
end

-- ============================================================================
-- Utility Functions
-- ============================================================================

---Get text content of element (concatenates all text children).
---@param el table Element to get text from
---@return string Concatenated text content
function M.get_text(el)
    local parts = {}
    local kids = el.kids or {}
    for _, node in ipairs(kids) do
        if node.type == "text" then
            table.insert(parts, node.value)
        elseif node.type == "element" then
            table.insert(parts, M.get_text(node))
        end
    end
    return table.concat(parts)
end

---Clone an element (deep copy).
---@param el table Element to clone
---@return table Deep copy of element
function M.clone(el)
    if el.type == "text" then
        return { type = "text", value = el.value }
    elseif el.type == "element" then
        local new_el = {
            type = "element",
            name = el.name,
            nsPrefix = el.nsPrefix,
            attr = {},
            kids = {},
            nsURI = el.nsURI
        }
        -- Copy attributes
        if el.attr then
            for k, v in pairs(el.attr) do
                new_el.attr[k] = v
            end
        end
        -- Clone children
        if el.kids then
            for _, child in ipairs(el.kids) do
                local cloned = M.clone(child)
                cloned.parent = new_el
                table.insert(new_el.kids, cloned)
            end
        end
        return new_el
    end
    return el
end

return M
