---Executive Summary object type for the default model.
---An unnumbered section for document executive summaries.
---
---Usage:
---  ## EXEC_SUMMARY: Executive Summary
---  This document provides...

return {
    kind = "object",
    schema = {
        id = "EXEC_SUMMARY",
        long_name = "Executive Summary",
        description = "Executive summary section",
        pid_scheme = "hierarchical",
        pid_prefix = "exec",  -- own chain: MAN-exec1, not a slot in the sec chain
        numbered = false,
        implicit_aliases = { "executive summary", "exec summary" },
        unnumbered = true,
        skip_attributes = true,
    },
}
