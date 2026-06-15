---Canonical reference anchor for a float.
---
---This is the SINGLE source of truth for "what bookmark name does a float get,
---and therefore what must a PAGEREF / cross-reference point at". emit_float emits
---the bookmark under this name; any list generator (LOF/LOT/LOG) or link rewriter
---that references a float MUST resolve to the same string, or the reference
---dangles -- Word shows "Error: Reference source not found". (This is exactly the
---class of bug VC-ABNT-002 was: a list view built its anchor from `syntax_key`
---while the bookmark used `anchor or label`.)
---
---The anchor VALUE is computed once during INITIALIZE (get_float_anchor in
---src/pipeline/initialize/spec_floats.lua) and stored on spec_floats.anchor; this
---module owns the fallback READ so every consumer agrees by construction.
---
---@module float_anchor
local M = {}

---Reference anchor for a float record/row.
---@param float table A spec_floats row or record exposing .anchor and/or .label
---@return string|nil anchor The reference anchor (anchor preferred, label fallback)
function M.ref_anchor(float)
    if not float then return nil end
    return float.anchor or float.label
end

---Stable Word bookmark id derived from a bookmark name.
---Single source of truth for the name->id hash used by every bookmark/PAGEREF
---emitter (emit_float, the docx filter, the equation builder). Keep this
---algorithm byte-identical: changing it invalidates existing bookmark ids.
---@param name string|nil Bookmark name
---@return number Bookmark id (always non-zero)
function M.bookmark_id(name)
    local bm_id = 0
    for i = 1, #(name or "") do
        bm_id = (bm_id * 31 + name:byte(i)) % 100000
    end
    return bm_id + 1
end

return M
