-- Test oracle for VC-029: generated reference.docx table header alignment.

return function(actual_doc, helpers)
    local errors = {}
    local function check(condition, message)
        if not condition then errors[#errors + 1] = message end
    end

    check(actual_doc and actual_doc.blocks and #actual_doc.blocks > 0,
        "expected a non-empty rendered document")

    local build_dir = helpers.build_dir .. "/reference-table-header"
    local input_path = helpers.suite_dir .. "/vc_029_07_reference_table_header.md"
    local docx_path = build_dir .. "/document.docx"
    local reference_path = build_dir .. "/reference.docx"
    local db_path = build_dir .. "/reference-table-header.db"
    require("infra.process.task_runner").ensure_dir(build_dir)

    local engine = require("core.engine")
    local generated, generation_err = pcall(engine.run_project, {
        project = {code = "TEST_DOCX_REF_TABLE", name = "Reference table header"},
        template = "default",
        files = {input_path},
        output_dir = build_dir,
        output_format = "docx",
        outputs = {{format = "docx", path = docx_path}},
        db_file = db_path,
        docx = {
            preset = "test_preset_default",
            reference_doc = reference_path,
        },
        logging = {level = "WARN"},
    })
    check(generated, "DOCX/reference generation failed: " .. tostring(generation_err))

    if generated then
        local docx_helpers = require("docx_helpers")
        local valid, valid_err = docx_helpers.is_valid_docx(reference_path)
        check(valid, "generated reference.docx is invalid: " .. tostring(valid_err))

        local styles = docx_helpers.extract_from_docx(reference_path, "word/styles.xml")
        check(styles ~= nil, "generated reference.docx has no word/styles.xml")
        if styles then
            local first_row = styles:match('<w:tblStylePr w:type="firstRow">.-</w:tblStylePr>')
            check(first_row ~= nil, "Pandoc Table style has no firstRow override")
            if first_row then
                check(first_row:find('w:val="top"', 1, true) ~= nil,
                    "generated firstRow table style is not top-aligned")
                check(first_row:find('w:val="bottom"', 1, true) == nil,
                    "generated firstRow table style remains bottom-aligned")
            end
        end
    end

    -- Scope guard: the rewrite must not alter vAlign outside firstRow.
    local refgen = require("infra.format.docx.reference_generator")
    local fixture = [[
<w:styles>
  <w:style w:type="table" w:styleId="Table">
    <w:tblStylePr w:type="firstRow"><w:tcPr><w:vAlign w:val="bottom"/></w:tcPr></w:tblStylePr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Other">
    <w:tcPr><w:vAlign w:val="bottom"/></w:tcPr>
  </w:style>
</w:styles>
]]
    local rewritten = refgen.fix_table_header_valign(fixture)
    local rewritten_first_row = rewritten:match(
        '<w:tblStylePr w:type="firstRow">.-</w:tblStylePr>'
    ) or ""
    check(rewritten_first_row:find('w:val="top"', 1, true) ~= nil,
        "firstRow fixture was not top-aligned")
    check(rewritten:find(
        '<w:style w:type="paragraph" w:styleId="Other">\n    <w:tcPr><w:vAlign w:val="bottom"/></w:tcPr>',
        1,
        true
    ) ~= nil, "vAlign outside firstRow was unexpectedly changed")

    if #errors > 0 then
        return false, "Reference table-header validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true
end
