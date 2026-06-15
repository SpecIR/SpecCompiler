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
local registry = require("contract.registry")
local hook_ctx = require("pipeline.shared.hook_ctx")

---Encode Pandoc blocks to JSON for storage.
---@param blocks table Array of Pandoc blocks
---@return string JSON representation
local function encode_ast(blocks)
    if not blocks or #blocks == 0 then return "[]" end

    return pandoc.json.encode(blocks)
end

-- Specification render dispatch reads host:get_hook_inherited("specification", type_ref, "render")
-- (walks the extends chain, like relation render_link).

---TRANSFORM phase: Invoke specification type handlers.
---@param data DataManager
---@param contexts Context[]
---@param diagnostics Diagnostics
function M.on_transform(data, contexts, diagnostics)
    local log = logger.create_diagnostic_adapter(diagnostics, "RENDER")

    data:begin_transaction()
    local host = registry.current()
    for _, ctx in ipairs(contexts) do
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

        -- The host owns the specification render hook.
        local render = host and host:get_hook_inherited("specification", spec.type_ref, "render")

        if not render then
            log.debug("No handler for specification type: %s", spec.type_ref)
            goto continue
        end

        -- The specification render hook receives the canonical frozen ctx
        -- (HLR-EXT-009) with the specification subject; the rendering type's
        -- schema carries declarative render options (show_pid, style).
        local desc = host:get_descriptor("specification", spec.type_ref)
        local render_ctx = hook_ctx.build(
            ctx, data, diagnostics,
            { specification = spec, type_schema = desc and desc.schema or {} },
            "render", spec_id)

        -- Call the handler to render the specification header
        local ok, result = pcall(render, render_ctx)

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
