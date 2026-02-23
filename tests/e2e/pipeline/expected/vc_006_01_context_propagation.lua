-- Test oracle for VC-006: Context Propagation
-- Verifies context fields are propagated to handlers and cached spec_ids create EMIT-only contexts.

return function(_, _)
    local pipeline_mod = require("core.pipeline")

    local function nop() end

    local function new_pipeline()
        local log = { debug = nop, info = nop, warn = nop, error = nop }
        local diagnostics = { errors = {}, has_errors = function() return false end }
        local project_info = {
            output_dir = "build/context-tests",
            template = "default",
            project_root = "/tmp/speccompiler-project",
            docx = { preset = "standard" },
            outputs = {
                { format = "json", path = "build/context-tests/out.json" },
                { format = "html5", path = "build/context-tests/out.html" }
            },
            html5 = { standalone = true, number_sections = true },
            bibliography = "refs/sample.bib",
            csl = "refs/sample.csl",
            files = { "docs/example.md" }
        }

        return pipeline_mod.new({
            log = log,
            diagnostics = diagnostics,
            data = {},
            validation = { missing_required = "error" },
            project_info = project_info
        })
    end

    local expected_ref_doc = "/tmp/speccompiler-project/build/context-tests/reference.docx"
    local expected_build_dir = "build/context-tests"

    -- 1) Verify context propagation for explicit docs
    local p = new_pipeline()
    local captured = {}

    p:register_handler({
        name = "capture_initialize_context",
        prerequisites = {},
        on_initialize = function(_, contexts, _)
            for _, c in ipairs(contexts) do
                table.insert(captured, c)
            end
        end
    })

    p:execute(
        {
            { spec_id = "SPEC-CONTEXT-A" },
            { spec_id = "SPEC-CONTEXT-B" }
        },
        {
            skip_phases = {
                pipeline_mod.PHASES.ANALYZE,
                pipeline_mod.PHASES.TRANSFORM,
                pipeline_mod.PHASES.VERIFY,
                pipeline_mod.PHASES.EMIT
            }
        }
    )

    if #captured ~= 2 then
        return false, string.format("Expected 2 captured contexts, got %d", #captured)
    end

    for i, ctx in ipairs(captured) do
        if type(ctx.validation) ~= "table" then
            return false, string.format("Context %d missing validation table", i)
        end
        if ctx.build_dir ~= expected_build_dir then
            return false, string.format("Context %d build_dir mismatch: %s", i, tostring(ctx.build_dir))
        end
        if type(ctx.log) ~= "table" then
            return false, string.format("Context %d missing log table", i)
        end
        if ctx.output_format ~= "docx" then
            return false, string.format("Context %d output_format mismatch: %s", i, tostring(ctx.output_format))
        end
        if ctx.template ~= "default" then
            return false, string.format("Context %d template mismatch: %s", i, tostring(ctx.template))
        end
        if ctx.reference_doc ~= expected_ref_doc then
            return false, string.format("Context %d reference_doc mismatch: %s", i, tostring(ctx.reference_doc))
        end
        if type(ctx.docx) ~= "table" then
            return false, string.format("Context %d missing docx table", i)
        end
        if ctx.project_root ~= "/tmp/speccompiler-project" then
            return false, string.format("Context %d project_root mismatch: %s", i, tostring(ctx.project_root))
        end
        if type(ctx.outputs) ~= "table" or #ctx.outputs ~= 2 then
            return false, string.format("Context %d outputs table mismatch", i)
        end
        if type(ctx.html5) ~= "table" then
            return false, string.format("Context %d missing html5 table", i)
        end
        if ctx.bibliography ~= "refs/sample.bib" then
            return false, string.format("Context %d bibliography mismatch: %s", i, tostring(ctx.bibliography))
        end
        if ctx.csl ~= "refs/sample.csl" then
            return false, string.format("Context %d csl mismatch: %s", i, tostring(ctx.csl))
        end
        if type(ctx.doc) ~= "table" then
            return false, string.format("Context %d missing doc field", i)
        end
        if not tostring(ctx.spec_id):match("^SPEC%-CONTEXT%-") then
            return false, string.format("Context %d spec_id mismatch: %s", i, tostring(ctx.spec_id))
        end
    end

    -- 2) Verify no fallback context when docs is empty (no cached_spec_ids)
    local p_empty = new_pipeline()
    local fallback = {}

    p_empty:register_handler({
        name = "capture_empty_context",
        prerequisites = {},
        on_initialize = function(_, contexts, _)
            for _, c in ipairs(contexts) do
                table.insert(fallback, c)
            end
        end
    })

    p_empty:execute(
        {},
        {
            skip_phases = {
                pipeline_mod.PHASES.ANALYZE,
                pipeline_mod.PHASES.TRANSFORM,
                pipeline_mod.PHASES.VERIFY,
                pipeline_mod.PHASES.EMIT
            }
        }
    )

    if #fallback ~= 0 then
        return false, string.format("Expected 0 INITIALIZE contexts when no docs and no cached_spec_ids, got %d", #fallback)
    end

    -- 3) Verify cached_spec_ids creates contexts for EMIT phase only
    local p_cached = new_pipeline()
    local init_captured = {}
    local emit_captured = {}

    p_cached:register_handler({
        name = "capture_init_context",
        prerequisites = {},
        on_initialize = function(_, ctx, _)
            for _, c in ipairs(ctx) do
                table.insert(init_captured, c)
            end
        end
    })

    p_cached:register_handler({
        name = "capture_emit_context",
        prerequisites = { "capture_init_context" },
        on_emit = function(_, ctx, _)
            for _, c in ipairs(ctx) do
                table.insert(emit_captured, c)
            end
        end
    })

    p_cached:execute(
        {},
        {
            cached_spec_ids = {"spec_a", "spec_b"},
            skip_phases = {
                pipeline_mod.PHASES.ANALYZE,
                pipeline_mod.PHASES.TRANSFORM,
                pipeline_mod.PHASES.VERIFY,
            }
        }
    )

    if #init_captured ~= 0 then
        return false, string.format("Expected 0 INITIALIZE contexts for cached-only build, got %d", #init_captured)
    end
    if #emit_captured ~= 2 then
        return false, string.format("Expected 2 EMIT contexts for cached spec_ids, got %d", #emit_captured)
    end
    for i, ctx in ipairs(emit_captured) do
        if ctx.doc ~= nil then
            return false, string.format("Cached emit context %d should have nil doc", i)
        end
        if ctx.cached ~= true then
            return false, string.format("Cached emit context %d should have cached=true", i)
        end
    end

    return true
end
