---Assembler for SpecCompiler.
---Reconstructs Pandoc AST from the IR database.
---Queries spec_objects, spec_floats, and spec_views, then assembles
---a complete Pandoc document for output.
---
---@module assembler
local Queries = require("db.queries")

local M = {}

---Decode AST JSON back to proper Pandoc blocks.
---Uses pandoc.read with JSON format to ensure proper object reconstruction.
---@param ast_json string JSON-encoded AST
---@return table|nil blocks Array of Pandoc blocks, or nil on error
local function decode_ast(ast_json)
    if not ast_json or ast_json == "" then
        return nil
    end

    -- Check if already a full Pandoc document
    if ast_json:match('^%s*{%s*"pandoc%-api%-version"') then
        -- Full document - read directly
        local ok, doc = pcall(pandoc.read, ast_json, "json")
        if ok and doc then
            return doc.blocks
        end
    elseif ast_json:match('^%s*%[') then
        -- Array of blocks - wrap in document structure for proper parsing
        local doc_json = '{"pandoc-api-version":[1,23,1],"meta":{},"blocks":' .. ast_json .. '}'
        local ok, doc = pcall(pandoc.read, doc_json, "json")
        if ok and doc then
            return doc.blocks
        end
    elseif ast_json:match('^%s*{%s*"t"') then
        -- Single block - wrap in array then document
        local doc_json = '{"pandoc-api-version":[1,23,1],"meta":{},"blocks":[' .. ast_json .. ']}'
        local ok, doc = pcall(pandoc.read, doc_json, "json")
        if ok and doc then
            return doc.blocks
        end
    end

    return nil
end

---Adjust header levels for cross-file includes.
---@param blocks table Array of Pandoc blocks
---@param level_offset number Level adjustment (positive = deeper)
---@return table blocks Modified blocks
local function adjust_header_levels(blocks, level_offset)
    if level_offset == 0 or not blocks then
        return blocks
    end

    for _, block in ipairs(blocks) do
        if block.t == "Header" then
            block.level = math.min(math.max(block.level + level_offset, 1), 6)
        end
    end

    return blocks
end

---Normalize header levels based on actual hierarchy.
---Finds the minimum header level and shifts all headers so that
---the minimum becomes level 1. This ensures proper numbering when
---the document title is not a Header (e.g., rendered as Div).
---@param blocks table Array of Pandoc blocks
---@return table blocks Modified blocks with normalized levels
local function normalize_header_levels(blocks)
    if not blocks then return blocks end

    -- Find minimum header level in the document
    local min_level = 6
    for _, block in ipairs(blocks) do
        if block.t == "Header" and block.level < min_level then
            min_level = block.level
        end
    end

    -- If min level > 1, normalize so top-level headers become H1
    if min_level > 1 and min_level <= 6 then
        local offset = 1 - min_level  -- e.g., min=2 -> offset=-1
        adjust_header_levels(blocks, offset)
    end

    return blocks
end

---Query and assemble spec_objects into blocks.
---@param data DataManager
---@param spec_id string Specification identifier
---@param log table Logger
---@return table blocks Array of Pandoc blocks
local function assemble_objects(data, spec_id, log)
    local blocks = {}

    -- Query all spec objects ordered by file sequence
    -- Note: Level 1 headers are specifications (in specifications table),
    -- not spec_objects, so only level 2+ content is assembled here
    -- ORDER BY file_seq preserves document order (not from_file which would sort alphabetically)
    local objects = data:query_all(Queries.assembly.select_objects_by_spec, { spec_id = spec_id })

    for _, obj in ipairs(objects or {}) do
        if obj.ast then
            local obj_blocks = decode_ast(obj.ast)
            if obj_blocks then
                local count = 0
                for _, block in ipairs(obj_blocks) do
                    table.insert(blocks, block)
                    count = count + 1
                end
                log.debug("Assembled %d blocks from %s '%s'", count, obj.type_ref, obj.pid or obj.title_text or tostring(obj.id))
            else
                log.warn("Failed to decode AST for %s '%s' from %s (id: %s)",
                    obj.type_ref or "object",
                    obj.title_text or obj.pid or "unknown",
                    obj.from_file or "unknown",
                    tostring(obj.id))
            end
        else
            log.debug("Object has no AST: %s '%s' from %s (type: %s)",
                obj.type_ref or "unknown",
                obj.title_text or tostring(obj.id),
                obj.from_file or "unknown",
                obj.type_ref or "unknown")
        end
    end

    return blocks
