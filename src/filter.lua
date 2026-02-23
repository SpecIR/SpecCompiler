---Pandoc Filter Entry Point for SpecCompiler.
---Uses Meta(meta) to process project.yaml metadata FIRST,
---then builds all documents listed in doc_files.

local config = require("core.config")
local engine = require("core.engine")
local logger = require("infra.logger")

---Meta filter function - called by Pandoc when processing metadata.
---This is the entry point for SpecCompiler.
---@param meta table Pandoc metadata from --metadata-file project.yaml
function Meta(meta)
    -- Wrap in pcall to catch errors and exit cleanly
    local ok, err = pcall(function()
        -- Extract project configuration from metadata
        local project_info = config.extract_metadata(meta)

        -- Run the build pipeline for all files
        engine.run_project(project_info)

    end)

    if not ok then
        logger.error(tostring(err))
        os.exit(1)
    end

    -- Explicit success exit avoids a Pandoc/libuv teardown assertion observed
    -- in this environment after Lua filter completion.
    os.exit(0)
end
