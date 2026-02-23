local logger = require("infra.logger")
local Queries = require("db.queries")
local hash_utils = require("infra.hash_utils")

local M = {
    name = "spec_relations",
    prerequisites = {"spec_objects", "attributes"}  -- Needs attributes for AST link extraction
}

-- Import spec_floats for get_float_anchor function
local spec_floats = require("pipeline.initialize.spec_floats")

-- Cache for resolved type aliases
local alias_cache = {}

---Clear module-level caches (required for re-entrant engine.run_project calls).
function M.clear_cache()
    alias_cache = {}
end

---Resolve a type prefix to its canonical float type identifier.
---Queries the spec_float_types table for matching identifiers or aliases.
---@param data DataManager
---@param prefix string The prefix to resolve (e.g., "fig", "csv", "puml")
---@return string|nil float_type The canonical float type identifier (e.g., "FIGURE", "TABLE")
local function resolve_float_type_from_prefix(data, prefix)
    local lower_prefix = prefix:lower()

    -- Check cache first
    if alias_cache[lower_prefix] then
        return alias_cache[lower_prefix]
    end

    -- Query the spec_float_types table for direct match or alias match
    local type_def = data:query_one(Queries.resolution.float_type_from_prefix, {
        prefix = lower_prefix,
        like_pattern = "%," .. lower_prefix .. ",%"
    })

    local canonical = type_def and type_def.identifier or nil
    alias_cache[lower_prefix] = canonical
    return canonical
end

---Find the parent spec_object for a link based on file and line number.
---The parent is the spec_object whose line range contains this link.
---@param data DataManager
---@param spec_id string Specification identifier
---@param from_file string Source file path
---@param line number Line number of the link
---@return integer|nil parent_object_id The parent spec_object id
local function find_parent_object(data, spec_id, from_file, line)
    if not line or line <= 0 then
        return nil
    end

    -- Find the spec_object that contains this line (start_line <= line <= end_line)
    -- Order by level descending to get the most specific (deepest nested) container
    local parent = data:query_one(Queries.resolution.find_parent_object_by_line, {
        spec_id = spec_id,
        from_file = from_file,
        line = line
    })

    return parent and parent.id or nil
end

