---Spec Object Render Handler for SpecCompiler.
---TRANSFORM phase handler that invokes type handlers to render spec objects.
---
---Types like COVER, DEDICATION, etc. can define header() and body() functions
---that transform the stored AST into styled output. This handler loads type
---modules and calls on_render_SpecObject to apply those transformations.
---
---@module spec_object_render_handler
local M = {
    name = "spec_object_render_handler",
    prerequisites = {"attributes", "spec_floats_transform", "relation_link_rewriter"}  -- Runs after float resolution and link rewriting
}

local logger = require("infra.logger")
local attribute_para = require("pipeline.shared.attribute_para_utils")
local Queries = require("db.queries")

-- Cache of loaded type handlers by type_ref
local type_handlers = {}

---Encode Pandoc blocks to JSON for storage.
---Uses pandoc.json.encode for consistency with section_handler.
---@param blocks table Array of Pandoc blocks
---@return string JSON representation
local function encode_ast(blocks)
    if not blocks or #blocks == 0 then return "[]" end

    return pandoc.json.encode(blocks)
end

---Try to load a type handler for a given type_ref.
---@param type_ref string Type identifier (e.g., "COVER")
---@param model_name string Model name (e.g., "abnt")
---@return table|nil handler Handler module or nil if not found
local function load_type_handler(type_ref, model_name)
    -- Check cache first
    local cache_key = model_name .. ":" .. type_ref
    if type_handlers[cache_key] ~= nil then
        return type_handlers[cache_key]
    end

    -- Try to load from model types/objects
    local type_name = type_ref:lower()
    local module_path = "models." .. model_name .. ".types.objects." .. type_name

    local ok, type_module = pcall(require, module_path)
    if ok and type_module then
        -- Type modules can export handler in two ways:
        -- 1. M.handler = {...} with on_render_SpecObject
        -- 2. return base_handler.create(M, name) which returns handler directly
        local handler = type_module.handler or type_module
        if handler and handler.on_render_SpecObject then
            type_handlers[cache_key] = handler
            logger.debug("Loaded type handler", {type_ref = type_ref})
            return handler
        end
    end

    -- Not found or doesn't have on_render_SpecObject
    type_handlers[cache_key] = false  -- Cache miss
    return nil
end

---Query attributes for a spec object.
---Returns both string values and AST for rich content rendering.
---@param data DataManager
---@param object_id string Object identifier
---@return table attributes Map of attribute names to {value, ast} tables
local function get_object_attributes(data, object_id)
    local results = data:query_all(Queries.content.select_attributes_by_owner,
        {owner_id = object_id})

    local attrs = {}
    if results then
        for _, row in ipairs(results) do
            local name = row.name and row.name:lower() or ""
            attrs[name] = {
                value = row.string_value or row.raw_value or "",
                ast = row.ast  -- JSON-encoded Pandoc inlines (may be nil)
            }
        end
    end
    return attrs
end

---Decode stored AST JSON back to Pandoc blocks.
---@param ast_json string JSON-encoded AST
---@return table|nil blocks Array of Pandoc blocks
local function decode_ast(ast_json)
    if not ast_json or ast_json == "" or ast_json == "[]" then
        return {}
    end

    local result = pandoc.json.decode(ast_json)
    if result then
        -- Check if result is a full Pandoc document (has pandoc-api-version or blocks)
        if result["pandoc-api-version"] or result.blocks then
            return result.blocks or {}
        elseif result.t then
            -- Single block, wrap in array
            return { result }
        else
            -- Array of blocks
            return result
        end
    end

    return nil
end

---Filter out Header blocks from an array of blocks.
---The stored AST includes the section header, but type handlers create their own
---styled header, so we need to exclude the original to avoid duplicates.
---@param blocks table Array of Pandoc blocks
---@return table filtered Blocks without Headers
local function filter_headers(blocks)
    if not blocks then return {} end
    local filtered = {}
    for _, block in ipairs(blocks) do
        -- Check block type (handles both table and userdata)
        local block_type = block.t or (block.tag) or ""
        if block_type ~= "Header" then
            table.insert(filtered, block)
        end
    end
    return filtered
