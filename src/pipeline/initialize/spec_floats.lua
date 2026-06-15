---Spec Floats Handler for SpecCompiler.
---Handles INITIALIZE phase only: parsing code blocks and storing in database.
---Transform logic is delegated to individual type handlers.
---Uses INTEGER PRIMARY KEY (auto-assigned by SQLite).
---Generates unified labels via label_utils ({type_prefix}:{user_label}).
---
---@module spec_floats
local logger = require("infra.logger")
local label_utils = require("pipeline.shared.label_utils")
local hash_utils = require("infra.hash_utils")
local Queries = require("db.queries")
local cache_registry = require("pipeline.shared.cache_registry")

local M = {
    name = "spec_floats_initialize",
    prerequisites = {"spec_objects"}  -- Needs spec_objects for parent_object_id FK
}

-- Cache for resolved type aliases
local alias_cache = {}

-- Cache for type prefixes (queried from DB)
local prefix_cache = {}

---Get the prefix for a float type from the database.
---Uses the first alias from spec_float_types.aliases, or falls back to first 3 chars.
---@param data DataManager
---@param type_ref string The canonical type identifier (e.g., "FIGURE", "TABLE")
---@return string prefix The type prefix (e.g., "fig", "tbl")
local function get_type_prefix(data, type_ref)
    if not type_ref or type_ref == "" then
        return "unk"  -- Unknown type
    end

    -- Check cache first
    if prefix_cache[type_ref] then
        return prefix_cache[type_ref]
    end

    -- Query the type registry for aliases
    local type_def = data:query_one(Queries.resolution.select_float_type_by_id, { type_ref = type_ref })

    if not type_def then
        error(string.format("Float type '%s' not found in spec_float_types", type_ref))
    end

    -- Extract first alias as prefix, or use first 3 chars of identifier
    local prefix = type_ref:sub(1, 3):lower()
    if type_def.aliases and type_def.aliases ~= "" then
        -- Aliases format: ",fig,figure,img," - extract first one
        local first_alias = type_def.aliases:match(",([^,]+),")
        if first_alias and first_alias ~= "" then
            prefix = first_alias
        end
    end

    prefix_cache[type_ref] = prefix
    return prefix
end

-- Expose for cross-module use (spec_relations needs canonical prefix for label normalization)
M.get_type_prefix = get_type_prefix

---Clear module-level caches (required for re-entrant engine.run_project calls).
function M.clear_cache()
    alias_cache = {}
    prefix_cache = {}
end
cache_registry.register(M.clear_cache)

---Generate anchor for a float based on scope.
---Anchors are formatted as:
---  - With parent PID: {parent-pid}-{type-prefix}-{label} (e.g., REQ-001-fig-diagram)
---  - Without parent: {type-prefix}-{label} (e.g., tbl-summary)
---@param float table Float record with type_ref, label, parent_object_id
---@param data DataManager
---@return string anchor The generated anchor
local function get_float_anchor(float, data)
    -- Get type prefix from database (with caching)
    local type_ref = float.type_ref or ""
    local type_prefix = get_type_prefix(data, type_ref)
    -- Use the user_label portion of the unified label (after the colon)
    local user_label = float.label and float.label:match(":(.+)$") or float.label or ""

    -- If float has parent, try to get parent's PID for scoped anchor
    if float.parent_object_id then
        local parent = data:query_one(Queries.content.select_object_pid_by_id, { id = float.parent_object_id })

        if parent and parent.pid then
            return parent.pid .. "-" .. type_prefix .. "-" .. user_label
        end
    end

    -- No parent or parent has no PID: global anchor
    return type_prefix .. "-" .. user_label
end

---Resolve a type alias to its canonical type identifier.
---Queries the spec_float_types table for matching aliases.
---@param data DataManager
---@param alias string The alias to resolve (e.g., "csv", "puml")
---@return string canonical_type The canonical type identifier (e.g., "TABLE", "FIGURE")
local function resolve_type_alias(data, alias)
    local upper_alias = alias:upper()

    -- Check cache first
    if alias_cache[upper_alias] then
        return alias_cache[upper_alias]
    end

    -- Query the type registry for direct match or alias match
    local type_def = data:query_one(Queries.resolution.resolve_float_type_alias, {
        alias = upper_alias,
        like_pattern = "%," .. alias:lower() .. ",%"
    })

    local canonical = type_def and type_def.identifier or upper_alias
    alias_cache[upper_alias] = canonical
    return canonical
