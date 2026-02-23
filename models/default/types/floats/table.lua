-- models/default/types/floats/table.lua
-- Handles CSV, TSV, and list-table parsing using Pandoc readers
-- Ported from v1: extensions/templates/default/types/objects/table/handler.lua

local M = {}

-- Float schema for type registration (goes into spec_float_types)
M.float = {
    id = "TABLE",
    long_name = "Table",
    description = "Tables from CSV, TSV, or list-table syntax",
    caption_format = "Table",
    counter_group = "TABLE",  -- Own counter
    aliases = { "csv", "tsv", "list-table", "listtable" }
}

-- ============================================================================
-- CSV/TSV Parsing (uses Pandoc's built-in CSV reader)
-- ============================================================================

local function parse_csv_tsv(content, log)
    -- Support file import (single line = file path)
    local lines = {}
    for line in content:gmatch('[^\r\n]+') do
        table.insert(lines, line)
    end

    if #lines == 1 then
        local potential_path = lines[1]:match('^%s*(.-)%s*$')
        local f = io.open(potential_path, 'r')
        if f then
            log.debug('Importing table from file: %s', potential_path)
            content = f:read('*all')
            f:close()
        end
    end

    -- Use Pandoc's CSV reader (handles both CSV and TSV)
    -- Note: Pandoc's CSV reader auto-detects delimiters including tabs for TSV
    local ok, doc = pcall(pandoc.read, content, 'csv')
    if not ok or not doc or not doc.blocks or #doc.blocks == 0 then
        log.debug('Failed to parse CSV content')
        return nil
    end

    log.debug('Parsed CSV table: %d blocks', #doc.blocks)
    return doc.blocks[1]  -- Return the Table block
end

-- ============================================================================
-- List-Table Parsing (parse as markdown, walk BulletList AST)
-- ============================================================================

local function parse_alignment(spec)
    if spec == 'l' then return pandoc.AlignLeft
    elseif spec == 'r' then return pandoc.AlignRight
    elseif spec == 'c' then return pandoc.AlignCenter
    else return pandoc.AlignDefault
    end
end

local function parse_metadata(content)
    local opts = { header_rows = 1, header_cols = 0, widths = nil, aligns = nil }
    for line in content:gmatch('[^\r\n]+') do
        local key, value = line:match('^>%s*([%w%-]+):%s*(.+)$')
        if key then
            if key == 'header-rows' then opts.header_rows = tonumber(value) or 1
            elseif key == 'header-cols' then opts.header_cols = tonumber(value) or 0
            elseif key == 'widths' then opts.widths = value:gsub('%s', '')
            elseif key == 'aligns' then opts.aligns = value:gsub('%s', '')
            end
        end
    end
    return opts
end

local function parse_list_table(content, log)
    -- Strip all metadata lines for parsing (metadata lines start with >)
    local clean_content = content:gsub('^(>.-\n)+', '')

    -- Parse as markdown to get BulletList AST
    local ok, doc = pcall(pandoc.read, clean_content, 'markdown')
    if not ok or not doc or not doc.blocks then
        log.debug('Failed to parse list-table markdown')
        return nil
    end

    -- Find the BulletList
    local bullet_list = nil
    for _, b in ipairs(doc.blocks) do
        if b.t == 'BulletList' then
            bullet_list = b
            break
        end
    end

    if not bullet_list then
        log.debug('No bullet list found in list-table')
        return nil
    end

    -- Extract rows from nested BulletLists
    local rows = {}
    for _, row_item in ipairs(bullet_list.content) do
        for _, block_el in ipairs(row_item) do
            if block_el.t == 'BulletList' then
                local cells = {}
                for _, cell_item in ipairs(block_el.content) do
                    table.insert(cells, cell_item)
                end
                table.insert(rows, cells)
            end
        end
    end

    if #rows == 0 then
        log.debug('No rows extracted from list-table')
        return nil
    end

    -- Parse metadata for header-rows, widths, aligns
    local opts = parse_metadata(content)

    -- Determine dimensions
    local num_cols = 0
    for _, row in ipairs(rows) do
        num_cols = math.max(num_cols, #row)
    end

    -- Build alignments
    local aligns = {}
    if opts.aligns then
        for spec in opts.aligns:gmatch('[^,]+') do
            table.insert(aligns, parse_alignment(spec:gsub('%s', '')))
        end
    end
    while #aligns < num_cols do
        table.insert(aligns, pandoc.AlignDefault)
    end

    -- Build widths
    local widths = {}
    if opts.widths then
        local raw_widths = {}
        local total = 0
        for w in opts.widths:gmatch('[^,]+') do
            local num = tonumber(w:gsub('%s', '')) or 0
            table.insert(raw_widths, num)
            total = total + num
        end
        for _, wv in ipairs(raw_widths) do
            table.insert(widths, total > 0 and wv / total or 0)
        end
    end
    while #widths < num_cols do
        table.insert(widths, 0)
    end

    -- Split header and body rows
    local header_row = {}
    local body_rows = {}

    if opts.header_rows > 0 and #rows > 0 then
        header_row = rows[1]
        for i = 2, #rows do
            table.insert(body_rows, rows[i])
        end
    else
        body_rows = rows
    end

    -- Build SimpleTable and convert to Table
    local simple_table = pandoc.SimpleTable({}, aligns, widths, header_row, body_rows)
    local table_block = pandoc.utils.from_simple_table(simple_table)

    log.debug('Parsed list-table: %d rows, %d cols', #rows, num_cols)
    return table_block
end

-- ============================================================================
-- Transform Interface (called by float_resolver)
-- ============================================================================

---Transform raw content to Pandoc AST
---@param raw_content string Raw code block content
---@param type_ref string Original type (CSV, TSV, LIST_TABLE, TABLE)
---@param log table|nil Logger (optional)
---@return pandoc.Block|nil Transformed AST block
function M.transform(raw_content, type_ref, log)
    log = log or { debug = function() end, error = function() end }

    -- Detect list-table by content patterns:
    -- 1. Starts with metadata line (> key: value)
    -- 2. Has bullet list structure (* - cell)
    local is_list_table = raw_content:match("^>%s*[%w%-]+:") or
                          raw_content:match("^%*%s+%-") or
                          raw_content:match("\n%*%s+%-")

    if is_list_table then
        log.debug("Detected list-table from content pattern")
        return parse_list_table(raw_content, log)
    else
        log.debug("Using CSV parser for table content")
        return parse_csv_tsv(raw_content, log)
    end
end

-- ============================================================================
-- Handler (EMIT phase)
-- ============================================================================

M.handler = {
    name = "table_handler",
    prerequisites = {},

    ---EMIT: Convert resolved_ast to Pandoc elements.
    ---@param block table Pandoc CodeBlock element
    ---@param ctx table Context with data, spec_id, log, preset
    ---@param float table Float record from database
    ---@param resolved string resolved_ast JSON string (Pandoc Table)
    ---@return table|nil Pandoc element or nil
    on_render_CodeBlock = function(block, ctx, float, resolved)
        if not resolved or not pandoc then return nil end

        -- resolved_ast is JSON-encoded Pandoc Table
        local table_ast = pandoc.json.decode(resolved)
        if not table_ast or table_ast.t ~= "Table" then
            return nil
        end

        -- Wrap Pandoc Table in semantic Div for filter processing
        -- Filters will convert to format-specific output (OOXML for DOCX, HTML for web)
        return pandoc.Div(
            {table_ast},
            pandoc.Attr("", {"speccompiler-table"}, {
                ["float-type"] = float.type_ref or "TABLE",
                ["identifier"] = float.anchor or float.label or "",
            })
        )
    end
}

return M