end

---Check if a BlockQuote contains attribute definitions.
---A blockquote is an attribute block if its first Para matches the
---attribute pattern (word followed by colon). Each attribute needs
---its own blockquote; multiple attributes in one blockquote are not supported.
---@param blockquote table Pandoc BlockQuote block
---@return boolean is_attribute_block True if blockquote is an attribute block
local function is_attribute_blockquote(blockquote)
    local paras = attribute_para.collect_paragraphs(blockquote)
    if #paras == 0 then return false end
    return attribute_para.is_attribute_para(paras[1])
end

---Filter out attribute BlockQuotes from an array of blocks.
---Attributes are extracted during INITIALIZE phase and rendered by spec_object_base.
---The raw blockquotes should not appear in the rendered output.
---@param blocks table Array of Pandoc blocks
---@return table filtered Blocks without attribute BlockQuotes
local function filter_attribute_blockquotes(blocks)
    if not blocks then return {} end
    local filtered = {}
    for _, block in ipairs(blocks) do
        local block_type = block.t or (block.tag) or ""

        -- Check if block is a BlockQuote containing only attributes
        if block_type == "BlockQuote" and is_attribute_blockquote(block) then
            -- Skip this attribute blockquote
            logger.debug("Filtered attribute blockquote")
        elseif block_type == "Div" then
            -- Check for wrapped BlockQuote (sourcepos)
            local div_content = block.c or block.content or {}
            if type(div_content[2]) == "table" then
                div_content = div_content[2]
            end
            -- If Div contains only an attribute blockquote, skip it
            local is_attr_div = false
            if #div_content == 1 and div_content[1].t == "BlockQuote" then
                if is_attribute_blockquote(div_content[1]) then
                    is_attr_div = true
                end
            end
            if not is_attr_div then
                table.insert(filtered, block)
            end
        else
            table.insert(filtered, block)
        end
    end
    return filtered
end

---Unwrap spec-object wrapper Divs from a previous transform run.
---Extracts children to top level so downstream filters can process them.
---@param blocks table Array of Pandoc blocks
---@return table unwrapped Blocks with spec-object wrappers replaced by their children
local function unwrap_spec_object_divs(blocks)
    if not blocks then return {} end
    local result = {}
    for _, block in ipairs(blocks) do
        local block_type = block.t or (block.tag) or ""
        local is_wrapper = false

        if block_type == "Div" then
            local attrs = block.attr
            local classes = {}
            if attrs then
                if type(attrs.classes) == "table" then
                    classes = attrs.classes
                elseif attrs[2] and type(attrs[2]) == "table" then
                    classes = attrs[2]
                end
            elseif block.c and block.c[1] then
                local attr = block.c[1]
                if type(attr[2]) == "table" then
                    classes = attr[2]
                end
            end
            for _, c in ipairs(classes) do
                if c == "spec-object" then
                    is_wrapper = true
                    break
                end
            end
        end

        if is_wrapper then
            -- Extract children to top level
            local children = block.content or (block.c and block.c[2]) or {}
            for _, child in ipairs(children) do
                table.insert(result, child)
            end
            logger.debug("Unwrapped spec-object Div for idempotent re-transform")
        else
            table.insert(result, block)
        end
    end
    return result
end

