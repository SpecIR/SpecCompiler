---Attributes Handler for SpecCompiler.
---Extracts attributes from BlockQuotes following headers.
---Syntax: > name: value (blockquote with field name and colon)
---
---@module attributes
local logger = require("infra.logger")
local AttributeCaster = require('pipeline.analyze.attribute_caster')
local attribute_para = require("pipeline.shared.attribute_para_utils")
local hash_utils = require("infra.hash_utils")
local cache_utils = require("pipeline.shared.cache_utils")
local DT = require("core.datatypes")
local Queries = require("db.queries")

local M = {
    name = "attributes",
    prerequisites = {"spec_objects"}  -- Needs spec_objects to exist for owner_object_id FK
}

-- Singleton cache: default object type from spec_object_types
local default_object_type = cache_utils.create_once(function(data)
    local result = data:query_one(Queries.resolution.default_object_type)
    return result and result.identifier or nil
end)

-- Key-value cache: attribute definitions by "owner_type:attr_name"
local attr_def = cache_utils.create_map(function(cache_key, data)
    local owner_type, attr_name = cache_key:match("^(.+):(.+)$")
    return data:query_one(Queries.resolution.attribute_definition, {
        owner_type = owner_type,
        name = attr_name
    })
end)

---Query the default object type from spec_object_types.
---@param data DataManager
---@return string|nil default_type The default type identifier
local function get_default_object_type(data)
    return default_object_type:get(data)
end

---Clear module-level caches (required for re-entrant engine.run_project calls).
function M.clear_cache()
    attr_def:clear()
    default_object_type:clear()
end

---Look up attribute definition to get datatype.
---@param data DataManager
---@param owner_type string Owner type (e.g., "HLR", "SECTION")
---@param attr_name string Attribute name
---@return table|nil definition Attribute definition with datatype
local function get_attribute_definition(data, owner_type, attr_name)
    return attr_def:get(owner_type .. ":" .. attr_name, data)
end

