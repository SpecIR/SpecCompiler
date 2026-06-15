-- src/pipeline/analyze/attribute_caster.lua
-- Casts raw_value to typed columns based on datatype

local DT = require("core.datatypes")
local Queries = require("db.queries")

local M = {}

-- Datatype handlers keyed by canonical datatype constants
local HANDLERS = {
    [DT.STRING] = function(raw)
        return { string_value = tostring(raw) }
    end,

    [DT.INTEGER] = function(raw)
        local num = tonumber(raw)
        if num and math.floor(num) == num then
            return { int_value = math.floor(num) }
        end
        return nil  -- Cast failed
    end,

    [DT.REAL] = function(raw)
        local num = tonumber(raw)
        if num then
            return { real_value = num }
        end
        return nil
    end,

    [DT.BOOLEAN] = function(raw)
        local lower = raw:lower()
        if lower == "true" or lower == "yes" or lower == "1" or lower == "on" then
            return { bool_value = 1 }
        elseif lower == "false" or lower == "no" or lower == "0" or lower == "off" then
            return { bool_value = 0 }
        end
        return nil
    end,

    [DT.DATE] = function(raw)
        -- Validate YYYY-MM-DD format
        local year, month, day = raw:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
        if year then
            local y, m, d = tonumber(year), tonumber(month), tonumber(day)
            if m >= 1 and m <= 12 and d >= 1 and d <= 31 then
                return { date_value = raw }
            end
        end
        return nil
    end,

    [DT.ENUM] = function(raw, data, datatype_ref)
        -- Look up enum value
        local enum = data:query_one(Queries.resolution.enum_value_by_type_and_key,
            { type = datatype_ref, key = raw })

        if enum then
            return { enum_ref = enum.identifier }
        end
        return nil
    end,

    [DT.XHTML] = function(raw)
        -- XHTML uses ast column, no typed column needed
        -- Just mark as processed (string_value = raw for now)
        return { string_value = raw }
    end
}

---Cast a single raw value to typed columns based on datatype.
---@param raw_value string Raw value string
---@param datatype string Datatype (STRING, INTEGER, REAL, BOOLEAN, DATE, ENUM, XHTML)
---@param data DataManager|nil For ENUM lookups
---@param attr_def table|nil Attribute definition for ENUM datatype_ref
---@return table result Table with typed column values (or nil values if cast fails)
function M.cast(raw_value, datatype, data, attr_def)
    if not raw_value then
        return {}
    end

    local handler = HANDLERS[datatype]
    if not handler then
        -- Unknown datatype, treat as string
        return { string_value = tostring(raw_value) }
    end

    local result
    if datatype == DT.ENUM then
        local datatype_ref = attr_def and attr_def.datatype_ref
        result = handler(raw_value, data, datatype_ref)
    else
        result = handler(raw_value)
    end

    -- Return empty table if cast fails (typed columns will be NULL)
    return result or {}
end

return M
