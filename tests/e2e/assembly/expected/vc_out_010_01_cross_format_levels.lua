-- Test oracle for VC-OUT-010: cross-format heading-level consistency.
--
-- LaTeX and DOCX are produced from the same assembled IR, so a heading must land
-- at the same depth in both: a `###` section is `\section` in LaTeX and Heading2
-- in DOCX, never `\subsection`/Heading2 in one and `\section`/Heading3 in the
-- other. This caught the dissertation symptom where a stale LaTeX build nested
-- sections one level deeper than the DOCX. The oracle builds the same fixture to
-- both formats and asserts an identical (title, depth) sequence.

local docx = require("docx_helpers")

local LATEX_LEVEL = { chapter = 1, section = 2, subsection = 3, subsubsection = 4 }

local function read_file(path)
    local f = io.open(path, "r"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c
end

-- (depth, title) for each heading command in document order.
local function latex_headings(tex)
    local seq = {}
    for cmd, title in tex:gmatch("\\(%a+)%s*{(.-)}") do
        local lvl = LATEX_LEVEL[cmd]
        if lvl then seq[#seq + 1] = { level = lvl, title = title } end
    end
    return seq
end

-- (depth, title) for each Heading paragraph in document order.
local function docx_headings(xml)
    local seq = {}
    for para in xml:gmatch("<w:p[%s>].-</w:p>") do
        local n = para:match('<w:pStyle w:val="Heading(%d+)"')
        if n then
            local t = {}
            for s in para:gmatch("<w:t[^>]*>(.-)</w:t>") do t[#t + 1] = s end
            seq[#seq + 1] = { level = tonumber(n), title = table.concat(t) }
        end
    end
    return seq
end

return function(actual_doc, helpers)
    local suite_dir = helpers.suite_dir .. "/"
    local build_dir = helpers.build_dir .. "/"
    local name = "vc_out_010_01_cross_format_levels"
    local stamp = tostring(os.clock()):gsub("%.", "")

    local engine = require("core.engine")
    local function build(fmt, ext)
        local out = build_dir .. name .. "_x." .. ext
        local ok, err = pcall(engine.run_project, {
            project = { code = "TEST_ASSEMBLY", name = "Cross Format" },
            template = "default", style = "default",
            files = { suite_dir .. name .. ".md" },
            output_dir = build_dir, output_format = fmt,
            outputs = {{ format = fmt, path = out }},
            latex = { top_level_division = "chapter", number_sections = true },
            db_file = build_dir .. fmt .. "_" .. stamp .. ".db",
            logging = { level = "ERROR" },
        })
        os.remove(build_dir .. fmt .. "_" .. stamp .. ".db")
        return ok, err, out
    end

    local lok, lerr, tex_path = build("latex", "tex")
    if not lok then return false, "LaTeX build failed: " .. tostring(lerr) end
    local dok, derr, docx_path = build("docx", "docx")
    if not dok then return false, "DOCX build failed: " .. tostring(derr) end

    local tex = read_file(tex_path)
    local xml = docx.get_document_xml(docx_path)
    if not tex then return false, "Could not read LaTeX output" end
    if not xml then return false, "Could not read DOCX document.xml" end

    local lh = latex_headings(tex)
    local dh = docx_headings(xml)
    local expected = {
        { level = 1, title = "Chapter One" },
        { level = 2, title = "Section 1.1" },
        { level = 3, title = "Subsection 1.1.1" },
        { level = 1, title = "Chapter Two" },
        { level = 2, title = "Section 2.1" },
    }

    local errors = {}
    if #lh ~= #dh then
        errors[#errors + 1] = string.format("heading count differs: LaTeX %d, DOCX %d", #lh, #dh)
    end
    local n = math.min(#lh, #dh)
    for i = 1, n do
        if lh[i].level ~= dh[i].level or lh[i].title ~= dh[i].title then
            errors[#errors + 1] = string.format(
                "format mismatch at heading %d: LaTeX [%d] '%s' vs DOCX [%d] '%s'",
                i, lh[i].level, lh[i].title, dh[i].level, dh[i].title)
        end
    end

    -- Cross-format equality alone is insufficient: both renderers could agree
    -- on the same incorrectly assembled hierarchy.
    for format_name, headings in pairs({ LaTeX = lh, DOCX = dh }) do
        if #headings ~= #expected then
            errors[#errors + 1] = string.format(
                "%s: expected %d headings, got %d", format_name, #expected, #headings)
        end
        for i = 1, math.min(#headings, #expected) do
            local got, want = headings[i], expected[i]
            if got.level ~= want.level or got.title ~= want.title then
                errors[#errors + 1] = string.format(
                    "%s heading %d: expected [%d] '%s', got [%d] '%s'",
                    format_name, i, want.level, want.title, got.level, got.title)
            end
        end
    end

    if #errors > 0 then
        return false, "Cross-format heading divergence:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
