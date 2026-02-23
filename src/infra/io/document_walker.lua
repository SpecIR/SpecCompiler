---Document Walker for SpecCompiler.
---Provides AST traversal methods for handlers with context preservation.

local M = {}

---Extract line number from sourcepos data-pos attribute.
---Format: "start_line:start_col-end_line:end_col" (e.g., "3:1-6:1")
---@param attributes table Block attributes
---@return number line Line number (1-indexed), or 0 if not found
local function extract_line_from_sourcepos(attributes)
    if not attributes then return 0 end

    -- Try data-pos first (from sourcepos extension)
    local data_pos = attributes["data-pos"]
    if data_pos then
        local line = data_pos:match("^(%d+):")
        if line then return tonumber(line) end
    end

    -- Fallback to explicit line attribute
    local explicit_line = attributes.line
    if explicit_line then
        return tonumber(explicit_line) or 0
    end

    return 0
end

---Extract source file from data-source-file attribute (set by include expansion).
---@param attributes table Block attributes
---@return string|nil source_file Source file path, or nil if not set
local function extract_source_file(attributes)
    if not attributes then return nil end
    return attributes["data-source-file"]
end

---Create a new walker instance for a Pandoc document.
---@param doc table Pandoc document
---@param opts table Options (spec_id, source_path)
---@return table walker
function M.new(doc, opts)
    opts = opts or {}
    local self = setmetatable({
        doc = doc,
        blocks = doc.blocks or {},
        spec_id = opts.spec_id or "default",
        source_path = opts.source_path or "unknown"
    }, { __index = M })
    
    return self
end

---Walk all headers in the document.
function M:walk_headers()
    local i = 0
    local blocks = self.blocks

    return function()
        while true do
            i = i + 1
            if i > #blocks then return nil end

            local block = blocks[i]
            if block.t == "Header" then
                local attrs = block.attributes or (block.attr and block.attr.attributes) or {}
                return {
                    t = "Header",
                    level = block.level,
                    content = block.content,
                    identifier = block.identifier or (block.attr and block.attr.identifier),
                    classes = block.classes or (block.attr and block.attr.classes) or {},
                    attributes = attrs,
                    line = extract_line_from_sourcepos(attrs),
                    file = extract_source_file(attrs) or self.source_path,
                }
            end
        end
    end
end

---Walk all code blocks in the document.
function M:walk_codeblocks()
    local i = 0
    local blocks = self.blocks

    return function()
        while true do
            i = i + 1
            if i > #blocks then return nil end

            local block = blocks[i]
            if block.t == "CodeBlock" then
                local attrs = block.attributes or (block.attr and block.attr.attributes) or {}
                return {
                    t = "CodeBlock",
                    text = block.text,
                    identifier = block.identifier or (block.attr and block.attr.identifier),
                    classes = block.classes or (block.attr and block.attr.classes) or {},
                    attributes = attrs,
                    line = extract_line_from_sourcepos(attrs),
                    file = extract_source_file(attrs) or self.source_path,
                }
            end
        end
    end
end

---Walk all links and citations in the document.
---Each link/cite includes the line number from its containing block.
function M:walk_links()
    local links = {}

    for _, block in ipairs(self.blocks) do
        -- Extract line number and source file from the containing block's sourcepos
        local attrs = block.attributes or (block.attr and block.attr.attributes) or {}
        local block_line = extract_line_from_sourcepos(attrs)
        local block_file = extract_source_file(attrs) or self.source_path

        local visitor = {
            Link = function(l)
                local link_attrs = l.attributes or (l.attr and l.attr.attributes) or {}
                local link_line = extract_line_from_sourcepos(link_attrs)
                local link_file = extract_source_file(link_attrs)

                table.insert(links, {
                    t = "Link",
                    target = l.target,
                    content = l.content,
                    classes = l.classes or (l.attr and l.attr.classes) or {},
                    attributes = link_attrs,
                    file = link_file or block_file,
                    line = (link_line > 0) and link_line or block_line
                })
            end,
            Cite = function(c)
                table.insert(links, {
                    t = "Cite",
                    citations = c.citations,
                    file = block_file,
                    line = block_line
                })
            end
        }

        pandoc.walk_block(block, visitor)
    end

    local i = 0
    return function()
        i = i + 1
        return links[i]
    end
end

return M
