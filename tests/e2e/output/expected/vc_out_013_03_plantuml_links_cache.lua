-- Test oracle for VC-OUT-013 (TP 03): PlantUML Diagram Link Cache Invalidation
--
-- Run 1 renders a diagram linking to a section ("Old Title") and a figure
-- ("Figure 2"). Run 2 renames the section and inserts a figure before the
-- linked one: the lowered source (and so diagrams/<sha>.*) must change and
-- the SVG must show "New Title" / "Figure 3", never the stale text. A no-op
-- run 3 must reuse the run-2 diagram (deterministic lowering).

return function(_, helpers)
    local engine = require("core.engine")
    local task_runner = require("infra.process.task_runner")

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

    local base_dir = helpers.build_dir .. "/diagram_links_cache"
    local out_dir = base_dir .. "/build"
    local doc = base_dir .. "/doc.md"
    task_runner.ensure_dir(base_dir)

    local project_info = {
        project = { code = "DIAGCACHE", name = "Diagram Link Cache" },
        template = "default",
        files = { doc },
        output_dir = out_dir,
        output_format = "json",
        outputs = { { format = "json", path = out_dir .. "/{spec_id}.json" } },
        db_file = out_dir .. "/specir.db",
        logging = { level = "WARN" },
    }

    local function source(title, extra_figure)
        return table.concat({
            "# Cache Doc @SPEC-CACHE",
            "",
            "## Overview @SEC-OV",
            "",
            "```puml:links{caption=\"Links\"}",
            "@startuml",
            "Foo --> Bar : [SEC-T](@)",
            "note right of Bar : [puml:target](#)",
            "@enduml",
            "```",
            "",
            "## " .. title .. " @SEC-T",
            "",
            extra_figure and "```puml:extra{caption=\"Extra\"}\n@startuml\nA -> B\n@enduml\n```\n" or "",
            "```puml:target{caption=\"Target\"}",
            "@startuml",
            "C -> D",
            "@enduml",
            "```",
            "",
        }, "\n")
    end

    ---Run the engine and return the links diagram {sha, puml, svg}.
    local function build(label)
        local ok, err = pcall(engine.run_project, project_info)
        if not ok then return nil, label .. ": engine run failed: " .. tostring(err) end
        local json = read(out_dir .. "/doc.json")
        if not json then return nil, label .. ": doc.json missing" end
        local sha
        pandoc.read(json, "json"):walk({
            Image = function(img)
                local s = img.src:match("^diagrams/(%x+)%.png$")
                local puml = s and read(out_dir .. "/diagrams/" .. s .. ".puml")
                if contains(puml, "Foo --> Bar") then sha = s end
            end
        })
        if not sha then return nil, label .. ": links diagram image not found" end
        return {
            sha = sha,
            puml = read(out_dir .. "/diagrams/" .. sha .. ".puml"),
            svg = read(out_dir .. "/diagrams/" .. sha .. ".svg"),
        }
    end

    assert(task_runner.write_file(doc, source("Old Title", false)))
    local r1, e1 = build("run 1")
    if not r1 then return false, e1 end
    if not contains(r1.puml, "[[#SEC-T{Old Title} Old Title]]") then
        return false, "run 1: lowered source missing section link:\n" .. tostring(r1.puml)
    end
    if not contains(r1.puml, "{Figure 2} Figure 2]]") then
        return false, "run 1: lowered source missing 'Figure 2':\n" .. tostring(r1.puml)
    end
    if not (contains(r1.svg, "Old Title") and contains(r1.svg, "Figure 2")) then
        return false, "run 1: SVG missing 'Old Title' / 'Figure 2'"
    end

    require("luv").sleep(1000)

    -- Run 2: retitle the target section and renumber the target figure.
    -- The diagram's own source text is unchanged.
    assert(task_runner.write_file(doc, source("New Title", true)))
    local r2, e2 = build("run 2")
    if not r2 then return false, e2 end
    if r2.sha == r1.sha then
        return false, "run 2: lowered source hash unchanged after the targets changed (stale render cache)"
    end
    if not contains(r2.puml, "[[#SEC-T{New Title} New Title]]") or not contains(r2.puml, "{Figure 3} Figure 3]]") then
        return false, "run 2: lowered source not updated:\n" .. tostring(r2.puml)
    end
    if contains(r2.svg, "Old Title") or contains(r2.svg, "Figure 2") then
        return false, "run 2: SVG still shows stale display text"
    end
    if not (contains(r2.svg, "New Title") and contains(r2.svg, "Figure 3")) then
        return false, "run 2: SVG missing 'New Title' / 'Figure 3'"
    end

    -- Run 3: no change -> same lowered source, same cached diagram
    local r3, e3 = build("run 3")
    if not r3 then return false, e3 end
    if r3.sha ~= r2.sha then
        return false, "run 3: no-op rebuild changed the lowered source hash (nondeterministic lowering)"
    end

    return true
end
