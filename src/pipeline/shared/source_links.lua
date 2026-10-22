---Source Links for SpecCompiler.
---Finds CommonSpec links (`[target](@)`, `[prefix:label](#)`, ...) written
---inside the raw text of a float whose source is not Markdown (e.g. PlantUML),
---so they can be registered and resolved like links in body text.
---
---The link text may not contain brackets or a newline, and the selector must
---start with `@` or `#`. This keeps PlantUML's own bracket syntax
---(`[Component]`, `[[url label]]`, `-[#red]->`) from matching. A link
---preceded by `~` (PlantUML's creole escape) is literal text, not a link.
---
---@module source_links
local M = {}

local LINK_PATTERN = "%[([^%[%]\n]+)%]%(([@#][^%s%)]*)%)"

---Call fn for every link in text.
---@param text string Raw float content
---@param fn function fn(content_text, selector, line_offset) where line_offset is the 1-based line within text
function M.each(text, fn)
    local pos, line, scanned = 1, 1, 1
    while true do
        local s, e, content_text, selector = text:find(LINK_PATTERN, pos)
        if not s then return end
        if text:sub(s - 1, s - 1) ~= "~" then
            local _, newlines = text:sub(scanned, s - 1):gsub("\n", "")
            line, scanned = line + newlines, s
            fn(content_text, selector, line)
        end
        pos = e + 1
    end
end

---Replace every link in text with fn's return value.
---@param text string Raw float content
---@param fn function fn(content_text, selector) -> string|nil (nil keeps the link verbatim)
---@return string text
function M.replace(text, fn)
    return (text:gsub("()" .. LINK_PATTERN, function(s, content_text, selector)
        if text:sub(s - 1, s - 1) ~= "~" then
            return fn(content_text, selector)
        end
    end))
end

return M