end

---Query and assemble spec_floats into a lookup table.
---Floats are not directly inserted into the block stream; instead,
---the backend uses this map to resolve float references.
---@param data DataManager
---@param spec_id string Specification identifier
---@param log table Logger
---@return table float_map Map of label/identifier to float data
local function assemble_floats(data, spec_id, log)
    local float_map = {}

    local floats = data:query_all(Queries.assembly.select_floats_by_spec, { spec_id = spec_id })

    for _, float in ipairs(floats or {}) do
        float_map[float.id] = float
        if float.label and float.label ~= "" then
            float_map[float.label] = float
        end
    end

    log.debug("Assembled %d floats for specification: %s", #(floats or {}), spec_id)
    return float_map
end

---Query and assemble spec_views into a lookup table.
---Views are resolved during transform phase and inserted where referenced.
---@param data DataManager
---@param spec_id string Specification identifier
---@param log table Logger
---@return table view_map Map of identifier to view data
local function assemble_views(data, spec_id, log)
    local view_map = {}

    local views = data:query_all(Queries.assembly.select_views_by_spec, { spec_id = spec_id })

    for _, view in ipairs(views or {}) do
        view_map[view.id] = view
    end

    log.debug("Assembled %d views for specification: %s", #(views or {}), spec_id)
    return view_map
end

---Build document metadata from specification and attributes.
---NOTE: We don't add title/author/date to metadata because:
---  1. Custom cover pages (EMB, ABNT) render these with their own styling
---  2. Adding them to metadata causes Pandoc to render a default title block
---  3. Document properties are handled separately by the DOCX writer
---@param data DataManager
---@param spec_id string Specification identifier
---@return table meta Pandoc metadata table
local function build_metadata(data, spec_id)
    local meta = {}

    -- Load attributes for specification (multi-column schema)
    local attrs = data:query_all(Queries.assembly.select_attributes_by_spec, { spec_id = spec_id })

    for _, attr in ipairs(attrs or {}) do
        local value = attr.typed_value or attr.raw_value
        -- Skip title/subtitle/author/date - these cause unwanted Pandoc title blocks
        if value and attr.name ~= "title" and attr.name ~= "subtitle" and attr.name ~= "author" and attr.name ~= "date" then
            meta[attr.name] = pandoc.MetaInlines({ pandoc.Str(tostring(value)) })
        end
    end

    return meta
end

---Assemble a complete Pandoc document from the IR database.
---This is the main entry point for document reconstruction.
---@param data DataManager
---@param spec_id string Specification identifier
---@param log table Logger
---@return pandoc.Pandoc doc The assembled document
---@return table floats Float lookup map
---@return table views View lookup map
function M.assemble_document(data, spec_id, log)
    log = log or { debug = function() end, info = function() end, warn = function() end, error = function() end }

    log.info("Assembling document from IR: %s", spec_id)

    -- 0. Get specification info including rendered header
    local spec = data:query_one(Queries.assembly.select_specification, { spec_id = spec_id })

    -- 1. Build blocks from spec_objects
    local blocks = assemble_objects(data, spec_id, log)

    -- 1.5 Insert H1 document title at the beginning
    -- Use header_ast from specification type handler (rendered during TRANSFORM)
    if spec and spec.header_ast then
        local header_blocks = decode_ast(spec.header_ast)
        if header_blocks and #header_blocks > 0 then
            -- Insert header block(s) at the beginning
            for i = #header_blocks, 1, -1 do
                table.insert(blocks, 1, header_blocks[i])
            end
            log.debug("Inserted specification header from handler: %s", spec.long_name or spec_id)
        end
    elseif pandoc and spec and spec.long_name then
        -- Fallback: generate default title as a Div (not Header, to avoid numbering issues)
        local title_inlines = { pandoc.Str(spec.long_name) }
        local title_para = pandoc.Para(title_inlines)
        local anchor_id = spec.pid or spec_id
        local title_div = pandoc.Div({title_para}, pandoc.Attr(anchor_id, {"spec-title"}, {
            ["custom-style"] = "Title"
        }))
        table.insert(blocks, 1, title_div)
        log.debug("Added default document title: %s", spec.long_name)
    end

    -- 1.7 Insert specification body content (root-level blocks between H1 and first H2)
    -- This content sits under the specification header but outside any spec_object.
    -- E.g., view inlines like `traceability_matrix:` placed at the document root level.
    if spec and spec.body_ast then
        local body_blocks = decode_ast(spec.body_ast)
        if body_blocks and #body_blocks > 0 then
            -- Find insertion point: after header blocks, before spec_object blocks
            -- Header blocks were prepended at the beginning of `blocks`,
            -- so count how many header blocks exist to find the right position.
            local header_count = 0
            if spec.header_ast then
                local hb = decode_ast(spec.header_ast)
                header_count = hb and #hb or 0
            elseif spec.long_name then
                header_count = 1  -- Fallback title Div
            end

            -- Insert body blocks after header blocks
            for i = #body_blocks, 1, -1 do
                table.insert(blocks, header_count + 1, body_blocks[i])
            end
            log.debug("Inserted %d specification body block(s) for %s", #body_blocks, spec_id)
        end
    end

    -- 1.8 Normalize header levels based on actual hierarchy
    -- Since the document title is a Div (not Header), compute the minimum
    -- header level and shift all headers so the top-level becomes H1.
    -- This ensures proper numbering (Introduction = "1" not "0.1")
    normalize_header_levels(blocks)
    log.debug("Normalized header levels for proper numbering")

    -- 2. Build float lookup map
    local floats = assemble_floats(data, spec_id, log)

    -- 3. Build view lookup map
    local views = assemble_views(data, spec_id, log)

    -- 4. Build metadata
    -- Note: Model filters can suppress title/author if needed (e.g., ABNT cover page)
    local meta = {}
    if pandoc then
        meta = build_metadata(data, spec_id)
    end

    -- 5. Create Pandoc document
    local doc
    if pandoc then
        doc = pandoc.Pandoc(blocks, meta)
    else
        doc = { blocks = blocks, meta = meta }
    end

    -- Note: Link rewriting is now done in relation_handler.on_transform
    -- The stored AST already has correct #anchor targets

    log.info("Assembled document with %d blocks", #blocks)

    return doc, floats, views
end

---Assemble blocks for a single spec_object.
---Used for incremental assembly or previews.
---@param data DataManager
---@param object_id string Object identifier
---@param log table Logger
---@return table|nil blocks Array of Pandoc blocks
function M.assemble_object(data, object_id, log)
    log = log or { debug = function() end, warn = function() end }

    local obj = data:query_one(Queries.assembly.select_object_ast, { id = object_id })

    if obj and obj.ast then
        local blocks = decode_ast(obj.ast)
        if blocks then
            log.debug("Assembled %d blocks from object: %s", #blocks, object_id)
            return blocks
        end
    end

    log.warn("Failed to assemble object: %s", object_id)
    return nil
end

---Get assembled float by label or identifier.
---@param floats table Float lookup map from assemble_document
---@param key string Label or identifier to look up
---@return table|nil float Float record or nil
function M.get_float(floats, key)
    return floats and floats[key]
end

---Get assembled view by identifier.
---@param views table View lookup map from assemble_document
---@param key string Identifier to look up
---@return table|nil view View record or nil
function M.get_view(views, key)
    return views and views[key]
end

return M
