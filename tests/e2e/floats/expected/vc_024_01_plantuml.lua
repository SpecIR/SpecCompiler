-- Test oracle for VC-FLOAT-003: PlantUML Processing
-- Verifies PlantUML diagrams are processed correctly

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Basic structure check - should have blocks
    if #actual_doc.blocks < 1 then
        err("Document should have blocks")
    end

    -- Check for spec title
    local title_block = actual_doc.blocks[1]
    if title_block and title_block.t == "Div" and title_block.identifier then
        -- Has title, good
    else
        err("Expected spec title Div as first block")
    end

    -- Each PlantUML float keeps the pre-SVG AST shape (Para/Image with the
    -- PNG) in non-HTML output: no wrapper Div, no svg attribute (the SVG
    -- rendition is HTML-only). Both renditions exist on disk.
    local function file_exists(path)
        local f = path and io.open(path, "rb")
        if f then f:close() return true end
        return false
    end
    local diagram_count = 0
    actual_doc:walk({
        Div = function(div)
            if div.classes:includes("speccompiler-svg") then
                err("Unexpected speccompiler-svg wrapper Div")
            end
        end,
        Para = function(para)
            local img = para.content[1]
            if not (img and img.t == "Image" and img.src:match("^diagrams/")) then return end
            diagram_count = diagram_count + 1
            if not img.src:match("^diagrams/%x+%.png$") then
                err("PlantUML image src is not diagrams/<sha>.png: " .. img.src)
            elseif not file_exists(helpers.build_dir .. "/" .. img.src) then
                err("PlantUML PNG missing: " .. helpers.build_dir .. "/" .. img.src)
            end
            if img.attributes.svg then
                err("svg attribute leaked into non-HTML output: " .. img.attributes.svg)
            end
            local svg = helpers.build_dir .. "/" .. img.src:gsub("%.png$", ".svg")
            if not file_exists(svg) then
                err("PlantUML SVG missing: " .. svg)
            end
        end
    })
    if diagram_count ~= 2 then
        err("Expected 2 PlantUML Para/Image diagrams, found " .. diagram_count)
    end

    if #errors > 0 then
        return false, "PlantUML processing validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
