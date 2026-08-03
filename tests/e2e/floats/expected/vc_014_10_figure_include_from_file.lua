-- Test oracle for VC-FLOAT-010: Figure inside an included file
-- The figure's image path must resolve relative to the INCLUDED file
-- (inc/deep/child.md -> inc/deep/img/nested.png), proving from_file is
-- threaded through include expansion, and the copy must land in the build
-- directory under the canonical images/<hash> path with the fixture's bytes.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local images = {}
    actual_doc:walk({
        Image = function(img) table.insert(images, img.src) end
    })

    if #images ~= 1 then
        return false, "expected exactly 1 image, found " .. #images
    end
    local src = images[1]
    if not src:match("^images/%x+%.png$") then
        return false, "image target is not canonical images/<hash>.png: " .. src
    end

    local here = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/]+$", "")
    local function read(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local c = f:read("*a")
        f:close()
        return c
    end

    local copied = read(here .. "../build/" .. src)
    if not copied then
        return false, "copied image missing under build/: " .. src
    end
    if copied ~= read(here .. "../inc/deep/img/nested.png") then
        return false, "copied bytes are not the nested fixture's bytes - wrong file was resolved"
    end

    return true, nil
end