---Parse link syntax to extract target, type, prefix, scope, and selector.
---Supports: [PID](@), [type:label](#), [scope:type:label](#), [key](@cite), [key](@citep)
---INITIALIZE phase: type_ref is ALWAYS nil (type inference deferred to ANALYZE).
---@param link table Link object
---@param data DataManager|nil Optional data manager for dynamic type resolution
---@return string|nil target_text, string|nil type_ref, string|nil prefix, string|nil explicit_scope, string|nil selector
local function parse_link_syntax(link, data)
    local target = link.target
    if not target and link.c and link.c[3] then
        target = type(link.c[3]) == "table" and link.c[3][1] or link.c[3]
    end
    target = target or ""
    local content_text = ""
    local content = link.content or (link.c and link.c[2])

    -- Get text content from link
    if content then
        if type(content) == "string" then
            content_text = content
        elseif pandoc then
            content_text = pandoc.utils.stringify(content)
        end
    end

    -- Only handle selectors that start with @ or #
    if not target:match("^[@#]") then
        -- Pattern 3: Link with explicit type class [target]{.TYPE}
        if link.classes and #link.classes > 0 then
            return target, nil, nil, nil, nil
        end
        return nil, nil, nil, nil, nil
    end

    local selector = target  -- "@", "#", "@cite", "@citep", etc.

    -- Try scope:prefix:label pattern (e.g., REQ-001:fig:diagram)
    local scope_part, type_part, label_part = content_text:match("^([^:]+):([^:]+):(.+)$")
    if scope_part and type_part and label_part then
        -- Only decompose if prefix is a known float type
        if data then
            local canonical_type = resolve_float_type_from_prefix(data, type_part)
            -- Handle type.language format (e.g., src.lua) — extract base type
            if not canonical_type then
                local base_type = type_part:match("^([^%.]+)")
                if base_type and base_type ~= type_part then
                    canonical_type = resolve_float_type_from_prefix(data, base_type)
                end
            end
            if canonical_type then
                local canonical_prefix = spec_floats.get_type_prefix(data, canonical_type)
                return label_part, nil, canonical_prefix, scope_part, selector
            end
        end
        -- Unknown prefix -- treat as plain text
        return content_text, nil, nil, nil, selector
    end

    -- Try prefix:label pattern (e.g., fig:diagram, cite:smith2024, src.lua:example)
    local type_part2, label_part2 = content_text:match("^([^:]+):(.+)$")
    if type_part2 then
        if data then
            -- Check if prefix is a known float type
            local canonical_type = resolve_float_type_from_prefix(data, type_part2)
            -- Handle type.language format (e.g., src.lua) — extract base type
            if not canonical_type then
                local base_type = type_part2:match("^([^%.]+)")
                if base_type and base_type ~= type_part2 then
                    canonical_type = resolve_float_type_from_prefix(data, base_type)
                end
            end
            if canonical_type then
                -- Known prefix -- normalize to canonical first alias
                local canonical_prefix = spec_floats.get_type_prefix(data, canonical_type)
                return label_part2, nil, canonical_prefix, nil, selector
            end
        end
        -- Unknown prefix -- treat as plain text (entire content is the target)
        return content_text, nil, nil, nil, selector
    end

    -- Plain content (no colons) -- just the PID or label
    return content_text, nil, nil, nil, selector
end

local function build_stored_target_text(target_text, prefix, explicit_scope)
    if prefix and explicit_scope then
        return explicit_scope .. ":" .. prefix .. ":" .. target_text
    end
    if prefix then
        return prefix .. ":" .. target_text
    end
    return target_text
end

local function insert_relation(data, spec_id, source_object_id, target_text, type_ref, from_file, link_line, source_attribute, link_selector)
    local content_key = spec_id .. (target_text or "") .. (type_ref or "") .. tostring(source_object_id or "")
    local content_sha = hash_utils.sha1(content_key)

    data:execute(Queries.resolution.insert_relation, {
        content_sha = content_sha,
        specification_ref = spec_id,
        source_object_id = source_object_id,
        target_text = target_text,
        target_object_id = nil,
        target_float_id = nil,
        type_ref = type_ref,
        from_file = from_file or "unknown",
        link_line = link_line or 0,
        source_attribute = source_attribute,
        link_selector = link_selector
    })
end

local function find_links(node, links)
    if node == nil then return end

    if node.t == "Link" then
        links[#links + 1] = node
        return
    end

    if node.t then
        if node.content then
            for i = 1, #node.content do
                find_links(node.content[i], links)
            end
        end
        return
    end

    for i = 1, #node do
        find_links(node[i], links)
    end
end

local function relation_identity_key(source_object_id, target_text, link_selector)
    return table.concat({
        tostring(source_object_id or ""),
        tostring(link_selector or ""),
        tostring(target_text or "")
    }, "|")
end

local function stringify_inlines(inlines)
    local result = {}
    for _, inline in ipairs(inlines or {}) do
        if type(inline) == "string" then
            result[#result + 1] = inline
        elseif inline.t == "Str" then
            result[#result + 1] = inline.c or inline.text or ""
        elseif inline.t == "Space" then
            result[#result + 1] = " "
        elseif inline.content then
            result[#result + 1] = stringify_inlines(inline.content)
        elseif inline.c and type(inline.c) == "table" then
            result[#result + 1] = stringify_inlines(inline.c)
        end
    end
    return table.concat(result)
end

local function extract_json_link_target(link)
    local target = link.target
    if not target and link.c and link.c[3] then
        target = type(link.c[3]) == "table" and link.c[3][1] or link.c[3]
    end
    return target
end

local function process_document_links(data, doc, spec_id, skip_keys)
    local relation_count = 0

    for link in doc:walk_links() do
        if link.t == "Link" then
            local target_text, _, prefix, explicit_scope, selector = parse_link_syntax(link, data)
            if target_text then
                local parent_id = find_parent_object(data, spec_id, link.file, link.line)
                local stored_target_text = build_stored_target_text(target_text, prefix, explicit_scope)
                local key = relation_identity_key(parent_id, stored_target_text, selector)

                -- Attribute-level extraction is authoritative for attribute links.
                -- Skip equivalent document-level relation to avoid duplicates.
                if not (skip_keys and skip_keys[key]) then
                    relation_count = relation_count + 1

                    insert_relation(
                        data,
                        spec_id,
                        parent_id,
                        stored_target_text,
                        nil,  -- type_ref = NULL, inferred in ANALYZE
                        link.file or "unknown",
                        link.line or 0,  -- link_line
                        nil,  -- source_attribute (body text)
                        selector  -- "@", "#", "@cite", ...
                    )
                end
            end
        end
    end

    return relation_count
end

local function process_attribute_links(data, ctx, spec_id, diagnostics, seen_keys)
    local attr_relations = data:query_all(Queries.resolution.select_attributes_with_ast_by_spec, { spec_id = spec_id })

    local attr_link_count = 0
    local relation_count = 0

    for _, attr in ipairs(attr_relations or {}) do
        if attr.ast and attr.owner_object_id then
            local ok, ast_data = pcall(pandoc.json.decode, attr.ast)
            if not ok then
                error(string.format(
                    "Failed to decode AST JSON for attribute '%s' on object %d: %s",
                    attr.attr_name or "unknown",
                    attr.owner_object_id,
                    tostring(ast_data)
                ))
            end
            if ast_data then
                local elements = type(ast_data) == "table" and ast_data or { ast_data }
                local links = {}
                find_links(elements, links)

                for _, link in ipairs(links) do
                    local target = extract_json_link_target(link)
                    local content = link.content or (link.c and link.c[2])
                    local content_text = content and stringify_inlines(content) or ""

                    local link_obj = {
                        t = "Link",
                        target = target,
                        content = content_text,
                        classes = link.classes or {},
                        attributes = link.attributes or {},
                    }

                    local target_text, _, prefix, explicit_scope, selector = parse_link_syntax(link_obj, data)
                    if target_text then
                        attr_link_count = attr_link_count + 1
                        relation_count = relation_count + 1

                        local stored_target_text = build_stored_target_text(target_text, prefix, explicit_scope)
                        local key = relation_identity_key(attr.owner_object_id, stored_target_text, selector)

                        insert_relation(
                            data,
                            spec_id,
                            attr.owner_object_id,
                            stored_target_text,
                            nil,  -- type_ref = NULL, inferred in ANALYZE
                            attr.owner_file or (ctx.doc and ctx.doc.source_path or "unknown"),
                            attr.owner_line or 0,  -- link_line (owner's start_line as best approximation)
                            attr.attr_name,
                            selector  -- "@" or "#"
                        )

                        if seen_keys then
                            seen_keys[key] = true
                        end
                    end
                end
            end
        end
    end

    return relation_count, attr_link_count
end

---@param data DataManager
---@param contexts Context[]
---@param diagnostics Diagnostics
function M.on_initialize(data, contexts, diagnostics)
    data:begin_transaction()

    -- Delete old relations for dirty documents before re-creating.
    -- Other content tables (spec_objects, spec_floats, etc.) already do this;
    -- without it, stale relations with old target_object_id values persist.
    for _, ctx in ipairs(contexts) do
        if ctx.doc then
            local spec_id = ctx.spec_id or "default"
            data:execute(Queries.content.delete_relations_by_spec, { spec_id = spec_id })
        end
    end

    for _, ctx in ipairs(contexts) do
        local doc = ctx.doc
        if not doc then goto continue end  -- Skip if no document (project context only)

        local spec_id = ctx.spec_id or "default"

        if not doc.walk_links then goto continue end

        local attr_relation_keys = {}
        local attr_relations_count, attr_link_count = process_attribute_links(data, ctx, spec_id, diagnostics, attr_relation_keys)
        local relation_count = attr_relations_count
        relation_count = relation_count + process_document_links(data, doc, spec_id, attr_relation_keys)

        -- Log summary
        if attr_link_count > 0 then
            logger.info(string.format("Created %d relations from attribute links for %s", attr_link_count, spec_id))
        end
        if relation_count > 0 then
            logger.info(string.format("Created %d relations for %s", relation_count, spec_id))
        end
        ::continue::
    end
    data:commit()
end

return M
