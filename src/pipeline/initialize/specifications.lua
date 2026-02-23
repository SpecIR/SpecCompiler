---Specifications Handler for SpecCompiler.
---Parses document headers and registers the specification (L1 header).
---Stores parsed headers in ctx for spec_objects handler.
---
---PID auto-generation has been moved to the ANALYZE phase (pid_generator.lua).
---This handler only extracts explicit @PID values from headers.
---
---@module specifications
local logger = require("infra.logger")
local pid_utils = require("pipeline.shared.pid_utils")
local Queries = require("db.queries")
local attribute_para = require("pipeline.shared.attribute_para_utils")

local M = {
    name = "specifications",
    prerequisites = {}  -- Runs first in INITIALIZE
}

-- Cache for default types
local default_object_type_cache = nil
local default_spec_type_cache = nil

---Query the default object type from spec_object_types.
---Falls back to nil if no default type is configured.
---@param data DataManager
---@return string|nil default_type The default type identifier
local function get_default_object_type(data)
    if default_object_type_cache then
        return default_object_type_cache
    end

    local result = data:query_one(Queries.types.default_object_type)

    if result and result.identifier then
        default_object_type_cache = result.identifier
        return default_object_type_cache
    end

    return nil  -- No default configured
end

---Query the default specification type from spec_specification_types.
---Falls back to nil if no default type is configured.
---@param data DataManager
---@return string|nil default_type The default specification type identifier
local function get_default_specification_type(data)
    if default_spec_type_cache then
        return default_spec_type_cache
    end

    local result = data:query_one(Queries.types.default_spec_type)

    if result and result.identifier then
        default_spec_type_cache = result.identifier
        return default_spec_type_cache
    end

    return nil  -- No default configured
end

---Clear module-level caches (required for re-entrant engine.run_project calls).
function M.clear_cache()
    default_object_type_cache = nil
    default_spec_type_cache = nil
end

---Strip @PID from the end of a Header's inline content list.
---Walks backwards to remove trailing Str("@PID") and preceding Space elements.
---@param inlines table Array of Pandoc Inlines (modified in-place)
---@param pid string The PID to strip (without @ prefix)
local function strip_pid_from_inlines(inlines, pid)
    local n = #inlines
    if n == 0 then return end

    -- Check if the last Str element contains @PID
    local last = inlines[n]
    if last.t == "Str" and last.text:match("\\?@" .. pid:gsub("%-", "%%-") .. "$") then
        -- Remove @PID from the Str text (handles "word@PID" edge case)
        local cleaned = last.text:gsub("%s*\\?@" .. pid:gsub("%-", "%%-") .. "$", "")
        if cleaned == "" then
            table.remove(inlines, n)
            -- Remove trailing Space element(s)
            while #inlines > 0 and inlines[#inlines].t == "Space" do
                table.remove(inlines)
            end
        else
            inlines[n] = pandoc.Str(cleaned)
        end
    end
end

---Parse header content to extract type, title, PID, and PID pattern components.
---Supports: TYPE: Title @PID, Title @PID, Title
---@param content_str string Header content as string
---@param default_type string|nil Default type if none specified
---@return string|nil type_ref, string title, string|nil pid, string|nil pid_prefix, integer|nil pid_sequence, string|nil pid_format
local function parse_header_content(content_str, default_type)
    local type_ref = default_type  -- May be nil if no default configured
    local title = content_str
    local pid = nil

    -- Pattern 1: TYPE: Title @PID-001
    local type_part, rest = content_str:match("^([A-Z][A-Z0-9_]*):%s*(.+)$")
    if type_part then
        type_ref = type_part
        title = rest
    end

    -- Extract @PID from end of title (also handles escaped \@PID from markdown)
    local title_part, pid_part = title:match("^(.-)%s*\\?@([%w%-_]+)%s*$")
    if pid_part then
        title = title_part
        pid = pid_part
    end

    -- Parse PID to extract prefix and sequence
    local pid_prefix, pid_sequence, pid_format = pid_utils.parse_pid_pattern(pid)

    return type_ref, title, pid, pid_prefix, pid_sequence, pid_format
end

---Get line number from a block's attributes (sourcepos)
---@param block table Pandoc block
---@return number|nil line
local function get_block_line(block)
    if block.attr and block.attr.attributes then
        local pos = block.attr.attributes["data-pos"]
        if pos then
            local line = pos:match("^(%d+):")
            return tonumber(line)
        end
    end
    return nil
end

---Get end line number from a block's attributes (sourcepos)
---Extracts the end line from data-pos format: "start_line:start_col-end_line:end_col"
---Handles compound data-pos (e.g. "4:1-5:1;3:1-18:1") by taking the last end line.
---@param block table Pandoc block
---@return number|nil end_line
local function get_block_end_line(block)
    if block.attr and block.attr.attributes then
        local pos = block.attr.attributes["data-pos"]
        if pos then
            local end_l = pos:match(".*%-(%d+):")
            return tonumber(end_l)
        end
    end
    return nil
