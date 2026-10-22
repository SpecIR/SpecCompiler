-- Test oracle for VC-OUT-013 (TP 01): PlantUML Diagram Links
--
-- CommonSpec links written inside a PlantUML float are:
--   * registered as ordinary spec_relations of the float's parent object
--     (source_attribute NULL, link_line = exact .md line) and resolved;
--   * lowered into PlantUML-native [[href{display} display]] with the same
--     display text a body link to the same target gets, before the render
--     (the render cache keys on the lowered source);
--   * rendered as <a href="#..."> in the SVG, while the PNG still exists.
-- PlantUML's own bracket syntax and citations stay verbatim.
-- Also unit-checks source_links.each/replace and the PLANTUML format_link hook.

return function(actual_doc, helpers)
    local sqlite = require("lsqlite3")
    local source_links = require("pipeline.shared.source_links")

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

    local test_name = "vc_out_013_01_plantuml_links"
    local md_path = helpers.suite_dir .. "/" .. test_name .. ".md"
    local md = read(md_path) or ""

    ---1-based line of the first .md line containing needle.
    local function md_line(needle)
        local n = 0
        for line in (md .. "\n"):gmatch("([^\n]*)\n") do
            n = n + 1
            if line:find(needle, 1, true) then return n end
        end
        return nil
    end

    -- ------------------------------------------------------------------
    -- Unit: source_links.each / replace
    -- ------------------------------------------------------------------
    local text = table.concat({
        "@startuml",                                 -- 1
        "A -> B : [SEC-1](@) and [fig:x](#)",        -- 2
        "[Component] -[#red]-> [[http://x label]]",  -- 3
        "[[#native{tip} label]] [multi",             -- 4
        "line](@) [](@) [a](@ b) [key](@cite)",      -- 5
        "[puml:y](#sel)",                            -- 6
        "@enduml",                                   -- 7
    }, "\n")
    local seen = {}
    source_links.each(text, function(content_text, selector, line_offset)
        seen[#seen + 1] = string.format("%s|%s|%d", content_text, selector, line_offset)
    end)
    local want = { "SEC-1|@|2", "fig:x|#|2", "key|@cite|5", "puml:y|#sel|6" }
    check(table.concat(seen, ",") == table.concat(want, ","),
        "source_links.each: expected " .. table.concat(want, ",") .. ", got " .. table.concat(seen, ","))

    local replaced = source_links.replace(text, function(content_text, selector)
        if selector == "@cite" then return nil end
        return "<" .. content_text .. selector .. ">"
    end)
    local want_replaced = text
        :gsub("%[SEC%-1%]%(@%)", "<SEC-1@>")
        :gsub("%[fig:x%]%(#%)", "<fig:x#>")
        :gsub("%[puml:y%]%(#sel%)", "<puml:y#sel>")
    check(replaced == want_replaced,
        "source_links.replace: unexpected result:\n" .. replaced)

    -- ------------------------------------------------------------------
    -- Unit: PLANTUML format_link hook
    -- ------------------------------------------------------------------
    local home = os.getenv("SPECCOMPILER_HOME") or "."
    local plantuml = dofile(home .. "/models/default/types/floats/plantuml.lua")
    local format_link = plantuml.hooks and plantuml.hooks.format_link
    check(type(format_link) == "function", "PLANTUML type has no format_link hook")
    if type(format_link) == "function" then
        local out = format_link({ subject = { href = "b.ext#SEC-9", display_text = "b: [Re]mote {x}" } })
        check(out == "[[b.ext#SEC-9{b: Remote x} b: Remote x]]",
            "format_link: brackets/braces not stripped: " .. tostring(out))
        out = format_link({ subject = { href = "#SEC-2", display_text = "Details" } })
        check(out == "[[#SEC-2{Details} Details]]", "format_link: unexpected " .. tostring(out))
    end

    -- ------------------------------------------------------------------
    -- Body links: target -> display text (the reference for diagram links)
    -- ------------------------------------------------------------------
    local body_display = {}
    actual_doc:walk({
        Link = function(link)
            body_display[link.target] = pandoc.utils.stringify(link.content)
        end
    })
    local expected_body = {
        ["#SEC-DET"] = "Details",
        ["#SEC-OVR"] = "Overview",
        ["#SEC-DET-puml-seq"] = "Figure 2",
    }
    for target, display in pairs(expected_body) do
        check(body_display[target] == display, string.format(
            "body link %s: expected display '%s', got '%s'", target, display, tostring(body_display[target])))
    end

    -- ------------------------------------------------------------------
    -- Emitted diagrams: Para/Image with the PNG (no wrapper Div and no svg
    -- attribute outside HTML); the SVG rendition sits next to it on disk
    -- ------------------------------------------------------------------
    local diagrams = {}  -- puml source -> {sha, svg, png}
    actual_doc:walk({
        Div = function(div)
            check(not div.classes:includes("speccompiler-svg"), "unexpected speccompiler-svg wrapper Div")
        end,
        Image = function(img)
            local sha = img.src:match("^diagrams/(%x+)%.png$")
            if sha then
                check(img.attributes.svg == nil, "svg attribute leaked into JSON output")
                diagrams[#diagrams + 1] = {
                    sha = sha,
                    puml = read(helpers.build_dir .. "/diagrams/" .. sha .. ".puml"),
                    svg = read(helpers.build_dir .. "/diagrams/" .. sha .. ".svg"),
                    png = read(helpers.build_dir .. "/" .. img.src),
                }
            end
        end
    })
    check(#diagrams == 2, "expected 2 PlantUML diagrams, found " .. #diagrams)

    local arch, seq
    for _, d in ipairs(diagrams) do
        check(d.puml ~= nil, "lowered source missing: diagrams/" .. d.sha .. ".puml")
        check(d.svg ~= nil, "SVG missing for diagram " .. d.sha)
        check(d.png ~= nil, "PNG missing for diagram " .. d.sha)
        -- The render cache is content-addressed by the LOWERED source
        check(d.puml == nil or pandoc.sha1(d.puml) == d.sha,
            "diagram file name is not the sha1 of the lowered source: " .. d.sha)
        if contains(d.puml, "class Foo") then arch = d end
        if contains(d.puml, "Alice -> Bob") then seq = d end
    end
    check(arch ~= nil and seq ~= nil, "could not identify the arch/seq diagrams")

    -- ------------------------------------------------------------------
    -- Lowering: same display text as body links; native syntax untouched
    -- ------------------------------------------------------------------
    if arch and arch.puml then
        for _, target in ipairs({ "#SEC-DET", "#SEC-OVR", "#SEC-DET-puml-seq" }) do
            local display = body_display[target] or "?"
            local native = string.format("[[%s{%s} %s]]", target, display, display)
            check(contains(arch.puml, native), "arch.puml missing lowered link " .. native)
        end
        for _, verbatim in ipairs({ "Foo -[#red]-> Bar", "[Component]", "[[http://x label]]", "[doe2026](@cite)" }) do
            check(contains(arch.puml, verbatim), "arch.puml should keep verbatim: " .. verbatim)
        end
        for _, gone in ipairs({ "[SEC-DET](@)", "[SEC-OVR](@)", "[plantuml:seq](#)" }) do
            check(not contains(arch.puml, gone), "arch.puml still has unlowered link " .. gone)
        end
    end
    if seq and seq.puml then
        check(contains(seq.puml, "[[#SEC-OVR-puml-arch{Figure 1} Figure 1]]"),
            "seq.puml missing lowered link to Figure 1:\n" .. seq.puml)
    end

    -- ------------------------------------------------------------------
    -- SVG: PlantUML emitted real hyperlinks
    -- ------------------------------------------------------------------
    if arch and arch.svg then
        for _, href in ipairs({ "#SEC-DET", "#SEC-OVR", "#SEC-DET-puml-seq" }) do
            check(contains(arch.svg, '<a href="' .. href .. '"'), "arch SVG missing <a href=\"" .. href .. "\">")
        end
    end
    if seq and seq.svg then
        check(contains(seq.svg, '<a href="#SEC-OVR-puml-arch"'), "seq SVG missing <a href=\"#SEC-OVR-puml-arch\">")
    end

    -- ------------------------------------------------------------------
    -- Relations: registered like body links of the float's parent object
    -- ------------------------------------------------------------------
    local db = sqlite.open(helpers.db_file)
    if not db then
        check(false, "cannot open DB " .. tostring(helpers.db_file))
    else
        local function rows(sql, params)
            local out = {}
            local stmt = db:prepare(sql)
            if not stmt then
                check(false, "SQL prepare failed: " .. db:errmsg())
                return out
            end
            if params then stmt:bind_names(params) end
            for row in stmt:nrows() do out[#out + 1] = row end
            stmt:finalize()
            return out
        end

        -- Diagram links: (link text, selector, expected parent PID, expected target)
        local cases = {
            { needle = "see [SEC-DET](@)", sel = "@", parent = "SEC-OVR", target_pid = "SEC-DET" },
            { needle = "[plantuml:seq](#) and", sel = "#", parent = "SEC-OVR", target_float = "SEC-DET-puml-seq" },
            { needle = "and [SEC-OVR](@)", sel = "@", parent = "SEC-OVR", target_pid = "SEC-OVR" },
            { needle = "[doe2026](@cite)", sel = "@cite", parent = "SEC-OVR" },
            { needle = "back to [puml:arch](#)", sel = "#", parent = "SEC-DET", target_float = "SEC-OVR-puml-arch" },
        }
        for _, c in ipairs(cases) do
            local line = md_line(c.needle)
            check(line ~= nil, "fixture line not found: " .. c.needle)
            local found = rows([[
                SELECT r.source_attribute, r.from_file, r.link_selector,
                       src.pid AS source_pid, tobj.pid AS target_pid, tf.anchor AS target_anchor
                FROM spec_relations r
                JOIN spec_objects src ON src.id = r.source_object_id
                LEFT JOIN spec_objects tobj ON tobj.id = r.target_object_id
                LEFT JOIN spec_floats tf ON tf.id = r.target_float_id
                WHERE r.link_line = :line AND r.link_selector = :sel
            ]], { line = line or -1, sel = c.sel })
            if #found ~= 1 then
                check(false, string.format("'%s': expected 1 relation at line %s, found %d",
                    c.needle, tostring(line), #found))
            else
                local r = found[1]
                check(r.source_pid == c.parent, string.format("'%s': source object %s, expected float parent %s",
                    c.needle, tostring(r.source_pid), c.parent))
                check(r.source_attribute == nil, "'" .. c.needle .. "': source_attribute should be NULL")
                check(contains(r.from_file, test_name .. ".md"), "'" .. c.needle .. "': from_file " .. tostring(r.from_file))
                if c.target_pid then
                    check(r.target_pid == c.target_pid, string.format("'%s': resolved to object %s, expected %s",
                        c.needle, tostring(r.target_pid), c.target_pid))
                end
                if c.target_float then
                    check(r.target_anchor == c.target_float, string.format("'%s': resolved to float %s, expected %s",
                        c.needle, tostring(r.target_anchor), c.target_float))
                end
            end
        end
        db:close()
    end

    if #errors > 0 then
        return false, "PlantUML diagram links failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true
end
