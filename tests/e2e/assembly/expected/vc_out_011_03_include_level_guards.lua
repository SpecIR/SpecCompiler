-- Test oracle for VC-OUT-011: Include normalization compatibility and guards.
--
-- The included tree is positioned relative to its shallowest heading:
--
--   guard_h2.md       -> fragment rooted at `##` normalizes to level 3
--   guard_h3.md       -> fragment rooted at `###` normalizes to level 3
--   guard_relative_skip.md -> internal `##` -> `####` gap remains malformed
--   guard_deep_levels.md -> computed levels 6/7/8 remain distinct in SpecIR;
--                           normalized DOCX styles are Heading5/6/7
--
-- This is a self-driving oracle: the suite runs in normal mode, so the primary
-- doc is trivially valid and `actual_doc` is ignored.

local CODE = "object_broken_hierarchy"
local docx = require("docx_helpers")

-- Build a fixture and return its status, diagnostics, and persisted heading
-- levels. Checking the IR levels makes the compatibility assertions independent
-- of the renderer's final whole-document normalization.
local function build_fixture(suite_dir, build_dir, name)
    local engine = require("core.engine")
    local stem = name:gsub("%.md$", "")
    local stamp = tostring(os.clock()):gsub("%.", "")
    local db = build_dir .. "guard_" .. stem .. "_" .. stamp .. ".db"
    local output = build_dir .. "guard_" .. stem .. "_" .. stamp .. ".docx"
    local ok, diag = pcall(engine.run_project, {
        project = { code = "TEST_GUARD", name = "shift guard fixture" },
        template = "default",
        files = { suite_dir .. "fixtures/" .. name },
        output_dir = build_dir,
        output_format = "docx",
        outputs = {{ format = "docx", path = output }},
        db_file = db,
        logging = { level = "ERROR" },
    })
    local result = {
        ok = ok,
        text = ok and "" or tostring(diag),
        hierarchy_count = 0,
        total_errors = ok and #((diag and diag.errors) or {}) or nil,
        levels = {},
        rendered_styles = {},
    }

    if not ok then
        os.remove(db)
        return result
    end

    local messages = {}
    for _, e in ipairs((diag and diag.errors) or {}) do
        if e.code == CODE then
            result.hierarchy_count = result.hierarchy_count + 1
            messages[#messages + 1] = tostring(e.file or "") .. ": " .. tostring(e.message or "")
        end
    end
    for _, w in ipairs((diag and diag.warnings) or {}) do
        if w.code == CODE then
            result.hierarchy_count = result.hierarchy_count + 1
            messages[#messages + 1] = tostring(w.file or "") .. ": " .. tostring(w.message or "")
        end
    end
    result.text = table.concat(messages, " | ")

    local sqlite = require("lsqlite3")
    local handle = sqlite.open(db)
    if handle then
        for row in handle:nrows("SELECT title_text, level FROM spec_objects") do
            result.levels[row.title_text] = tonumber(row.level)
        end
        handle:close()
    end

    local document_xml = docx.get_document_xml(output)
    if document_xml then
        for para in document_xml:gmatch("<w:p[%s>].-</w:p>") do
            local style = para:match('<w:pStyle w:val="(Heading%d+)"')
            if style then
                local parts = {}
                for text in para:gmatch("<w:t[^>]*>(.-)</w:t>") do
                    parts[#parts + 1] = text
                end
                result.rendered_styles[table.concat(parts)] = style
            end
        end
    end
    os.remove(db)
    return result
end

return function(actual_doc, helpers)
    local errors = {}
    local function err(msg) errors[#errors + 1] = msg end

    local suite_dir = helpers.suite_dir .. "/"
    local build_dir = helpers.build_dir .. "/"

    -- Legacy fragments may begin deeper than H1. Their shallowest heading is
    -- normalized to one level below the include point without editing source.
    for _, case in ipairs({
        { file = "guard_h2.md", title = "Not Standalone" },
        { file = "guard_h3.md", title = "Deep Start" },
    }) do
        local result = build_fixture(suite_dir, build_dir, case.file)
        if not result.ok then
            err(case.file .. ": compatibility build aborted: " .. result.text)
        elseif result.total_errors ~= 0 then
            err(string.format("%s: expected no errors, got %d: %s",
                case.file, result.total_errors, result.text))
        elseif result.levels[case.title] ~= 3 then
            err(string.format("%s: expected '%s' at normalized level 3, got %s",
                case.file, case.title, tostring(result.levels[case.title])))
        end
    end

    -- Normalization is uniform, so it must not repair a malformed gap inside
    -- the included fragment.
    local gap = build_fixture(suite_dir, build_dir, "guard_relative_skip.md")
    if not gap.ok then
        err("guard_relative_skip.md: build aborted instead of returning a diagnostic: " .. gap.text)
    elseif gap.hierarchy_count ~= 1 then
        err(string.format("guard_relative_skip.md: expected one hierarchy diagnostic, got %d: %s",
            gap.hierarchy_count, gap.text))
    elseif not (gap.text:find("inc_relative_skip.md", 1, true)
            and gap.text:find("Relative Gap", 1, true)
            and gap.text:find("level 5", 1, true)) then
        err("guard_relative_skip.md: diagnostic did not preserve/identify the relative gap: " .. gap.text)
    end
    if gap.levels["Relative Root"] ~= 3 or gap.levels["Relative Gap"] ~= 5 then
        err(string.format("guard_relative_skip.md: expected normalized levels 3 and 5, got %s and %s",
            tostring(gap.levels["Relative Root"]), tostring(gap.levels["Relative Gap"])))
    end

    -- Include expansion must preserve computed levels beyond six, and the
    -- assembler's uniform normalization must not clamp the rendered result.
    local deep = build_fixture(suite_dir, build_dir, "guard_deep_levels.md")
    if not deep.ok then
        err("guard_deep_levels.md: deep-heading build aborted: " .. deep.text)
    elseif deep.total_errors ~= 0 then
        err(string.format("guard_deep_levels.md: expected no errors, got %d: %s",
            deep.total_errors, deep.text))
    end

    for title, expected_level in pairs({
        ["Deep Six"] = 6,
        ["Deep Seven"] = 7,
        ["Deep Eight"] = 8,
    }) do
        if deep.levels[title] ~= expected_level then
            err(string.format("guard_deep_levels.md: expected '%s' at SpecIR level %d, got %s",
                title, expected_level, tostring(deep.levels[title])))
        end
    end

    for title, expected_style in pairs({
        ["Deep Six"] = "Heading5",
        ["Deep Seven"] = "Heading6",
        ["Deep Eight"] = "Heading7",
    }) do
        if deep.rendered_styles[title] ~= expected_style then
            err(string.format("guard_deep_levels.md: expected '%s' rendered as %s, got %s",
                title, expected_style, tostring(deep.rendered_styles[title])))
        end
    end

    if #errors > 0 then
        return false, "Include level guard failures:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