end

---Get source file from a block's attributes (from include expansion)
---@param block table Pandoc block
---@return string|nil source_file
local function get_block_source_file(block)
    if block.attr and block.attr.attributes then
        return block.attr.attributes["data-source-file"]
    end
    return nil
end

---Serialize Pandoc blocks to JSON string
---@param blocks table Array of Pandoc blocks
---@return string|nil json
local function blocks_to_json(blocks)
    if not blocks or #blocks == 0 then
        return nil
    end
    return pandoc.json.encode(blocks)
end

---Check if a BlockQuote contains attribute definitions.
---@param blockquote table Pandoc BlockQuote block
---@return boolean True if blockquote is an attribute block
local function is_attribute_blockquote(blockquote)
    local paras = attribute_para.collect_paragraphs(blockquote)
    if #paras == 0 then return false end
    return attribute_para.is_attribute_para(paras[1])
end

---Extract body blocks from an L1 section (blocks after header, excluding attributes).
---Returns blocks that sit between the specification header/metadata and the first L2 header.
---These are root-level content blocks (view inlines, paragraphs, etc.) that are not
---part of any spec_object.
---@param section_blocks table Array of Pandoc blocks from the L1 section
---@return table body_blocks Array of Pandoc blocks representing the body content
local function extract_spec_body_blocks(section_blocks)
    if not section_blocks or #section_blocks == 0 then return {} end

    local body = {}
    for _, block in ipairs(section_blocks) do
        -- Skip the Header block itself
        if block.t == "Header" then
            goto continue
        end
        -- Skip attribute BlockQuotes (version, status, etc.)
        if block.t == "BlockQuote" and is_attribute_blockquote(block) then
            goto continue
        end
        -- Skip Div-wrapped attribute blockquotes (sourcepos compat)
        if block.t == "Div" then
            local div_content = block.c or block.content or {}
            if type(div_content[2]) == "table" then
                div_content = div_content[2]
            end
            if #div_content == 1 and div_content[1].t == "BlockQuote"
                and is_attribute_blockquote(div_content[1]) then
                goto continue
            end
        end
        table.insert(body, block)
        ::continue::
    end
    return body
end

---Check if a type_ref exists in spec_object_types
---@param data DataManager
---@param type_ref string
---@return boolean
local function is_valid_object_type(data, type_ref)
    local result = data:query_all(Queries.types.object_type_exists, { type_ref = type_ref })
    return result and #result > 0
end

---Check if a type_ref exists in spec_specification_types
---@param data DataManager
---@param type_ref string
---@return boolean
local function is_valid_specification_type(data, type_ref)
    local result = data:query_all(Queries.types.spec_type_exists, { type_ref = type_ref })
    return result and #result > 0
end

---Resolve implicit type from title via implicit_type_aliases table
---@param data DataManager
---@param title string
---@return string|nil object_type_id
local function resolve_implicit_type(data, title)
    local trimmed = title:match("^%s*(.-)%s*$")
    local result = data:query_one(Queries.types.implicit_object_type_alias, { alias = trimmed })
    return result and result.object_type_id or nil
end

---Resolve implicit specification type from title via implicit_spec_type_aliases table
---@param data DataManager
---@param title string
---@return string|nil spec_type_id
local function resolve_implicit_spec_type(data, title)
    local trimmed = title:match("^%s*(.-)%s*$")
    local result = data:query_one(Queries.types.implicit_spec_type_alias, { alias = trimmed })
    return result and result.spec_type_id or nil
end

