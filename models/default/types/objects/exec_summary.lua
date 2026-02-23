---Executive Summary object type for the default model.
---An unnumbered section for document executive summaries.
---
---Usage:
---  ## EXEC_SUMMARY: Executive Summary
---  This document provides...

local spec_object_base = require("pipeline.shared.spec_object_base")

local M = {}

M.object = {
    id = "EXEC_SUMMARY",
    long_name = "Executive Summary",
    description = "Executive summary section",
    is_composite = true,
    numbered = false,
    implicit_aliases = { "executive summary", "exec summary" },
}

M.handler = spec_object_base.create_handler("exec_summary_handler", {
    unnumbered = true,
    skip_attributes = true,
})

return M
