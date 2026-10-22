-- Test oracle for VC-OUT-013 (TP 05): diagram link hook contract
--
-- HOST-REGISTRY + UNIT CONTRACT TEST -- does not inspect actual_doc.
--  * format_link / mask_comments are valid float hooks with a string return
--    contract; PLANTUML declares both.
--  * A model re-registering PLANTUML with hooks = {} (as abnt does) keeps the
--    default hooks; a type extending PLANTUML inherits them.
--  * handle_result still yields the PNG for a model that overrides only
--    prepare_task (PNG output_path, no relative_dir / no SVG).
--  * mask_comments + source_links: links in PlantUML comments and ~-escaped
--    links are not found; line offsets stay exact.
--  * format_link sanitises the label and percent-encodes spaces in the href.
--  * The HTML filter inlines the SVG rendition (sizes as inline style, even
--    "50%"; .ext -> .html; no target/xlink:show; no prolog) and falls back to
--    the PNG when the SVG cannot be read.

return function(actual_doc, helpers)  -- luacheck: ignore actual_doc
    local errors = {}
    local function err(m) errors[#errors + 1] = m end
    local function check(cond, m) if not cond then err(m) end end
    local function contains(s, needle)
        return type(s) == "string" and s:find(needle, 1, true) ~= nil
    end

    local registry = require("contract.registry")
    local task_runner = require("infra.process.task_runner")
    local source_links = require("pipeline.shared.source_links")

    local executed = {}
    local mock = {
        execute = function(_, _, params) executed[#executed + 1] = params end,
        query_all = function() return {} end,
        query_one = function() return nil end,
        register_resolver = function() end,
        db = { exec_sql = function() end },
    }
    local host = registry.new{ data = mock }
    host:load_model("default")

    -- ------------------------------------------------------------------
    -- Hook contract
    -- ------------------------------------------------------------------
    local format_link = host:get_hook("float", "PLANTUML", "format_link")
    local mask_comments = host:get_hook("float", "PLANTUML", "mask_comments")
    check(type(format_link) == "function", "PLANTUML should expose a format_link hook")
    check(type(mask_comments) == "function", "PLANTUML should expose a mask_comments hook")

    local ok, e = pcall(function()
        host:register{ kind = "float", schema = { id = "BADLINK" },
            hooks = { format_link = function() return 42 end } }
        host:get_hook("float", "BADLINK", "format_link")({ subject = {} })
    end)
    check(not ok and contains(tostring(e), "must return a string"),
        "format_link returning a non-string should fail the return contract: " .. tostring(e))

    -- Model override with hooks = {} keeps the default hooks (abnt pattern)
    host:register{ kind = "float", schema = { id = "PLANTUML", caption_format = "Figura",
        counter_group = "FIGURE", aliases = { "puml", "diagrama" }, needs_external_render = true },
        hooks = {} }
    for _, hook in ipairs({ "prepare_task", "handle_result", "format_link", "mask_comments" }) do
        check(type(host:get_hook("float", "PLANTUML", hook)) == "function",
            "PLANTUML override with hooks = {} lost the default " .. hook .. " hook")
    end

    -- A type extending PLANTUML inherits the link hooks
    host:register{ kind = "float", schema = { id = "SEQDIAG", extends = "PLANTUML",
        aliases = { "seq" }, needs_external_render = true }, hooks = {} }
    for _, hook in ipairs({ "format_link", "mask_comments", "prepare_task" }) do
        check(type(host:get_hook_inherited("float", "SEQDIAG", hook)) == "function",
            "type extending PLANTUML did not inherit " .. hook)
    end

    -- ------------------------------------------------------------------
    -- handle_result fallback: model overriding only prepare_task (PNG-only)
    -- ------------------------------------------------------------------
    local handle_result = host:get_hook("float", "PLANTUML", "handle_result")
    local nolog = setmetatable({}, { __index = function() return function() end end })
    local legacy_dir = helpers.build_dir .. "/hook_contract/legacy"
    task_runner.ensure_dir(legacy_dir)
    assert(task_runner.write_file(legacy_dir .. "/legacy-name.png", "png"))
    executed = {}
    handle_result({
        data = mock, log = nolog,
        subject = { success = true, stderr = "", task = {
            output_path = legacy_dir .. "/legacy-name.png",
            context = { float = { id = 1 }, attrs = {}, hash = "unused",
                diagrams_path = legacy_dir, relative_path = "diagrams/legacy-name.png" },
        } },
    })
    local stored = executed[1] and executed[1].ast
    check(contains(stored, '"png_paths":["diagrams/legacy-name.png"]'),
        "prepare_task-only override: PNG output_path not stored: " .. tostring(stored))
    check(not contains(stored, "svg_paths"), "PNG-only override must not store svg_paths")

    -- Context without relative_dir (HEAD-era contexts made it optional)
    assert(task_runner.write_file(legacy_dir .. "/abc.png", "png"))
    executed = {}
    local hr_ok, hr_err = pcall(handle_result, {
        data = mock, log = nolog,
        subject = { success = true, stderr = "", task = {
            output_path = legacy_dir .. "/abc.png",
            context = { float = { id = 2 }, attrs = {}, hash = "abc", diagrams_path = legacy_dir },
        } },
    })
    check(hr_ok, "handle_result without relative_dir crashed: " .. tostring(hr_err))
    check(contains(executed[1] and executed[1].ast, "abc.png"),
        "handle_result without relative_dir did not store the PNG")

    -- ------------------------------------------------------------------
    -- Comments, escape and line offsets
    -- ------------------------------------------------------------------
    local src = table.concat({
        "A -> B : [X-1](@) and ~[click here](#)",   -- 1: X-1 only
        "' [GONE-1](@) line comment",                -- 2: masked
        "  ' [GONE-2](@) indented comment",          -- 3: masked
        "/' block [GONE-3](@)",                      -- 4: masked
        "[GONE-4](@) '/ C : [fig:y](#)",             -- 5: fig:y only
        "D : don't [Y-1](@)",                        -- 6: apostrophe mid-line is not a comment
    }, "\n")
    local masked = mask_comments({ subject = { raw_content = src } })
    check(#masked == #src, "mask_comments must preserve length")
    check(select(2, masked:gsub("\n", "")) == 5, "mask_comments must preserve newlines")
    local found = {}
    source_links.each(masked, function(text, selector, line)
        found[#found + 1] = text .. selector .. "@" .. line
    end)
    local expected_found = { "X-1@@1", "fig:y#@5", "Y-1@@6" }
    check(table.concat(found, ",") == table.concat(expected_found, ","),
        "masked scan: expected " .. table.concat(expected_found, ",") .. ", got " .. table.concat(found, ","))
    local replaced = source_links.replace("~[a](@) [b](@)", function(text) return "<" .. text .. ">" end)
    check(replaced == "~[a](@) <b>", "replace must keep ~-escaped links verbatim, got " .. replaced)

    -- ------------------------------------------------------------------
    -- format_link sanitising
    -- ------------------------------------------------------------------
    local link = format_link({ subject = { href = "sys design.ext#S-1", display_text = "C:\\t [x] {y}" } })
    check(link == "[[sys%20design.ext#S-1{C:/t x y} C:/t x y]]",
        "format_link sanitising/encoding wrong: " .. tostring(link))

    -- ------------------------------------------------------------------
    -- HTML filter: inline SVG rendition
    -- ------------------------------------------------------------------
    local filters = dofile("models/default/filters/html.lua")
    local function run_html(doc)
        for i = 2, #filters do doc = doc:walk(filters[i]) end  -- [1] is the TOC strip
        return doc
    end
    local svg_path = helpers.build_dir .. "/hook_contract/d.svg"
    assert(task_runner.write_file(svg_path, '<?xml version="1.0" encoding="us-ascii" standalone="no"?>'
        .. '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        .. 'contentStyleType="text/css" height="120px" preserveAspectRatio="none" '
        .. 'style="width:236px;height:120px;background:#FFFFFF;" version="1.1" viewBox="0 0 236 120" width="236px">'
        .. '<a href="b.ext#X" target="_top" title="b: X" xlink:href="b.ext#X" xlink:show="new">'
        .. '<text>b: X</text></a>'
        -- PlantUML 1.2026+ writes target before href
        .. '<a target="_top" href="b.ext#Y" xlink:href="b.ext#Y" xlink:show="new" title="b: Y">'
        .. '<text>b: Y</text></a></svg>'))
    local function image_doc(attrs)
        return pandoc.Pandoc({ pandoc.Para({
            pandoc.Image({}, "diagrams/d.png", "", pandoc.Attr("", {}, attrs)) }) })
    end

    local out = run_html(image_doc({ { "width", "50%" }, { "height", "5cm" }, { "svg", svg_path } }))
    local raw = out.blocks[1].content[1]
    if not (raw and raw.t == "RawInline" and raw.format == "html") then
        err("HTML filter did not inline the SVG rendition (got " .. tostring(raw and raw.t) .. ")")
    else
        local svg = raw.text
        local root = svg:match("<svg[^>]*>") or ""
        check(root:find('^<svg class="speccompiler%-diagram"') ~= nil, "inline svg lacks class speccompiler-diagram")
        check(contains(root, 'style="width:50%;height:5cm;background:#FFFFFF;"'),
            "requested size not applied as inline style: " .. root)
        check(not contains(root, "preserveAspectRatio"), "preserveAspectRatio=none kept")
        check(not contains(svg, "<?xml"), "XML prolog kept")
        check(contains(svg, 'href="b.html#X"') and contains(svg, 'xlink:href="b.html#X"'),
            ".ext placeholder not replaced in href/xlink:href")
        check(contains(svg, '<a href="b.html#Y" xlink:href="b.html#Y"'),
            "target-first <a> (PlantUML 1.2026+) not normalised: " .. svg)
        check(not contains(svg, ".ext#"), ".ext placeholder left in svg")
        check(not contains(svg, 'target="_top"') and not contains(svg, 'xlink:show="new"'),
            "target/xlink:show not removed")
    end

    -- Unsized: renderer size stripped from the style, CSS scales it
    local unsized = run_html(image_doc({ { "svg", svg_path } })).blocks[1].content[1]
    check(unsized.t == "RawInline" and contains(unsized.text, 'style="background:#FFFFFF;"'),
        "unsized inline svg should keep only non-size style")

    -- Unreadable SVG: keep the PNG image, drop the attribute
    local fallback = run_html(image_doc({ { "svg", helpers.build_dir .. "/hook_contract/missing.svg" } }))
    local img = fallback.blocks[1].content[1]
    check(img and img.t == "Image" and img.src == "../diagrams/d.png",
        "missing SVG should fall back to the PNG image")
    check(img and img.attributes.svg == nil, "fallback image kept the svg attribute")

    if #errors > 0 then
        return false, "Diagram link hook contract failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
