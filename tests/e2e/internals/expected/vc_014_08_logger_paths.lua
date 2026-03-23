-- Test oracle for VC-INT-008: Logger Code Paths
-- Exercises console format, color branches, timestamp, configure, and adapters.
-- Output goes to stderr (harmless); we only care about LCOV coverage.

return function(actual_doc, helpers)
    local logger = require("infra.logger")

    -- Save original stderr and redirect to /dev/null to suppress noise
    local orig_stderr = io.stderr
    local devnull = io.open("/dev/null", "w")
    if devnull then
        io.stderr = devnull
    end

    local ok, err = pcall(function()
        -- ================================================================
        -- 1. Console format, no color, DEBUG level
        -- ================================================================
        logger.configure({ format = "console", color = false, level = "DEBUG" })

        -- Exercise M.log() console path with DEBUG timestamp
        logger.log("debug", "test debug message")
        logger.log("info", "test info message")
        logger.log("info", "test with extra", { key = "value" })

        -- Exercise M.diagnostic() console path with source:line
        logger.diagnostic("error", "test error", "test.md", 42)
        logger.diagnostic("warning", "test warning", "test.md", 0)
        logger.diagnostic("warning", "test warning no source")
        logger.diagnostic("info", "test info diag")

        -- Convenience methods
        logger.info("convenience info")
        logger.debug("convenience debug")
        logger.error("convenience error", "file.lua", 10)
        logger.warning("convenience warning", "file.lua", 5)

        -- ================================================================
        -- 2. Console format WITH color — exercises ANSI code branches
        -- ================================================================
        logger.configure({ format = "console", color = true, level = "DEBUG" })

        logger.log("debug", "colored debug")
        logger.log("info", "colored info")
        logger.log("warn", "colored warn")
        logger.log("error", "colored error")
        logger.diagnostic("error", "colored diag error", "x.md", 1)
        logger.diagnostic("warning", "colored diag warning")

        -- ================================================================
        -- 3. JSON format — exercises JSON output path
        -- ================================================================
        logger.configure({ format = "json", level = "DEBUG" })

        logger.log("debug", "json debug")
        logger.log("info", "json info", { extra_field = 123 })
        logger.diagnostic("error", "json error", "y.md", 99)

        -- ================================================================
        -- 4. Auto format — exercises detect_tty() path
        -- ================================================================
        logger.configure({ format = "auto", level = "INFO" })

        logger.log("info", "auto-detect message")
        logger.diagnostic("warning", "auto-detect diag")

        -- ================================================================
        -- 5. Adapters — exercise create_adapter and create_diagnostic_adapter
        -- ================================================================
        local adapter = logger.create_adapter("DEBUG")
        adapter.debug("adapter debug %s", "test")
        adapter.info("adapter info %d", 42)
        adapter.warn("adapter warn %s", "oops")
        adapter.error("adapter error %s", "fail")

        -- create_adapter with level filtering
        local filtered = logger.create_adapter("ERROR")
        filtered.debug("should be filtered")
        filtered.info("should be filtered")
        filtered.warn("should be filtered")
        filtered.error("only this passes %s", "through")

        -- create_diagnostic_adapter with diagnostics object
        local mock_diag = {
            warn = function() end,
            error = function() end,
        }
        local diag_adapter = logger.create_diagnostic_adapter(mock_diag, "TEST")
        diag_adapter.debug("diag adapter debug")
        diag_adapter.info("diag adapter info")
        diag_adapter.warn("diag adapter warn %s", "val")
        diag_adapter.error("diag adapter error %s", "val")

        -- create_diagnostic_adapter WITHOUT diagnostics (nil) — fallback to logger
        local fallback = logger.create_diagnostic_adapter(nil, "FALLBACK")
        fallback.warn("fallback warn")
        fallback.error("fallback error")
    end)

    -- Restore stderr and reset logger to JSON/WARN for other tests
    io.stderr = orig_stderr
    if devnull then devnull:close() end
    logger.configure({ format = "json", level = "WARN", color = false })

    if not ok then
        return false, "Logger exercise failed: " .. tostring(err)
    end
    return true, nil
end