end

---Find the parent spec_object for a float based on file and line number.
---The parent is the spec_object whose line range contains this float.
---@param data DataManager
---@param spec_id string Specification identifier
---@param from_file string Source file path
---@param line number Line number of the float
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

---Parse float syntax: type:label{attrs} or type.language:label{attrs}
---@param classes table Code block classes
---@param identifier string Code block identifier
---@param data DataManager Database for alias resolution
---@return string|nil type_ref, string|nil label, table|nil attrs
local function parse_attrs_string(attrs_str)
    if not attrs_str or attrs_str == "" then
        return nil
    end

    local attrs = {}

    for key, value in attrs_str:gmatch('([%w_%-]+)%s*=%s*"([^"]*)"') do
        attrs[key] = value
    end

    for key, value in attrs_str:gmatch("([%w_%-]+)%s*=%s*([^%s\"'}]+)") do
        if attrs[key] == nil then
            attrs[key] = value
        end
    end

    if next(attrs) == nil then
        return nil
    end
    return attrs
end

local function parse_float_syntax(classes, identifier, data)
    if not classes or #classes == 0 then return nil, nil, nil end

    local first_class = classes[1]

    -- Check for type:label format in class
    local type_part, label_part = first_class:match("^([^:]+):(.+)$")

    if type_part then
        -- Handle type.language format (e.g., src.python)
        local base_type = type_part:match("^([^%.]+)") or type_part
        local canonical_type = resolve_type_alias(data, base_type)

        -- Check if this is a known float type
        local type_exists = data:query_one(Queries.resolution.float_type_exists, { id = canonical_type })

        if type_exists then
            -- Extract clean label (everything before first '{')
            local clean_label = label_part:match("^([^{]+)") or label_part
            -- Extract attributes string (everything between '{' and '}')
            local attrs_str = label_part:match("{(.-)}")

            local attrs = parse_attrs_string(attrs_str)

            -- If type has language suffix (e.g., src.python), store it in attrs
            local language = type_part:match("%.(.+)$")
            if language then
                attrs = attrs or {}
                attrs.language = language
            end

            return canonical_type, clean_label, attrs
        end
    end

    -- Check if first class is a known type, label is in identifier or second class
    local canonical_type = resolve_type_alias(data, first_class)
    local type_exists = data:query_one(Queries.resolution.float_type_exists, { id = canonical_type })

    if type_exists then
        local label = identifier or (classes[2] and classes[2]) or ""
        return canonical_type, label, nil
    end

    return nil, nil, nil
end

---Serialize a code block to JSON for AST storage
---@param block table Code block data from walker
---@return string|nil json
local function block_to_json(block)
    -- Reconstruct a Pandoc CodeBlock from walker data
    local attr = pandoc.Attr(
        block.identifier or "",
        block.classes or {},
        block.attributes or {}
    )
    local code_block = pandoc.CodeBlock(block.text or "", attr)

    return pandoc.json.encode(code_block)
end

---BATCH MODE for INITIALIZE: Process ALL documents in a single transaction.
---@param data DataManager
---@param contexts table Array of Context objects
---@param diagnostics Diagnostics
---Merge parser-derived attrs with the code block's Pandoc attributes
---(parser values win; data-* attributes are skipped). Pandoc may present
---block attributes as a map or as {key, value} pairs — handle both.
---@param parsed_attrs table|nil Attrs parsed from the float syntax
---@param block_attributes table|nil Pandoc code-block attributes
---@return table|nil float_attrs Merged attrs, or nil when empty
local function merge_block_attrs(parsed_attrs, block_attributes)
    local float_attrs = parsed_attrs or {}
    if block_attributes then
        for k, v in pairs(block_attributes) do
            if type(k) == "string" then
                if not k:match("^data%-") then
                    float_attrs[k] = float_attrs[k] or v
                end
            elseif type(k) == "number" and type(v) == "table" and #v >= 2 then
                local attr_key, attr_val = v[1], v[2]
                if type(attr_key) == "string" and not attr_key:match("^data%-") then
                    float_attrs[attr_key] = float_attrs[attr_key] or attr_val
                end
            end
        end
    end
    if not next(float_attrs) then return nil end
    return float_attrs
