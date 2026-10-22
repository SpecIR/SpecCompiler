-- Test oracle for VC-OUT-013 (TP 02): PlantUML Diagram Links in HTML
--
-- Builds a 2-document project (html5 + docx + markdown) in-process. doc a has
-- a PlantUML diagram linking to a same-doc section, a same-doc figure and a
-- section of doc b. HTML (per-spec page and SPA index) must inline the SVG
-- with working hrefs ('#ANCHOR', 'b.html#ANCHOR', no '.ext', no
-- target="_top") instead of the PNG <img>; DOCX and Markdown keep the PNG.

return function(_, helpers)
    local engine = require("core.engine")
    local task_runner = require("infra.process.task_runner")
    local docx_helpers = require("docx_helpers")

    local errors = {}
    local function check(cond, msg)
        if not cond then errors[#errors + 1] = msg end
    end
    local function contains(s, needle)
        return type(s) == "string" and s:find(needle, 1, true) ~= nil
    end
    local function read(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local c = f:read("*a")
        f:close()
        return c
    end

    local base_dir = helpers.build_dir .. "/diagram_links_html"
    local out_dir = base_dir .. "/build"
    task_runner.ensure_dir(base_dir)

    assert(task_runner.write_file(base_dir .. "/a.md", [[
# Spec A @SPECA-1

## Overview @SEC-1

Body links [SEC-2](@), [puml:other](#) and [SEC-9](@).

```puml:arch{caption="Architecture" width="300"}
@startuml
class Foo
class Bar
Foo --> Bar : see [SEC-2](@)
note right of Bar : [puml:other](#) and [SEC-9](@)
@enduml
```

## Details @SEC-2

```puml:other{caption="Other"}
@startuml
Alice -> Bob : hi
@enduml
```
]]))
    assert(task_runner.write_file(base_dir .. "/b.md", [[
# Spec B @SPECB-1

## Remote @SEC-9

Remote section.
]]))

    local ok, run_err = pcall(engine.run_project, {
        project = { code = "DIAGLINKS", name = "Diagram Links HTML" },
        template = "default",
        files = { base_dir .. "/a.md", base_dir .. "/b.md" },
        output_dir = out_dir,
        output_format = "html5",
        outputs = {
            { format = "html5", path = out_dir .. "/www/{spec_id}.html" },
            { format = "docx", path = out_dir .. "/docx/{spec_id}.docx" },
            { format = "markdown", path = out_dir .. "/md/{spec_id}.md" },
        },
        html5 = { standalone = true, embed_resources = true },
        db_file = out_dir .. "/specir.db",
        logging = { level = "WARN" },
    })
    if not ok then
        return false, "engine run failed: " .. tostring(run_err)
    end

    -- Body links give the reference display texts for the diagram links
    local md_a = read(out_dir .. "/md/a.md")
    check(md_a ~= nil, "markdown output a.md missing")

    local function check_html(name, html)
        check(html ~= nil, name .. " missing")
        if not html then return end
        local svg = html:match('<svg class="speccompiler%-diagram"[^>]*>.-</svg>')
        check(svg ~= nil, name .. ": no inline <svg class=\"speccompiler-diagram\">")
        if not svg then return end
        check(contains(svg, 'href="#SEC-2"'), name .. ": svg missing href=\"#SEC-2\"")
        check(contains(svg, 'href="#SEC-2-puml-other"'), name .. ": svg missing href=\"#SEC-2-puml-other\"")
        check(contains(svg, 'href="b.html#SEC-9"'), name .. ": svg missing href=\"b.html#SEC-9\"")
        check(not contains(svg, ".ext#"), name .. ": svg still has a .ext placeholder href")
        check(not contains(svg, 'target="_top"'), name .. ": svg still has target=\"_top\"")
        check(not contains(svg, 'xlink:show="new"'), name .. ": svg still has xlink:show=\"new\"")
        check(not contains(svg, "<?xml"), name .. ": inline svg kept the XML prolog")
        -- Display text laid out by PlantUML = body link display text
        for _, text in ipairs({ "Details", "Figure 2", "b: Remote" }) do
            check(contains(svg, text), name .. ": svg missing display text '" .. text .. "'")
        end
        -- The arch diagram is the inline SVG, not the PNG
        check(not html:find("<img[^>]-diagrams/"), name .. ": diagram still emitted as PNG <img>")
        check(not html:find("<img[^>]-data:image/png"), name .. ": diagram still emitted as embedded PNG <img>")
    end

    local html_a = read(out_dir .. "/www/a.html")
    check_html("a.html", html_a)
    if html_a then
        local inline_count = select(2, html_a:gsub('<svg class="speccompiler%-diagram"', ""))
        check(inline_count == 2, "a.html: expected 2 inline diagrams, found " .. inline_count)
    end
    check_html("index.html", read(out_dir .. "/www/index.html"))

    -- Markdown keeps the PNG image (no SVG wrapper leaks into the output)
    if md_a then
        for _, link in ipairs({ "[Details](#SEC-2)", "[Figure 2](#SEC-2-puml-other)", "[b: Remote](b.md#SEC-9)" }) do
            check(contains(md_a, link), "a.md: body link display differs from the diagram's: " .. link)
        end
        check(md_a:find("!%[[^%]]*%]%([^)]*diagrams/%x+%.png") ~= nil, "a.md: PNG diagram image missing")
        check(not contains(md_a, "speccompiler-svg"), "a.md: speccompiler-svg wrapper leaked")
        check(not contains(md_a, "<svg"), "a.md: inline svg leaked into markdown")
    end

    -- DOCX embeds the PNG rendition
    local docx = out_dir .. "/docx/a.docx"
    check(docx_helpers.is_valid_docx(docx), "a.docx missing or invalid")
    if docx_helpers.is_valid_docx(docx) then
        local png_media, svg_media = 0, 0
        for _, part in ipairs(docx_helpers.list_files(docx)) do
            if part:match("^word/media/.+%.png$") then png_media = png_media + 1 end
            if part:match("^word/media/.+%.svg$") then svg_media = svg_media + 1 end
        end
        check(png_media >= 2, "a.docx: expected the 2 PNG diagrams in word/media, found " .. png_media)
        check(svg_media == 0, "a.docx: unexpected SVG media")
    end

    if #errors > 0 then
        return false, "PlantUML diagram links (HTML) failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true
end
