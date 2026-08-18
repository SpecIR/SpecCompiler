-- Test oracle for VC-OUT-012 (case 01): attributes render for every object.
--
-- A hook-less composite container (SECTION) must get the default object render:
-- its heading at the constant -1 shift with the PID as anchor, its attribute
-- blockquote promoted to the spec-object-attributes card, and its body kept.
-- Raw `> key: value` blockquotes must not survive into the output.

return function(actual_doc, helpers)  -- luacheck: ignore actual_doc
    local suite_dir = helpers.suite_dir .. "/"
    local build_dir = helpers.build_dir .. "/"
    local name = "vc_out_012_01_section_attribute_card"
    local out = build_dir .. name .. "_x.json"
    local db = build_dir .. name .. "_x.db"

    local engine = require("core.engine")
    local ok, gen_err = pcall(engine.run_project, {
        project = { code = "TEST_ASSEMBLY", name = "Section Attribute Card" },
        template = "default",
        files = { suite_dir .. name .. ".md" },
        output_dir = build_dir,
        output_format = "json",
        outputs = {{ format = "json", path = out }},
        db_file = db,
        logging = { level = "ERROR" },
    })
    os.remove(db)
    if not ok then
        return false, "build failed: " .. tostring(gen_err)
    end

    local f = io.open(out, "r")
    if not f then return false, "missing json output: " .. out end
    local content = f:read("*a")
    f:close()
    local doc = pandoc.read(content, "json")

    local headers, attr_divs, blockquotes = {}, {}, 0
    doc:walk{
        Header = function(h)
            headers[#headers + 1] = {
                level = h.level,
                id = h.attr.identifier,
                text = pandoc.utils.stringify(h.content),
            }
        end,
        Div = function(d)
            if d.attr.classes:includes("spec-object-attributes") then
                attr_divs[#attr_divs + 1] = pandoc.utils.stringify(d.content)
            end
        end,
        BlockQuote = function()
            blockquotes = blockquotes + 1
        end,
    }

    local errors = {}
    local function err(m) errors[#errors + 1] = m end

    if #headers ~= 1 then
        err(string.format("expected 1 heading, got %d", #headers))
    else
        local h = headers[1]
        if h.text ~= "Escopo" then err("heading text: " .. tostring(h.text)) end
        if h.level ~= 1 then err("heading level: expected 1, got " .. tostring(h.level)) end
        if h.id ~= "SRS-AC-sec1" then
            err("heading anchor: expected SRS-AC-sec1, got " .. tostring(h.id))
        end
    end

    if #attr_divs ~= 1 then
        err(string.format("expected 1 spec-object-attributes card, got %d", #attr_divs))
    else
        local card = attr_divs[1]
        if not card:find("DESCRIPTION", 1, true)
            or not card:find("Scope of the firmware specification.", 1, true) then
            err("attribute card must show the declared description, got: " .. card)
        end
    end

    if blockquotes ~= 0 then
        err(string.format("raw attribute blockquotes leaked into output (%d)", blockquotes))
    end

    if #errors > 0 then
        return false, "section attribute card:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
