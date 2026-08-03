-- Unit test for FIGURE copy-to-build behavior.
--
-- The FIGURE transform must resolve the image path relative to its source
-- file, copy the file into <build_dir>/images/<content-hash><ext> (only when
-- the destination does not already exist), and store the build-relative
-- canonical path in the resolved png-path JSON. When the source file is
-- missing or no build_dir is provided, it falls back to the old behavior of
-- storing the resolved source path.
--
-- Run: dist/bin/lua5.4 tests/figure_copy_test.lua   (from the SpecCompiler root)

local here = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/]+$", "")
package.path = here .. "../src/?.lua;" .. here .. "../src/?/init.lua;" .. package.path
package.cpath = here .. "../dist/vendor/?.so;" .. here .. "../dist/vendor/?/?.so;" .. package.cpath

local figure = dofile(here .. "../models/default/types/floats/figure.lua")
local transform = figure.hooks.transform

local warns = {}
local log = {
    warn = function(fmt, ...) table.insert(warns, string.format(fmt, ...)) end,
    info = function() end,
    debug = function() end,
}

local tmp = (os.getenv("TMPDIR") or "/tmp") .. "/figure_copy_test"
os.execute("rm -rf '" .. tmp .. "'")
os.execute("mkdir -p '" .. tmp .. "/docs/deep/assets' '" .. tmp .. "/docs/other' '" .. tmp .. "/build'")
local build_dir = tmp .. "/build"

local function write(path, content)
    local f = assert(io.open(path, "wb"))
    f:write(content)
    f:close()
end

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local c = f:read("*a")
    f:close()
    return c
end

local IMG_BYTES = "PNG-BYTES-\1\2\3"
write(tmp .. "/docs/deep/assets/img.png", IMG_BYTES)

local from_file = tmp .. "/docs/deep/chapter.md"

local function run(raw, bdir, src_file)
    local dctx = {
        subject = {
            raw_content = raw,
            float = { from_file = src_file or from_file },
            build_dir = bdir,
        },
        log = log,
    }
    return transform(dctx)
end

local function png_path_of(resolved)
    return resolved and resolved:match('"png_path":"([^"]+)"')
end

-- 1. Copies the image into <build_dir>/images under a content-hash name and
--    stores the build-relative canonical path.
local res = assert(run("assets/img.png", build_dir), "transform returned nil")
local png_path = png_path_of(res)
assert(png_path, "no png_path in resolved json: " .. tostring(res))
assert(png_path:match("^images/%x+%.png$"),
    "expected canonical images/<hash>.png path, got: " .. png_path)
assert(read(build_dir .. "/" .. png_path) == IMG_BYTES,
    "copied file missing or bytes differ at " .. build_dir .. "/" .. png_path)

-- 2. Copy is skipped when the destination already exists.
write(build_dir .. "/" .. png_path, "SENTINEL")
local res2 = assert(run("assets/img.png", build_dir))
assert(png_path_of(res2) == png_path, "canonical path not stable across runs")
assert(read(build_dir .. "/" .. png_path) == "SENTINEL",
    "destination was re-copied even though it already existed")

-- 3. Identical bytes referenced from a different source file resolve to the
--    same canonical path (content-addressed dedup).
write(tmp .. "/docs/other/copy.png", IMG_BYTES)
local res3 = assert(run("copy.png", build_dir, tmp .. "/docs/other/page.md"))
assert(png_path_of(res3) == png_path,
    "identical bytes should share one canonical path, got: " .. tostring(png_path_of(res3)))

-- 4. Missing source file: warn and fall back to the resolved source path.
local n_warns = #warns
local res4 = assert(run("assets/missing.png", build_dir), "missing-file fallback returned nil")
assert(png_path_of(res4) == tmp .. "/docs/deep/assets/missing.png",
    "missing source should keep resolved source path, got: " .. tostring(png_path_of(res4)))
assert(#warns > n_warns, "missing source file should log a warning")

-- 5. No build_dir in context: fall back to the resolved source path.
local res5 = assert(run("assets/img.png", nil), "no-build_dir fallback returned nil")
assert(png_path_of(res5) == tmp .. "/docs/deep/assets/img.png",
    "without build_dir the resolved source path should be kept, got: " .. tostring(png_path_of(res5)))

os.execute("rm -rf '" .. tmp .. "'")
print("figure_copy_test: OK")