---Extract parsed headers from a single context WITHOUT database operations.
---Sets ctx.parsed_headers and returns specification data for batch insertion.
---@param ctx Context Document context
---@param data DataManager Data manager (for type validation only)
---@param diagnostics Diagnostics
---@return table|nil spec_data Specification data for DB insert, or nil if no L1 header
local function extract_headers_from_context(ctx, data, diagnostics)
    local doc = ctx.doc
    local spec_id = ctx.spec_id or "default"

    local blocks
    local source_path = "unknown"
    if doc then
        if doc.blocks then
            blocks = doc.blocks
            source_path = doc.source_path or "unknown"
        elseif doc.doc and doc.doc.blocks then
            blocks = doc.doc.blocks
            source_path = doc.source_path or "unknown"
        end
    end

    if not blocks then return nil end

    -- First pass: collect all headers
    local headers = {}
    for i, block in ipairs(blocks) do
        if block.t == "Header" then
            local content = block.content
            local title_text
            if pandoc and content then
                title_text = pandoc.utils.stringify(content)
            elseif type(content) == "string" then
                title_text = content
            else
                title_text = ""
            end

            table.insert(headers, {
                index = i,
                block = block,
                level = block.level,
                content = content,
                title_text = title_text,
                identifier = block.identifier or (block.attr and block.attr.identifier),
                classes = block.classes or (block.attr and block.attr.classes) or {},
                attributes = block.attributes or (block.attr and block.attr.attributes) or {},
                line = get_block_line(block) or i,
                source_file = get_block_source_file(block)
            })
        end
    end

    local default_object_type = get_default_object_type(data)
    local default_spec_type = get_default_specification_type(data)

    local parsed_headers = {}
    local spec_data = nil

    for i, header in ipairs(headers) do
        local start_idx = header.index
        local end_idx = (headers[i + 1] and headers[i + 1].index - 1) or #blocks

        local header_default
        if header.level == 1 then
            header_default = default_spec_type
        else
            header_default = default_object_type
        end
        local type_ref, title, pid, pid_prefix, pid_sequence, pid_format = parse_header_content(header.title_text, header_default)

        local section_blocks = {}
        for j = start_idx, end_idx do
            local block = blocks[j]
            if block.t == "Header" and pid and block.attr then
                block.attr.identifier = pid
                -- Strip @PID notation from header inlines — PID is stored
                -- separately and should not appear in rendered output
                if block.content then
                    strip_pid_from_inlines(block.content, pid)
                end
            end
            table.insert(section_blocks, block)
        end

        local end_line = nil
        if #section_blocks > 0 then
            end_line = get_block_end_line(section_blocks[#section_blocks])
                or get_block_line(section_blocks[#section_blocks])
            if not end_line then
                end_line = header.line + #section_blocks
            end
        end

        local ast_json = blocks_to_json(section_blocks)
        local is_valid_type = header.level == 1 and is_valid_specification_type or is_valid_object_type

        -- If no explicit type (defaulted to header_default), try implicit typing from title
        if type_ref == header_default or type_ref == nil then
            if header.level == 1 then
                -- Try implicit specification type from title (e.g., "Trabalho Acadêmico" -> TRABALHO_ACADEMICO)
                local implicit_spec_type = resolve_implicit_spec_type(data, title)
                if implicit_spec_type and is_valid_specification_type(data, implicit_spec_type) then
                    type_ref = implicit_spec_type
                end
            else
                -- Try implicit object type from title (level 2+)
                local implicit_type = resolve_implicit_type(data, title)
                if implicit_type and is_valid_object_type(data, implicit_type) then
                    type_ref = implicit_type
                end
            end
        end

        if type_ref and type_ref ~= header_default and not is_valid_type(data, type_ref) then
            local diag_file = header.source_file or source_path
            if header_default then
                diagnostics:add_warning(
                    diag_file,
                    header.line,
                    string.format("Unknown type '%s', falling back to %s", type_ref, header_default)
                )
                type_ref = header_default
            else
                diagnostics:add_warning(
                    diag_file,
                    header.line,
                    string.format("Unknown type '%s' and no default type configured", type_ref)
                )
            end
        end

        table.insert(parsed_headers, {
            header = header,
            type_ref = type_ref,
            title = title,
            pid = pid,
            pid_prefix = pid_prefix,
            pid_sequence = pid_sequence,
            pid_format = pid_format,
            section_blocks = section_blocks,
            end_line = end_line,
            ast_json = ast_json,
            seq = i
        })

        -- Capture specification data for first L1 header
        if i == 1 and header.level == 1 then
            -- Extract body blocks from L1 section (excludes header and attribute blockquotes)
            local body_blocks = extract_spec_body_blocks(section_blocks)
            local body_ast_json = nil
            if #body_blocks > 0 then
                body_ast_json = blocks_to_json(body_blocks)
            end

            spec_data = {
                identifier = spec_id,
                root_path = source_path,
                long_name = title,
                type_ref = type_ref,
                pid = pid,
                body_ast = body_ast_json
            }
        end
    end

    -- NOTE: PID auto-generation has been moved to ANALYZE phase (pid_generator.lua)
    -- Objects without explicit @PID will have pid = NULL until ANALYZE runs.

    -- Store in context for downstream handlers
    ctx.parsed_headers = parsed_headers
    ctx.source_path = source_path

    return spec_data, #parsed_headers
end

---BATCH MODE: Process ALL documents in a single transaction.
---@param data DataManager
---@param contexts table Array of Context objects
---@param diagnostics Diagnostics
function M.on_initialize(data, contexts, diagnostics)
    local all_specs = {}
    local total_headers = 0

    -- Phase 1: Extract headers from ALL documents (CPU-bound)
    -- This also sets ctx.parsed_headers for each context
    for _, ctx in ipairs(contexts) do
        if ctx.doc then
            local spec_data, header_count = extract_headers_from_context(ctx, data, diagnostics)
            if spec_data then
                table.insert(all_specs, spec_data)
            end
            total_headers = total_headers + header_count
        end
    end

    -- Phase 2: Single transaction for ALL specification inserts
    if #all_specs > 0 then
        data:begin_transaction()

        for _, spec in ipairs(all_specs) do
            data:execute(Queries.content.insert_specification, spec)
        end

        data:commit()
    end

    -- Log summary
    if total_headers > 0 then
        logger.info(string.format("Parsed %d total headers across %d specifications", total_headers, #all_specs))
    end
end

return M
