---Float Resolver for SpecCompiler.
---Collects floats and their resolved_ast for EMIT phase.
---Type-specific rendering is delegated to float type handlers.
---
---@module float_resolver
local Queries = require("db.queries")

local M = {}

---Process a float's resolved_ast.
---Returns type="image" for image-producing floats, or {float, resolved} for handler dispatch.
---@param float table Float record with resolved_ast
---@param build_dir string Build directory
---@param log table Logger
---@return table|nil Result for emit_float.lua
local function process_float(float, build_dir, log)
    if not float.resolved_ast then
        log.debug("Float not resolved: %s '%s' from %s",
            float.type_ref or "unknown", float.syntax_key or tostring(float.id), float.from_file or "unknown")
        return nil
    end

    local resolved = float.resolved_ast

    -- Check if resolved_ast is a direct file path (external resolver output like PNG)
    if resolved:match("^/") or resolved:match("^build/") then
        return {
            type = "image",
            paths = { resolved },
            float = float,
            resolved = resolved,
        }
    end

    -- Check for JSON with png_path or png_paths (chart/figure/plantuml resolver output)
    -- This is the generic image pattern - handled by emit_float.lua fallback
    if resolved:match('"png_path') then
        local result = pandoc and pandoc.json and pandoc.json.decode(resolved)
        if result then
            if result.png_path then
                return {
                    type = "image",
                    paths = { result.png_path },
                    float = float,
                    resolved = resolved,
                }
            elseif result.png_paths then
                return {
                    type = "image",
                    paths = result.png_paths,
                    float = float,
                    resolved = resolved,
                }
            end
        end
    end

    -- All other types: return float + resolved for handler dispatch
    -- Type handlers (math, table, listing, etc.) parse their own resolved_ast format
    return {
        float = float,
        resolved = resolved,
    }
end

---Collect floats from database for EMIT phase.
---Reads resolved_ast populated during TRANSFORM phase.
---@param data DataManager
---@param build_dir string Build directory
---@param log table Logger
---@return table float_results Map of syntax_key to {float, resolved, type?, paths?}
function M.resolve_floats(data, build_dir, log)
    local float_results = {}

    -- Query all floats with type metadata (caption_format, counter_group)
    local floats = data:query_all(Queries.content.select_all_floats_with_types)

    for _, float in ipairs(floats) do
        if not float.resolved_ast then
            -- Check if this is an external type (PLANTUML, CHART, etc.) vs internal (TABLE, CSV)
            local type_info = data:query_one(Queries.content.select_float_type_external_render,
                { id = float.type_ref })

            if type_info and type_info.needs_external_render == 1 then
                log.warn("Float %s '%s' from %s: external render did not produce resolved_ast (check TRANSFORM phase logs for render errors)",
                    float.type_ref or "unknown", float.syntax_key or tostring(float.id), float.from_file or "unknown")
            else
                log.warn("Float %s '%s' from %s: no transform handler produced resolved_ast",
                    float.type_ref or "unknown", float.syntax_key or tostring(float.id), float.from_file or "unknown")
            end
        else
            local result = process_float(float, build_dir, log)

            if result then
                -- Use syntax_key from database (stored during INITIALIZE phase)
                -- This matches the code block's first class exactly (e.g., "list-table:req-summary")
                local key = float.syntax_key
                if key and key ~= "" then
                    float_results[key] = result
                    log.debug("Resolved float: %s -> key=%s", tostring(float.id), key)
                else
                    log.warn("Float %s from %s has no syntax_key - cannot match to code block (id: %s)",
                        float.type_ref or "unknown", float.from_file or "unknown", tostring(float.id))
                end
            end
        end
    end

    return float_results
end

return M