---Pre-index attribute positions in blockquote blocks for O(n) processing.
---Returns array of {pos, field_name} for each attribute-defining Para.
---@param bq_blocks table Array of blocks from blockquote
---@return table attr_index Array of {pos=number, field_name=string}
local function index_attribute_positions(bq_blocks)
    local attr_index = {}
    for i, blk in ipairs(bq_blocks) do
        if blk.t == "Para" then
            local field_name = attribute_para.get_field_name(blk)
            if field_name then
                attr_index[#attr_index + 1] = { pos = i, field_name = field_name }
            end
        end
    end
    return attr_index
end

---Process a single attribute with its continuation blocks.
---@param bq_blocks table All blocks in the blockquote
---@param attr_pos number Position of the attribute Para
---@param field_name string The attribute field name
---@param next_attr_pos number Position of next attribute (or #bq_blocks+1)
---@param spec_id string Specification ID
---@param current_owner table Owner object
---@param current_owner_type string Owner type
---@param data DataManager Database manager
---@return table attr_record Attribute record ready for insertion
local function process_single_attribute(bq_blocks, attr_pos, field_name, next_attr_pos, spec_id, current_owner, current_owner_type, data)
    local blk = bq_blocks[attr_pos]
    local raw_value, value_inlines = attribute_para.extract_value_from_para(blk)

    -- Collect continuation blocks between this attribute and the next
    if attr_pos + 1 < next_attr_pos then
        local continuation_blocks = {}
        local continuation_text = {}

        for j = attr_pos + 1, next_attr_pos - 1 do
            local next_blk = bq_blocks[j]
            table.insert(continuation_blocks, next_blk)
            table.insert(continuation_text, pandoc.utils.stringify(next_blk))
        end

        if #continuation_blocks > 0 then
            local continuation_str = table.concat(continuation_text, "\n")
            if raw_value and raw_value ~= "" then
                raw_value = raw_value .. "\n" .. continuation_str
            else
                raw_value = continuation_str
            end
            if value_inlines and #value_inlines > 0 then
                local merged = {pandoc.Para(value_inlines)}
                for _, b in ipairs(continuation_blocks) do
                    table.insert(merged, b)
                end
                value_inlines = merged
            else
                value_inlines = continuation_blocks
            end
        end
    end

    -- Compute content_sha for change detection
    local content_key = spec_id .. tostring(current_owner.id or "") .. field_name .. raw_value
    local content_sha = hash_utils.sha1(content_key)

    -- Look up datatype from definition
    local attr_def = get_attribute_definition(data, current_owner_type, field_name)
    local datatype = attr_def and attr_def.datatype or DT.STRING

    -- Cast value to typed columns
    local cast_result = AttributeCaster.cast(raw_value, datatype, data, attr_def)

    -- Serialize value AST for rich content
    local ast_json = nil
    if value_inlines and #value_inlines > 0 then
        local has_rich_content = datatype == DT.XHTML
        if not has_rich_content then
            if value_inlines[1] and value_inlines[1].t and
               (value_inlines[1].t == "Para" or value_inlines[1].t == "Plain" or value_inlines[1].t == "BulletList") then
                has_rich_content = true
            else
                for _, inline in ipairs(value_inlines) do
                    if inline.t == "Link" or inline.t == "Strong" or inline.t == "Emph" or inline.t == "Code" then
                        has_rich_content = true
                        break
                    end
                end
            end
        end
        if has_rich_content then
            ast_json = pandoc.json.encode(value_inlines)
        end
    end

    return {
        content_sha = content_sha,
        specification_ref = spec_id,
        owner_object_id = current_owner.id,  -- INTEGER FK to spec_objects.id (nil for spec-level metadata)
        owner_float_id = nil,  -- Attributes on floats not yet supported
        name = field_name,
        raw_value = raw_value,
        string_value = cast_result.string_value,
        int_value = cast_result.int_value,
        real_value = cast_result.real_value,
        bool_value = cast_result.bool_value,
        date_value = cast_result.date_value,
        enum_ref = cast_result.enum_ref,
        ast = ast_json,
        datatype = datatype
    }
end

---Process all attributes in a blockquote using O(n) indexed approach.
---@param blockquote table Pandoc BlockQuote block
---@param spec_id string Specification ID
---@param current_owner table Owner object
---@param current_owner_type string Owner type
---@param data DataManager Database manager
---@return table attrs Array of attribute records
local function process_blockquote_indexed(blockquote, spec_id, current_owner, current_owner_type, data)
    local bq_blocks = attribute_para.extract_blocks_from_blockquote(blockquote)
    local num_blocks = #bq_blocks
    if num_blocks == 0 then return {} end

    -- Phase 1: Single pass to identify all attribute positions - O(n)
    local attr_index = index_attribute_positions(bq_blocks)
    if #attr_index == 0 then return {} end

    -- Phase 2: Process each attribute with pre-computed boundaries - O(n) total
    local attrs = {}
    for idx, entry in ipairs(attr_index) do
        local next_pos = attr_index[idx + 1] and attr_index[idx + 1].pos or (num_blocks + 1)
        local attr = process_single_attribute(
            bq_blocks, entry.pos, entry.field_name, next_pos,
            spec_id, current_owner, current_owner_type, data
        )
        attrs[#attrs + 1] = attr
    end

    return attrs
end

---Find the spec_object that owns a given block position by file_seq.
---Uses file_seq (header order) which is unique, unlike line numbers.
---@param data DataManager
---@param spec_id string Specification ID
---@param file_seq number Header sequence number (1-based)
---@return table|nil owner The owning spec_object record
local function find_owner_by_seq(data, spec_id, file_seq)
    -- Find spec_object by file_seq (order of header in document)
    local owner = data:query_one(Queries.resolution.object_by_file_seq, {
        spec_id = spec_id,
        file_seq = file_seq
    })

    -- If no spec_object found, this might be content under level 1 (specification)
    -- Return a pseudo-owner with id = nil (spec-level metadata has no object owner)
    if not owner then
        owner = { id = nil, type_ref = "SPECIFICATION", title_text = "", start_line = 0, file_seq = 0 }
    end

    return owner
end

-- NOTE: Attribute stripping was removed. Attributes appear as blockquotes in output.
-- Future enhancement: Add on_transform that strips raw attributes and injects
-- rendered attribute tables via spec_object_render_handler.

---Extract attributes from a single context WITHOUT database operations.
---Returns array of attribute records ready for batch insertion.
---Uses O(n) indexed approach for attribute extraction.
---@param ctx Context Document context
---@param data DataManager Data manager (for owner lookup only)
---@return table attrs Array of attribute records
---@return number count Number of attributes extracted
local function extract_attributes_from_context(ctx, data)
    local doc = ctx.doc
    if not doc then return {}, 0 end

    local spec_id = ctx.spec_id or "default"
    local blocks = doc.blocks or (doc.doc and doc.doc.blocks) or {}
    local default_type = get_default_object_type(data)

    local attrs = {}
    local current_owner = nil
    local current_owner_type = default_type
    local header_seq = 0

    ---Unwrap a block from Div wrapper (used by commonmark+sourcepos)
    local function unwrap_div(block)
        if block.t == "Div" then
            local div_content = block.content or (block.c and block.c[2]) or {}
            if #div_content == 1 then
                return div_content[1]
            end
        end
        return block
    end

    -- Process all blocks using O(n) indexed approach
    for _, block in ipairs(blocks) do
        local inner_block = unwrap_div(block)

        if inner_block.t == "Header" or block.t == "Header" then
            local header = inner_block.t == "Header" and inner_block or block
            local title_text = header.content and pandoc.utils.stringify(header.content) or ""
            local type_ref = default_type
            local type_part = title_text:match("^([A-Z][A-Z0-9_]*):%s*")
            if type_part then
                type_ref = type_part
            end
            header_seq = header_seq + 1
            current_owner = find_owner_by_seq(data, spec_id, header_seq)
            current_owner_type = type_ref

        elseif (inner_block.t == "BlockQuote" or block.t == "BlockQuote") and current_owner then
            local blockquote = inner_block.t == "BlockQuote" and inner_block or block
            -- Use O(n) indexed processing
            local bq_attrs = process_blockquote_indexed(blockquote, spec_id, current_owner, current_owner_type, data)
            for _, attr in ipairs(bq_attrs) do
                attrs[#attrs + 1] = attr
            end

        elseif block.t == "Div" and current_owner then
            local div_content = block.c or block.content or {}
            if type(div_content[2]) == "table" then
                div_content = div_content[2]
            end
            for _, inner in ipairs(div_content) do
                if inner.t == "BlockQuote" then
                    -- Use O(n) indexed processing
                    local bq_attrs = process_blockquote_indexed(inner, spec_id, current_owner, current_owner_type, data)
                    for _, attr in ipairs(bq_attrs) do
                        attrs[#attrs + 1] = attr
                    end
                end
            end
        end
    end

    -- Extract YAML frontmatter metadata
    -- Metadata attributes have no object/float owner (spec-level)
    local meta = doc.doc and doc.doc.meta
    if meta then
        for name, meta_value in pairs(meta) do
            local raw_value = pandoc.utils.stringify(meta_value)
            local content_key = spec_id .. "METADATA" .. name .. raw_value
            local content_sha = hash_utils.sha1(content_key)
            local ast_json = meta_value and pandoc.json.encode(meta_value) or nil

            table.insert(attrs, {
                content_sha = content_sha,
                specification_ref = spec_id,
                owner_object_id = nil,  -- spec-level metadata, no object owner
                owner_float_id = nil,
                name = name,
                raw_value = raw_value,
                string_value = raw_value,
                int_value = nil,
                real_value = nil,
                bool_value = nil,
                date_value = nil,
                enum_ref = nil,
                ast = ast_json,
                datatype = DT.XHTML
            })
        end
    end

    return attrs, #attrs
end

---BATCH MODE: Process ALL documents in a single transaction.
---Extracts attributes from all contexts first (CPU-bound), then does
---a single database transaction for all inserts.
---@param data DataManager
---@param contexts table Array of Context objects
---@param diagnostics Diagnostics
function M.on_initialize(data, contexts, diagnostics)
    local all_attrs = {}
    local spec_ids = {}
    local total_count = 0

    -- Phase 1: Extract attributes from ALL documents (CPU-bound)
    -- This maximizes CPU utilization by doing all extraction before any DB I/O
    for _, ctx in ipairs(contexts) do
        if ctx.doc then
            local spec_id = ctx.spec_id or "default"
            table.insert(spec_ids, spec_id)

            local attrs, count = extract_attributes_from_context(ctx, data)
            for _, attr in ipairs(attrs) do
                table.insert(all_attrs, attr)
            end
            total_count = total_count + count
        end
    end

    -- Phase 2: Single transaction for ALL database operations
    if #spec_ids > 0 then
        data:begin_transaction()

        -- Bulk DELETE for all specs at once
        for _, spec_id in ipairs(spec_ids) do
            data:execute(Queries.content.delete_attributes_by_spec, { spec_id = spec_id })
        end

        -- Insert all attributes in single transaction
        for _, attr in ipairs(all_attrs) do
            data:execute(Queries.content.insert_attribute_value, attr)
        end

        data:commit()
    end

    -- Log summary
    if total_count > 0 then
        logger.info(string.format("Extracted %d total attributes across %d documents", total_count, #spec_ids))
    end
end

return M
