return function(_, helpers)
    local diag = helpers and helpers.diagnostics
    if not diag or type(diag.errors) ~= "table" then
        return false, "Expected diagnostics in expect_errors mode"
    end

    local errors = {}
    local function err(msg) table.insert(errors, msg) end
    local function assert_eq(actual, expected, label)
        if actual ~= expected then
            err(string.format("%s: expected %s, got %s",
                label, tostring(expected), tostring(actual)))
        end
    end
    local function assert_nil(actual, label)
        if actual ~= nil then
            err(string.format("%s: expected nil, got %s", label, tostring(actual)))
        end
    end

    local messages = {}
    for _, e in ipairs(diag.errors) do
        messages[#messages + 1] = tostring(e.message or "")
    end
    local blob = table.concat(messages, "\n")

    local needles = {
        "build_number",
        "progress",
        "is_stable",
        "release_date",
        "stage"
    }

    for _, n in ipairs(needles) do
        if not blob:find(n, 1, true) then
            err("Missing expected cast diagnostic for " .. n)
        end
    end

    local sqlite = require("lsqlite3")
    if not helpers or not helpers.db_file then
        err("helpers.db_file not provided by runner")
    else
        local db = sqlite.open(helpers.db_file)
        if not db then
            err("Failed to open pipeline DB: " .. tostring(helpers.db_file))
        else
            local function query(sql)
                local rows = {}
                for row in db:nrows(sql) do
                    table.insert(rows, row)
                end
                return rows
            end

            local function sql_quote(s)
                return "'" .. tostring(s):gsub("'", "''") .. "'"
            end

            local spec_rows = query("SELECT identifier FROM specifications ORDER BY identifier LIMIT 1")
            local spec_id = spec_rows[1] and spec_rows[1].identifier
            if not spec_id then
                err("No specification found in DB")
            else
                local function fetch_spec_attr(name)
                    local sql = string.format([[
SELECT
  name, datatype, raw_value,
  string_value, int_value, real_value, bool_value, date_value, enum_ref
FROM spec_attribute_values
WHERE specification_ref = %s
  AND owner_object_id IS NULL
  AND owner_float_id IS NULL
  AND name = %s
LIMIT 1
]], sql_quote(spec_id), sql_quote(name))

                    local rows = query(sql)
                    return rows[1]
                end

                local build_number = fetch_spec_attr("build_number")
                if not build_number then
                    err("Missing spec attribute: build_number")
                else
                    assert_eq(build_number.datatype, "INTEGER", "build_number.datatype")
                    assert_eq(build_number.raw_value, "42.50", "build_number.raw_value")
                    assert_nil(build_number.int_value, "build_number.int_value")
                end

                local progress = fetch_spec_attr("progress")
                if not progress then
                    err("Missing spec attribute: progress")
                else
                    assert_eq(progress.datatype, "REAL", "progress.datatype")
                    assert_eq(progress.raw_value, "not-a-number", "progress.raw_value")
                    assert_nil(progress.real_value, "progress.real_value")
                end

                local is_stable = fetch_spec_attr("is_stable")
                if not is_stable then
                    err("Missing spec attribute: is_stable")
                else
                    assert_eq(is_stable.datatype, "BOOLEAN", "is_stable.datatype")
                    assert_eq(is_stable.raw_value, "maybe", "is_stable.raw_value")
                    assert_nil(is_stable.bool_value, "is_stable.bool_value")
                end

                local release_date = fetch_spec_attr("release_date")
                if not release_date then
                    err("Missing spec attribute: release_date")
                else
                    assert_eq(release_date.datatype, "DATE", "release_date.datatype")
                    assert_eq(release_date.raw_value, "2026-99-99", "release_date.raw_value")
                    assert_nil(release_date.date_value, "release_date.date_value")
                end

                local stage = fetch_spec_attr("stage")
                if not stage then
                    err("Missing spec attribute: stage")
                else
                    assert_eq(stage.datatype, "ENUM", "stage.datatype")
                    assert_eq(stage.raw_value, "Gamma", "stage.raw_value")
                    assert_nil(stage.enum_ref, "stage.enum_ref")
                end
            end

            db:close()
        end
    end

    if #errors > 0 then
        return false, "Casting negative validation failed (" .. #errors .. " errors):\n  - "
            .. table.concat(errors, "\n  - ")
    end

    return true, nil
end
