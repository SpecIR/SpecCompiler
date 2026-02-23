return function(actual_doc, helpers)
    if not actual_doc or not actual_doc.blocks or #actual_doc.blocks == 0 then
        return false, "Expected non-empty rendered document"
    end

    local text = pandoc.utils.stringify(actual_doc)
    if not text:find("Datatype Sweep", 1, true) then
        return false, "Rendered output missing expected section title"
    end

    local sqlite = require("lsqlite3")
    if not helpers or not helpers.db_file then
        return false, "helpers.db_file not provided by runner"
    end

    local db = sqlite.open(helpers.db_file)
    if not db then
        return false, "Failed to open pipeline DB: " .. tostring(helpers.db_file)
    end

    local errors = {}
    local function err(msg) table.insert(errors, msg) end
    local function assert_eq(actual, expected, label)
        if actual ~= expected then
            err(string.format("%s: expected %s, got %s",
                label, tostring(expected), tostring(actual)))
        end
    end
    local function assert_not_nil(actual, label)
        if actual == nil then
            err(string.format("%s: expected non-nil value", label))
        end
    end
    local function assert_close(actual, expected, eps, label)
        eps = eps or 1e-9
        if type(actual) ~= "number" then
            err(string.format("%s: expected number close to %s, got %s",
                label, tostring(expected), tostring(actual)))
            return
        end
        if math.abs(actual - expected) > eps then
            err(string.format("%s: expected %s±%g, got %s",
                label, tostring(expected), eps, tostring(actual)))
        end
    end

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
        db:close()
        return false, "No specification found in DB"
    end

    local function fetch_spec_attr(name)
        local sql = string.format([[
SELECT
  name, datatype, raw_value,
  string_value, int_value, real_value, bool_value, date_value, enum_ref, ast
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

    local version = fetch_spec_attr("version")
    if not version then
        err("Missing spec attribute: version")
    else
        assert_eq(version.datatype, "STRING", "version.datatype")
        assert_eq(version.string_value, "1.2.3", "version.string_value")
    end

    local build_number = fetch_spec_attr("build_number")
    if not build_number then
        err("Missing spec attribute: build_number")
    else
        assert_eq(build_number.datatype, "INTEGER", "build_number.datatype")
        assert_eq(build_number.int_value, 42, "build_number.int_value")
    end

    local progress = fetch_spec_attr("progress")
    if not progress then
        err("Missing spec attribute: progress")
    else
        assert_eq(progress.datatype, "REAL", "progress.datatype")
        assert_close(progress.real_value, 0.75, 1e-9, "progress.real_value")
    end

    local is_stable = fetch_spec_attr("is_stable")
    if not is_stable then
        err("Missing spec attribute: is_stable")
    else
        assert_eq(is_stable.datatype, "BOOLEAN", "is_stable.datatype")
        assert_eq(is_stable.bool_value, 1, "is_stable.bool_value")
    end

    local release_date = fetch_spec_attr("release_date")
    if not release_date then
        err("Missing spec attribute: release_date")
    else
        assert_eq(release_date.datatype, "DATE", "release_date.datatype")
        assert_eq(release_date.date_value, "2026-02-07", "release_date.date_value")
    end

    local stage = fetch_spec_attr("stage")
    if not stage then
        err("Missing spec attribute: stage")
    else
        assert_eq(stage.datatype, "ENUM", "stage.datatype")
        assert_not_nil(stage.enum_ref, "stage.enum_ref")
        if stage.enum_ref then
            local enum_rows = query(string.format(
                "SELECT key FROM enum_values WHERE identifier = %s LIMIT 1",
                sql_quote(stage.enum_ref)
            ))
            local key = enum_rows[1] and enum_rows[1].key
            assert_eq(key, "Alpha", "stage.enum_ref key")
        end
    end

    local notes = fetch_spec_attr("notes")
    if not notes then
        err("Missing spec attribute: notes")
    else
        assert_eq(notes.datatype, "XHTML", "notes.datatype")
        assert_not_nil(notes.ast, "notes.ast")
    end

    db:close()

    if #errors > 0 then
        return false, "Casting DB validation failed (" .. #errors .. " errors):\n  - "
            .. table.concat(errors, "\n  - ")
    end

    return true, nil
end
