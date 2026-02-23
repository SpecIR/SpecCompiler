---Specification Render Handler for SpecCompiler.
---TRANSFORM phase handler that invokes specification type handlers.
---
---Specification types (SRS, SDD, SVC) can define handlers that control
---how the document title (H1) is rendered. This handler loads the type
---module and calls on_render_Specification to generate the header.
---
---The rendered header is stored in the specifications table for the
---assembler to insert at document start.
---
---@module specification_render_handler
local M = {
    name = "specification_render_handler",
    prerequisites = {"specifications"}  -- Runs after specifications are parsed
}

local logger = require("infra.logger")
local Queries = require("db.queries")

-- Cache of loaded specification type handlers
local spec_type_handlers = {}

---Encode Pandoc blocks to JSON for storage.
---@param blocks table Array of Pandoc blocks
---@return string JSON representation
local function encode_ast(blocks)
    if not blocks or #blocks == 0 then return "[]" end

    return pandoc.json.encode(blocks)
end

---Try to load a specification type handler.
---@param type_ref string Type identifier (e.g., "SRS")
---@param model_name string Model name (e.g., "sw_docs")
---@return table|nil handler Handler module or nil if not found
local function load_spec_type_handler(type_ref, model_name)
    -- Check cache first
    local cache_key = model_name .. ":" .. type_ref
    if spec_type_handlers[cache_key] ~= nil then
        return spec_type_handlers[cache_key]
    end

    -- Try to load from model types/specifications
    local type_name = type_ref:lower()
    local module_path = "models." .. model_name .. ".types.specifications." .. type_name

    local ok, type_module = pcall(require, module_path)
    if ok and type_module then
        -- Specification modules have M.handler with on_render_Specification
        local handler = type_module.handler
        if handler and handler.on_render_Specification then
            spec_type_handlers[cache_key] = handler
            logger.debug("Loaded specification type handler", {type_ref = type_ref})
            return handler
        end
    end

    -- Not found or doesn't have on_render_Specification
    spec_type_handlers[cache_key] = false  -- Cache miss
    return nil
end

---TRANSFORM phase: Invoke specification type handlers.
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
            logger.warn(formatted)
        end
    }

    data:begin_transaction()
    for _, ctx in ipairs(contexts) do
        local model_name = ctx.model_name or ctx.template or "default"
        local spec_id = ctx.spec_id or "default"

        -- Query the specification
        local spec = data:query_one(Queries.content.select_specification_for_render,
            { spec_id = spec_id })

        if not spec then
            log.debug("No specification found for: %s", spec_id)
            goto continue
        end

        if not spec.type_ref then
            log.debug("Specification has no type_ref, skipping handler: %s", spec_id)
            goto continue
        end

        -- Try to load the specification type's handler
        local handler = load_spec_type_handler(spec.type_ref, model_name)

        if not handler then
            log.debug("No handler for specification type: %s", spec.type_ref)
            goto continue
        end

        -- Build context for the handler
        local render_ctx = {
            specification = spec,
            spec_id = spec_id,
            output_format = ctx.output_format or "docx"
        }

        -- Call the handler to render the specification header
        local ok, result = pcall(handler.on_render_Specification, render_ctx, pandoc, data)

        if ok and result then
            -- Store the rendered header AST in specifications table
            local header_ast = encode_ast({result})

            data:execute(Queries.content.update_specification_header_ast, {
                spec_id = spec_id,
                header_ast = header_ast
            })

            log.debug("Rendered specification header for: %s (%s)", spec_id, spec.type_ref)
        elseif not ok then
            log.warn("Handler error for specification %s: %s", spec.type_ref, tostring(result))
        end
        ::continue::
    end
    data:commit()
end

return M
