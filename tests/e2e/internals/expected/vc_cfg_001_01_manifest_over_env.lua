-- Test oracle for VC-CFG-001: Manifest-only configuration (HLR-CFG-001)
--
-- Verifies that build configuration (output format, build directory, log
-- level) is sourced from project.yaml ONLY. The env vars OUTPUT_FORMAT,
-- BUILD_DIR and SPECCOMPILER_LOG_LEVEL must not influence configuration.
--
-- Two layers:
--   1. Functional -- with bogus values monkeypatched into os.getenv,
--      config.extract_metadata() still returns the manifest values.
--   2. Static guard -- the deleted env reads must not reappear in core source
--      (catches a regression that reintroduces an env fallback).

return function(actual_doc, helpers)  -- luacheck: ignore actual_doc helpers
    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    local real_getenv = os.getenv
    local home = real_getenv("SPECCOMPILER_HOME") or "."

    -- ----------------------------------------------------------------------
    -- 1. Functional: config.extract_metadata ignores bogus env, uses manifest
    -- ----------------------------------------------------------------------
    local bogus = {
        OUTPUT_FORMAT = "bogus_format",
        BUILD_DIR = "/bogus/build/dir",
        SPECCOMPILER_LOG_LEVEL = "TRACE_BOGUS",
    }
    os.getenv = function(name)  -- luacheck: ignore
        if bogus[name] ~= nil then return bogus[name] end
        return real_getenv(name)
    end

    local ok, slice_or_err = pcall(function()
        local config = require("core.config")
        return config.extract_metadata({
            project = {
                code = pandoc.MetaString("CFG"),
                name = pandoc.MetaString("Manifest Config"),
            },
            doc_files = { pandoc.MetaString("doc.md") },
            output_dir = pandoc.MetaString("manifest_build"),
            output_format = pandoc.MetaString("json"),
            logging = { level = pandoc.MetaString("ERROR") },
        })
    end)

    os.getenv = real_getenv  -- ALWAYS restore, even on error

    if not ok then
        err("config.extract_metadata raised: " .. tostring(slice_or_err))
    else
        local slice = slice_or_err
        if slice.output_format ~= "json" then
            err("output_format should come from manifest ('json'), got '"
                .. tostring(slice.output_format) .. "'")
        end
        if slice.output_dir ~= "manifest_build" then
            err("output_dir should come from manifest ('manifest_build'), got '"
                .. tostring(slice.output_dir) .. "'")
        end
        if not (slice.logging and slice.logging.level == "ERROR") then
            err("logging.level should come from manifest ('ERROR'), got '"
                .. tostring(slice.logging and slice.logging.level) .. "'")
        end
    end

    -- ----------------------------------------------------------------------
    -- 2. Static guard: the deleted config env reads must not reappear
    -- ----------------------------------------------------------------------
    local function read_src(rel)
        local f = io.open(home .. "/" .. rel, "r")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        return content
    end

    local banned = {
        { rel = "src/core/pipeline.lua",         pat = 'os%.getenv%("OUTPUT_FORMAT"%)' },
        { rel = "src/core/pipeline.lua",         pat = 'os%.getenv%("BUILD_DIR"%)' },
        { rel = "src/pipeline/emit/emitter.lua", pat = 'os%.getenv%("BUILD_DIR"%)' },
        { rel = "src/core/config.lua",           pat = 'os%.getenv%("SPECCOMPILER_LOG_LEVEL"%)' },
        { rel = "src/core/engine.lua",           pat = 'os%.getenv%("SPECCOMPILER_LOG_LEVEL"%)' },
    }
    for _, b in ipairs(banned) do
        local src = read_src(b.rel)
        if not src then
            err("could not read source for static guard: " .. b.rel)
        elseif src:find(b.pat) then
            err(b.rel .. " still reads a config env var matching /" .. b.pat
                .. "/ (HLR-CFG-001 regression)")
        end
    end

    if #errors > 0 then
        return false, "Manifest-only config validation failed:\n  - "
            .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
