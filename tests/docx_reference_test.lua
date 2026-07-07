-- Unit tests for reference.docx generation fixes:
--   1. Pandoc's default "Table" style bottom-aligns header cells via a
--      firstRow tblStylePr (vAlign=bottom), sinking short headers below
--      multi-line ones. The generator must flip it to top so DOCX headers
--      match the abntex/LaTeX rendering.
--
-- Run: lua5.4 tests/docx_reference_test.lua   (from the SpecCompiler root)

package.path = "./src/?.lua;./src/?/init.lua;./dist/vendor/?.lua;./dist/vendor/?/init.lua;" .. package.path
package.cpath = "./dist/vendor/?.so;" .. package.cpath

local refgen = require("infra.format.docx.reference_generator")

local function contains(haystack, needle, msg)
    if not haystack:find(needle, 1, true) then
        error(msg .. "\n  looking for: " .. needle .. "\n  in:\n" .. haystack, 2)
    end
end

local function absent(haystack, needle, msg)
    if haystack:find(needle, 1, true) then
        error(msg .. "\n  unexpected:  " .. needle .. "\n  in:\n" .. haystack, 2)
    end
end

-- Pandoc default styles.xml excerpt: Table style with firstRow vAlign=bottom,
-- plus an unrelated style whose vAlign must not be touched.
local styles_xml = [[
<w:styles>
  <w:style w:type="table" w:default="1" w:styleId="Table">
    <w:name w:val="Table" />
    <w:tblStylePr w:type="firstRow">
      <w:tcPr>
        <w:tcBorders>
          <w:bottom w:val="single"/>
        </w:tcBorders>
        <w:vAlign w:val="bottom"/>
      </w:tcPr>
    </w:tblStylePr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Other">
    <w:tcPr><w:vAlign w:val="bottom"/></w:tcPr>
  </w:style>
</w:styles>
]]

do
    local out = refgen.fix_table_header_valign(styles_xml)
    contains(out, '<w:tblStylePr w:type="firstRow">',
        "firstRow tblStylePr must be preserved")
    absent(out:match('<w:tblStylePr w:type="firstRow">.-</w:tblStylePr>'),
        'w:val="bottom"/>',
        "firstRow header cells must not stay bottom-aligned")
    contains(out, '<w:vAlign w:val="top"/>',
        "firstRow header cells must become top-aligned")
    contains(out, '<w:style w:type="paragraph" w:styleId="Other">\n    <w:tcPr><w:vAlign w:val="bottom"/></w:tcPr>',
        "vAlign outside firstRow blocks must be left untouched")
end

-- Integration: run against the REAL pandoc default styles.xml, not just the
-- hand-made excerpt, so pattern drift in pandoc's output is caught.
do
    local tmp = os.tmpname()
    local ok = os.execute("pandoc --print-default-data-file reference.docx > " .. tmp .. " 2>/dev/null")
    if ok then
        local pipe = io.popen("unzip -p " .. tmp .. " word/styles.xml 2>/dev/null")
        local real_styles = pipe and pipe:read("*a")
        if pipe then pipe:close() end
        os.remove(tmp)
        assert(real_styles and #real_styles > 0, "could not extract styles.xml from pandoc default reference.docx")

        local first_row = real_styles:match('<w:tblStylePr w:type="firstRow">.-</w:tblStylePr>')
        assert(first_row, "pandoc default has no firstRow tblStylePr -- test fixture is stale")
        assert(first_row:find('vAlign', 1, true),
            "pandoc default firstRow no longer sets vAlign -- fix may be obsolete")

        local out = refgen.fix_table_header_valign(real_styles)
        local out_first_row = out:match('<w:tblStylePr w:type="firstRow">.-</w:tblStylePr>')
        absent(out_first_row, 'w:val="bottom"',
            "real pandoc firstRow must not remain bottom-aligned")
        contains(out_first_row, 'w:val="top"',
            "real pandoc firstRow must become top-aligned")
    else
        os.remove(tmp)
        print("SKIP: pandoc not available for integration check")
    end
end

-- 2. Preset cache must track the whole extends chain -----------------------
-- uspsc/academico extends abnt/academico; editing the BASE preset must
-- invalidate the reference.docx cache (previously only the top file was hashed).
do
    local preset_loader = require("infra.format.docx.preset_loader")
    local home = os.getenv("SPECCOMPILER_HOME") or "."

    local chain = preset_loader.resolve_chain_paths(home, "uspsc", "academico")
    assert(type(chain) == "table", "resolve_chain_paths must return a list")
    assert(#chain == 2, "uspsc/academico chain must have 2 presets, got " .. tostring(#chain))
    contains(chain[1], "models/uspsc/styles/academico/preset.lua", "chain[1] must be the top preset")
    contains(chain[2], "models/abnt/styles/academico/preset.lua", "chain[2] must be the extended base preset")
end

do
    local reference_cache = require("infra.reference_cache")

    -- Minimal in-memory stand-in for the db handler (build_meta key/value)
    local store = {}
    local db = {
        exec_sql = function() end,
        query_all = function(_, _, params)
            local v = store[params.key]
            if v == nil then return {} end
            return { { value = v } }
        end,
        execute = function(_, _, params)
            store[params.key] = params.value
            return true
        end,
    }

    local dir = os.tmpname() .. "_d"
    os.execute("mkdir -p " .. dir)
    local top, base, ref = dir .. "/top.lua", dir .. "/base.lua", dir .. "/reference.docx"
    local function write(path, content)
        local f = assert(io.open(path, "w")); f:write(content); f:close()
    end
    write(top, "return { name = 'top' }")
    write(base, "return { name = 'base' }")
    write(ref, "stub")

    local paths = { top, base }
    assert(reference_cache.update_hash(db, paths), "update_hash must succeed")
    assert(reference_cache.needs_rebuild(db, paths, ref) == false,
        "fresh hash must not need rebuild")

    write(base, "return { name = 'base CHANGED' }")
    assert(reference_cache.needs_rebuild(db, paths, ref) == true,
        "changing the extended BASE preset must invalidate the cache")

    os.execute("rm -rf " .. dir)
end

print("PASS: docx_reference_test")
