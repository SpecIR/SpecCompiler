-- Test oracle for VC-OUT-013 (TP 06): PlantUML diagram link edge cases
--
-- Builds a 2-document project (html5 + markdown) in-process:
--  * cross-doc link into "sys design.md" -> href "sys%20design.html#SEC-9"
--  * links in ' and /' '/ comments: not registered, no unresolved error
--  * ~[click here](#): not registered, rendered literally (PlantUML drops ~)
--  * width="50%": HTML build succeeds, size lands in the root svg style
--  * participant "Name" as X [SEC-2](@): the whole participant box (rect +
--    text) is the link, the authored name is kept
--  * PNG-only build dir (SVG deleted) re-renders the SVG on the next build

return function(_, helpers)
    local engine = require("core.engine")
    local task_runner = require("infra.process.task_runner")
    local sqlite = require("lsqlite3")

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

    local base_dir = helpers.build_dir .. "/diagram_links_edge"
    local out_dir = base_dir .. "/build"
    task_runner.ensure_dir(base_dir)
    os.remove(out_dir .. "/specir.db")

    local function doc_a(extra)
        return table.concat({
            "# Spec A @SPECA-1",
            "",
            "## Overview @SEC-1",
            "",
            "Body link [SEC-9](@).",
            "",
            "```puml:edge{caption=\"Edge\" width=\"50%\"}",
            "@startuml",
            "participant \"Foo\\nBox\" as Foo [SEC-2](@)",
            "Foo -> Bar : remote [SEC-9](@)",
            "' commented [GONE-1](@)",
            "/' block",
            "[GONE-2](@) '/",
            "Bar -> Foo : ~[click here](#)",
            "@enduml",
            "```",
            "",
            "```puml:plain{caption=\"Plain\"}",
            "@startuml",
            "Carol -> Dave : no links",
            "@enduml",
            "```",
            "",
            "## Details @SEC-2",
            "",
            "Details." .. (extra or ""),
            "",
        }, "\n")
    end
    assert(task_runner.write_file(base_dir .. "/a.md", doc_a()))
    assert(task_runner.write_file(base_dir .. "/sys design.md", "# Spec B @SPECB-1\n\n## Remote @SEC-9\n\nRemote.\n"))

    local project_info = {
        project = { code = "DIAGEDGE", name = "Diagram Link Edge Cases" },
        template = "default",
        files = { base_dir .. "/a.md", base_dir .. "/sys design.md" },
        output_dir = out_dir,
        output_format = "html5",
        outputs = {
            { format = "html5", path = out_dir .. "/www/{spec_id}.html" },
            { format = "markdown", path = out_dir .. "/md/{spec_id}.md" },
        },
        html5 = { standalone = true, embed_resources = true },
        db_file = out_dir .. "/specir.db",
        logging = { level = "WARN" },
    }

    local ok, run_err = pcall(engine.run_project, project_info)
    if not ok then
        return false, "engine run failed (commented/escaped links must not be errors): " .. tostring(run_err)
    end

    -- Registration: commented and escaped links are not relations
    local db = sqlite.open(out_dir .. "/specir.db")
    local targets = {}
    for row in db:nrows("SELECT target_text FROM spec_relations WHERE specification_ref = 'a'") do
        targets[row.target_text] = (targets[row.target_text] or 0) + 1
    end
    db:close()
    for _, t in ipairs({ "GONE-1", "GONE-2", "click here" }) do
        check(targets[t] == nil, "link '" .. t .. "' (comment/escape) was registered")
    end
    check((targets["SEC-9"] or 0) == 2, "expected body + diagram relations to SEC-9, got " .. tostring(targets["SEC-9"]))

    -- Lowered sources
    local pumls = {}
    for name in (io.popen('ls "' .. out_dir .. '/diagrams"'):read("*a")):gmatch("[^\n]+") do
        local sha = name:match("^(%x+)%.puml$")
        if sha then pumls[sha] = read(out_dir .. "/diagrams/" .. name) end
    end
    local edge_sha, plain_sha
    for sha, src in pairs(pumls) do
        if contains(src, "Foo -> Bar") then edge_sha = sha end
        if contains(src, "Carol -> Dave") then plain_sha = sha end
    end
    check(edge_sha and plain_sha, "missing lowered diagram sources")
    if edge_sha then
        local src = pumls[edge_sha]
        check(contains(src, "[[sys%20design.ext#SEC-9{sys design: Remote} sys design: Remote]]"),
            "cross-doc href into a spec with a space not percent-encoded:\n" .. src)
        check(contains(src, "~[click here](#)"), "escaped link must stay verbatim in the source")
        local svg = read(out_dir .. "/diagrams/" .. edge_sha .. ".svg") or ""
        check(contains(svg, "[click here](#)") and not contains(svg, "~[click here]"),
            "escaped link must render literally without the ~")
        check(contains(src, 'participant "Foo\\nBox" as Foo [[#SEC-2{Details} Details]]'),
            "participant link not lowered after the alias:\n" .. src)
        local box  -- <a> attribute order differs across PlantUML versions
        for tag, inner in svg:gmatch("(<a [^>]*>)(.-)</a>") do
            if contains(tag, ' href="#SEC-2"') then box = inner break end
        end
        check(box and box:find("<rect") and box:find(">Foo<") and box:find(">Box<"),
            "participant box (rect + authored name) is not wrapped by the link")
    end

    -- HTML: percent width as inline style, encoded cross-doc href
    local html = read(out_dir .. "/www/a.html")
    check(html ~= nil, "a.html missing (percent width must not crash the HTML filter)")
    if html then
        check(select(2, html:gsub('<svg class="speccompiler%-diagram"', "")) == 2,
            "a.html: expected 2 inline diagrams")
        check(html:find('<svg class="speccompiler%-diagram"[^>]-style="width:50%%;') ~= nil,
            "a.html: width=50% not applied as inline style")
        check(contains(html, 'href="sys%20design.html#SEC-9"'), "a.html: encoded cross-doc href missing")
    end

    -- Upgrade: a PNG-only build dir (SVG deleted) re-renders on the next build
    if plain_sha then
        os.remove(out_dir .. "/diagrams/" .. plain_sha .. ".svg")
        require("luv").sleep(1000)
        assert(task_runner.write_file(base_dir .. "/a.md", doc_a(" Edited.")))
        local ok2, err2 = pcall(engine.run_project, project_info)
        check(ok2, "rebuild failed: " .. tostring(err2))
        check(read(out_dir .. "/diagrams/" .. plain_sha .. ".svg") ~= nil,
            "PNG-only cached diagram did not re-render its SVG")
        local html2 = read(out_dir .. "/www/a.html") or ""
        check(select(2, html2:gsub('<svg class="speccompiler%-diagram"', "")) == 2,
            "after upgrade rebuild: expected 2 inline diagrams")
    end

    if #errors > 0 then
        return false, "Diagram link edge cases failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