end

---Build the spec_floats insert record for one recognized code block.
---@param data DataManager
---@param spec_id string Specification identifier
---@param block table Code block from doc:walk_codeblocks()
---@param file_seq integer Per-document float sequence number
---@param type_ref string Canonical float type
---@param user_label string|nil Label from the float syntax
---@param parsed_attrs table|nil Attrs parsed from the float syntax
---@return table record Row for Queries.content.insert_float (anchor unset)
local function build_float_record(data, spec_id, block, file_seq, type_ref, user_label, parsed_attrs)
    local content_key = (block.file or "") .. ":" .. file_seq .. ":" .. (block.text or "")
    local content_sha = hash_utils.sha1(content_key)

    -- Compute unified label: {type_prefix}:{user_label}
    local type_prefix = get_type_prefix(data, type_ref)
    local label = label_utils.compute_float_label(type_prefix, user_label)

    local float_attrs = merge_block_attrs(parsed_attrs, block.attributes)
    local caption = float_attrs and float_attrs.caption
    local attrs_json = float_attrs and pandoc.json.encode(float_attrs) or nil

    local ast_json = block_to_json(block)
    local from_file = block.file or "unknown"
    local parent_object_id = find_parent_object(data, spec_id, from_file, block.line)
    local first_class = block.classes and block.classes[1] or ""
    local syntax_key = first_class:match("^([^{]+)") or first_class

    return {
        content_sha = content_sha,
        specification_ref = spec_id,
        type_ref = type_ref,
        from_file = from_file,
        file_seq = file_seq,
        start_line = block.line,
        label = label,
        number = nil,
        caption = caption,
        raw_content = block.text or "",
        raw_ast = ast_json,
        parent_object_id = parent_object_id,
        pandoc_attributes = attrs_json,
        syntax_key = syntax_key
    }
end

function M.on_initialize(data, contexts, diagnostics)
    local all_floats = {}
    local spec_ids = {}
    local total_count = 0

    -- Phase 1: Extract floats from ALL documents (CPU-bound)
    for _, ctx in ipairs(contexts) do
        local doc = ctx.doc
        local spec_id = ctx.spec_id or "default"

        if doc and doc.walk_codeblocks then
            table.insert(spec_ids, spec_id)
            local file_seq = 0

            for block in doc:walk_codeblocks() do
                local type_ref, user_label, parsed_attrs = parse_float_syntax(
                    block.classes, block.identifier, data
                )

                if type_ref then
                    file_seq = file_seq + 1
                    table.insert(all_floats, build_float_record(
                        data, spec_id, block, file_seq, type_ref, user_label, parsed_attrs))
                    total_count = total_count + 1
                end
            end
        end
    end

    -- Phase 2: Single transaction for ALL database operations
    if #spec_ids > 0 then
        data:begin_transaction()

        -- Bulk DELETE for all specs
        for _, spec_id in ipairs(spec_ids) do
            data:execute(Queries.content.delete_floats_by_spec, { spec_id = spec_id })
        end

        -- Insert all floats (duplicates detected by view_float_duplicate_label verification_view in VERIFY)
        for _, float in ipairs(all_floats) do
            -- Compute anchor after all objects are inserted
            float.anchor = get_float_anchor(float, data)

            data:execute(Queries.content.insert_float, float)
        end

        data:commit()
    end

    if total_count > 0 then
        logger.info(string.format("Registered %d total floats across %d documents", total_count, #spec_ids))
    end
end

-- Expose for cross-module use (spec_relations resolves float parents the same way)
M.find_parent_object = find_parent_object

return M
