---PID utilities for SpecCompiler.
---Shared functions for parsing and generating project identifiers (PIDs).
---Extracted from specifications.lua for reuse across INITIALIZE and ANALYZE phases.
---
---@module pid_utils
local M = {}

---Parse PID to extract prefix and sequence number.
---Supports: @PREFIX-NN (e.g., @HLR-001) and @NN (e.g., @123)
---@param pid string|nil The PID string (without @)
---@return string|nil prefix, integer|nil sequence, string|nil format
function M.parse_pid_pattern(pid)
    if not pid or pid == "" then
        return nil, nil, nil
    end

    -- Pattern 1: PREFIX-SEQUENCE (e.g., HLR-001, VC-42, PARSE-04)
    local prefix, seq_str = pid:match("^([A-Za-z][A-Za-z0-9_]*)-(%d+)$")
    if prefix and seq_str then
        local sequence = tonumber(seq_str)
        -- Detect format: leading zeros?
        local format_str
        if seq_str:match("^0") and #seq_str > 1 then
            format_str = "%s-%0" .. #seq_str .. "d"  -- e.g., "%s-%03d"
        else
            format_str = "%s-%d"
        end
        return prefix:upper(), sequence, format_str
    end

    -- Pattern 2: SEQUENCE only (e.g., 123, 001)
    local seq_only = pid:match("^(%d+)$")
    if seq_only then
        local sequence = tonumber(seq_only)
        local format_str
        if seq_only:match("^0") and #seq_only > 1 then
            format_str = "%0" .. #seq_only .. "d"  -- e.g., "%03d"
        else
            format_str = "%d"
        end
        return nil, sequence, format_str
    end

    -- Pattern 3: Custom format (no sequence, e.g., @INTRO, @APPENDIX)
    -- Treat as prefix-only, no auto-generation possible
    return pid:upper(), nil, nil
end

---Generate the next PID from a pattern.
---@param prefix string|nil The PID prefix (e.g., "HLR")
---@param format_str string|nil The printf format string (e.g., "%s-%03d")
---@param next_seq integer The next sequence number
---@return string pid The generated PID
function M.generate_next_pid(prefix, format_str, next_seq)
    if prefix then
        return string.format(format_str or "%s-%03d", prefix, next_seq)
    else
        return string.format(format_str or "%d", next_seq)
    end
end

return M
