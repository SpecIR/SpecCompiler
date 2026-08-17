-- Test oracle for VC-014-09: Figure image copy
-- Verifies the full pipeline's copied image and the transform's edge cases:
-- existing destinations are preserved, identical content is deduplicated,
-- and missing build/source inputs retain their resolved source paths.

return function(actual_doc, helpers)
    local errors = {}
    local function check(condition, message)
        if not condition then errors[#errors + 1] = message end
    end

    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local images = {}
    actual_doc:walk({
        Image = function(img) table.insert(images, img.src) end
    })

    local function read(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local c = f:read("*a")
        f:close()
        return c
    end

    local function write(path, content)
        local f = assert(io.open(path, "wb"))
        f:write(content)
        f:close()
    end

    -- The markdown input exercises the normal end-to-end path.
    check(#images == 1, "expected exactly 1 image, found " .. #images)
    local src = images[1]
    if src then
        check(src:match("^images/%x+%.png$") ~= nil,
            "image target is not canonical images/<hash>.png: " .. src)
        local copied = read(helpers.build_dir .. "/" .. src)
        check(copied ~= nil, "copied image missing under build/: " .. src)
        check(copied == read(helpers.suite_dir .. "/assets/pixel.png"),
            "copied image bytes differ from fixture")
    end

    -- Probe transform-only fallbacks that cannot be expressed by a normal
    -- project build (notably a context without build_dir).
    local task_runner = require("infra.process.task_runner")
    local home = os.getenv("SPECCOMPILER_HOME") or "."
    local figure = dofile(home .. "/models/default/types/floats/figure.lua")
    local transform = figure.hooks.transform
    local probe_dir = helpers.build_dir .. "/figure-copy-probe"
    local source_a = probe_dir .. "/source-a"
    local source_b = probe_dir .. "/source-b"
    local probe_build = probe_dir .. "/build"
    task_runner.ensure_dir(source_a)
    task_runner.ensure_dir(source_b)
    task_runner.ensure_dir(probe_build)

    local bytes = "PNG-PROBE-\1\2\3"
    write(source_a .. "/image.png", bytes)
    write(source_b .. "/copy.png", bytes)

    local warnings = {}
    local log = {
        warn = function(fmt, ...)
            warnings[#warnings + 1] = string.format(fmt, ...)
        end,
        info = function() end,
        debug = function() end,
    }
    local function run(raw, build_dir, from_file)
        return transform({
            subject = {
                raw_content = raw,
                float = {from_file = from_file},
                build_dir = build_dir,
            },
            log = log,
        })
    end
    local function png_path_of(resolved)
        return resolved and resolved:match('"png_path":"([^"]+)"')
    end

    local first = run("image.png", probe_build, source_a .. "/chapter.md")
    local canonical = png_path_of(first)
    check(canonical and canonical:match("^images/%x+%.png$") ~= nil,
        "transform did not return canonical images/<hash>.png: " .. tostring(first))

    if canonical then
        local destination = probe_build .. "/" .. canonical
        check(read(destination) == bytes, "transform did not copy the source bytes")

        write(destination, "SENTINEL")
        local repeated = png_path_of(run("image.png", probe_build, source_a .. "/chapter.md"))
        check(repeated == canonical, "canonical path changed across repeated transforms")
        check(read(destination) == "SENTINEL",
            "existing content-addressed destination was overwritten")

        local duplicate = png_path_of(run("copy.png", probe_build, source_b .. "/page.md"))
        check(duplicate == canonical,
            "identical bytes from another source did not deduplicate")
    end

    local warning_count = #warnings
    local missing_path = source_a .. "/missing.png"
    local missing = png_path_of(run("missing.png", probe_build, source_a .. "/chapter.md"))
    check(missing == missing_path,
        "missing source did not retain resolved path: " .. tostring(missing))
    check(#warnings > warning_count, "missing source did not emit a warning")

    local without_build = png_path_of(run("image.png", nil, source_a .. "/chapter.md"))
    check(without_build == source_a .. "/image.png",
        "context without build_dir did not retain resolved source path")

    if #errors > 0 then
        return false, "Figure copy validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true
end