---Filter out existing spec-object-attributes Divs from blocks.
---These may exist from a previous transform and should not be duplicated.
---The spec_object_base.render_attributes() will add a fresh one.
---@param blocks table Array of Pandoc blocks
---@return table filtered Blocks without spec-object-attributes Divs
local function filter_spec_object_attr_divs(blocks)
    if not blocks then return {} end
    local filtered = {}
    for _, block in ipairs(blocks) do
        local block_type = block.t or (block.tag) or ""
        local skip = false

        if block_type == "Div" then
            -- Check classes for spec-object-attributes
            -- Pandoc Div structure: {attr, content} where attr = {id, classes, kvpairs}
            local attrs = block.attr
            local classes = {}

            if attrs then
                -- Handle both userdata (Pandoc Attr) and table formats
                if type(attrs.classes) == "table" then
                    classes = attrs.classes
                elseif attrs[2] and type(attrs[2]) == "table" then
                    classes = attrs[2]
                end
            elseif block.c and block.c[1] then
                -- Legacy/alternative format: block.c = {attr, content}
                local attr = block.c[1]
                if type(attr[2]) == "table" then
                    classes = attr[2]
                end
            end

            for _, c in ipairs(classes) do
                if c == "spec-object-attributes" then
                    skip = true
                    logger.debug("Filtered existing spec-object-attributes Div")
                    break
                end
            end
        end

        if not skip then
            table.insert(filtered, block)
        end
    end
    return filtered
end

---Filter out spec-object-header Divs from previous transform runs.
---The base_handler wraps type handler header() output in a Div with this class.
---Filtering this makes type handler rendering idempotent - running TRANSFORM
---multiple times (e.g., on cached documents) produces the same result.
---@param blocks table Array of Pandoc blocks
---@return table filtered Blocks without spec-object-header Divs
local function filter_spec_object_headers(blocks)
    if not blocks then return {} end
    local filtered = {}
    for _, block in ipairs(blocks) do
        local block_type = block.t or (block.tag) or ""
        local skip = false

        if block_type == "Div" then
            -- Check classes for spec-object-header
            local attrs = block.attr
            local classes = {}

            if attrs then
                -- Handle both userdata (Pandoc Attr) and table formats
                if type(attrs.classes) == "table" then
                    classes = attrs.classes
                elseif attrs[2] and type(attrs[2]) == "table" then
                    classes = attrs[2]
                end
            elseif block.c and block.c[1] then
                -- Legacy/alternative format: block.c = {attr, content}
                local attr = block.c[1]
                if type(attr[2]) == "table" then
                    classes = attr[2]
                end
            end

            for _, c in ipairs(classes) do
                if c == "spec-object-header" then
                    skip = true
                    logger.debug("Filtered existing spec-object-header Div (idempotent transform)")
                    break
                end
            end
        end

        if not skip then
            table.insert(filtered, block)
        end
    end
    return filtered
end

---TRANSFORM phase: Invoke type handlers to render spec objects.
---@param data DataManager
---@param contexts Context[]
---@param diagnostics Diagnostics
function M.on_transform(data, contexts, diagnostics)
    local log = {
        debug = function(msg, ...)
            local formatted = select("#", ...) > 0 and string.format(msg, ...) or tostring(msg)
            logger.debug(formatted)
        end,
        info = function(msg, ...)
            local formatted = select("#", ...) > 0 and string.format(msg, ...) or tostring(msg)
            logger.info(formatted)
        end,
        warn = function(msg, ...)
            local formatted = select("#", ...) > 0 and string.format(msg, ...) or tostring(msg)
            if diagnostics then
                diagnostics:warn(nil, nil, "RENDER", formatted)
            else
                logger.warning(formatted)
            end
        end,
        error = function(msg, ...)
            local formatted = select("#", ...) > 0 and string.format(msg, ...) or tostring(msg)
            if diagnostics then
                diagnostics:error(nil, nil, "RENDER", formatted)
            else
                logger.error(formatted)
            end
        end,
    }

    data:begin_transaction()
    for _, ctx in ipairs(contexts) do
        local model_name = ctx.model_name or ctx.template or "default"
        local spec_id = ctx.spec_id or "default"

        -- Query spec objects for this spec that might need type handler rendering
        local objects = data:query_all(Queries.content.select_typed_objects_by_spec,
            { spec_id = spec_id })

        if not objects or #objects == 0 then
            log.debug("No typed spec objects found for rendering")
            goto continue
        end

        log.debug("Processing %d typed spec objects for rendering", #objects)

        local rendered_count = 0
        for _, obj in ipairs(objects) do
            local handler = load_type_handler(obj.type_ref, model_name)

            if handler then
                -- Build context for type handler
                -- Filter out headers, attribute blockquotes, and existing spec-object-attributes divs
                -- - Headers: type handlers create styled headers
                -- - Attribute blockquotes: rendered as DefinitionList by spec_object_base
                -- - Spec-object-attributes divs: prevent duplicate attribute rendering
                local decoded_blocks = decode_ast(obj.ast) or {}
                local unwrapped = unwrap_spec_object_divs(decoded_blocks)
                local body_blocks = filter_spec_object_headers(filter_spec_object_attr_divs(filter_attribute_blockquotes(filter_headers(unwrapped))))

                local render_ctx = {
                    spec_object = obj,
                    spec_id = obj.specification_ref,
                    spec_identifier = obj.specification_ref,
                    attributes = get_object_attributes(data, obj.id),
                    original_blocks = body_blocks,
                    output_format = ctx.output_format or "docx",
                    format = ctx.output_format or "docx",
                    db = data,
                    api = ctx.api,
                    header_level = obj.level or 2,
                }

                -- Call type handler's on_render_SpecObject
                local ok, result = pcall(handler.on_render_SpecObject, obj, render_ctx)

                if ok and result and #result > 0 then
                    -- Encode new blocks and update database
                    local new_ast = encode_ast(result)

                    data:execute(Queries.content.update_object_ast, {
                        ast = new_ast,
                        id = obj.id
                    })

                    rendered_count = rendered_count + 1
                    log.debug("Rendered %s: %s", obj.type_ref, obj.pid or obj.title_text or tostring(obj.id))
                elseif not ok then
                    log.warn("Handler error for %s '%s': %s", obj.type_ref, obj.pid or obj.title_text or tostring(obj.id), tostring(result))
                end
            end
        end

        log.info("Rendered %d spec objects with type handlers", rendered_count)

        -- Patch heading IDs for composite objects (SECTION, EXEC_SUMMARY, etc.).
        -- Composite objects are excluded from full type-handler rendering because
        -- their AST contains nested children whose headers must not be stripped.
        -- This lightweight pass only updates the FIRST header's ID to the PID,
        -- ensuring cross-references like [MANUAL-sec14](@) resolve in HTML output.
        local composites = data:query_all(Queries.content.select_composite_objects_by_spec,
            { spec_id = spec_id })

        local patched = 0
        for _, obj in ipairs(composites or {}) do
            local decoded = decode_ast(obj.ast)
            if decoded and #decoded > 0 then
                -- Find the first Header in the top-level blocks
                for _, block in ipairs(decoded) do
                    local block_type = block.t or (block.tag) or ""
                    if block_type == "Header" then
                        -- Check if the header ID already matches the PID
                        local current_id = ""
                        if block.attr then
                            current_id = block.attr.identifier or
                                         (type(block.attr[1]) == "string" and block.attr[1]) or ""
                        end
                        if current_id ~= obj.pid then
                            -- Update the header ID to the PID
                            if block.attr and block.attr.identifier ~= nil then
                                block.attr.identifier = obj.pid
                            else
                                -- Reconstruct attr preserving classes and kvpairs
                                local classes = block.attr and block.attr[2] or {}
                                local kvpairs = block.attr and block.attr[3] or {}
                                block.attr = pandoc.Attr(obj.pid, classes, kvpairs)
                            end
                            local new_ast = encode_ast(decoded)
                            data:execute(Queries.content.update_object_ast, {
                                ast = new_ast, id = obj.id
                            })
                            patched = patched + 1
                        end
                        break  -- Only patch the first header
                    end
                end
            end
        end

        if patched > 0 then
            log.info("Patched heading IDs for %d composite object(s)", patched)
        end

        ::continue::
    end
    data:commit()
end

return M
