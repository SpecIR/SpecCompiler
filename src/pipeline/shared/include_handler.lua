---Include Handler for SpecCompiler.
---Expands include directives by embedding file content before pipeline.

-- Maximum depth for recursive include expansion (prevents infinite loops)
local MAX_INCLUDE_DEPTH = 100
local include_utils = require("pipeline.shared.include_utils")
local sourcepos_compat = require("pipeline.shared.sourcepos_compat")
local hash_utils = require("infra.hash_utils")

local M = {}

---Expand all include directives in a document.
---This should be called BEFORE the pipeline runs.
---Optimized: Single-pass expansion since recursive calls handle nested includes.
---@param doc pandoc.Pandoc The document to process
---@param base_dir string Directory of the source file
---@param root_path string Path of the root document (for build graph)
---@param processed table Set of already-processed files (for cycle detection)
---@param log table Logger
---@param depth number|nil Current recursion depth (for safety)
---@return pandoc.Pandoc Expanded document
---@return table includes Array of {path, sha1} for build graph
function M.expand_includes(doc, base_dir, root_path, processed, log, depth)
    processed = processed or {}
    depth = depth or 0
    local includes = {}

    -- Safety check for excessive recursion
    if depth > MAX_INCLUDE_DEPTH then
        log.warn("Max include depth reached at %d, possible deep nesting", depth)
        return doc, includes
    end

    -- Single pass: recursive calls handle nested includes in each file
    local new_blocks = {}
    local block_idx = 0

    -- Heading level in effect at the include point (LLR-071). Tracked from
    -- this document's own blocks only, so sibling includes share the same
    -- context regardless of what the included files contain. A `----`
    -- thematic break closes the current section, popping one level.
    local heading_level = 0

    for _, block in ipairs(doc.blocks) do
        if include_utils.is_include_block(block) then
            for _, rel_path in ipairs(include_utils.iter_include_paths(block.text)) do
                local abs_path = include_utils.resolve_path(base_dir, rel_path)

                -- Cycle detection
                if processed[abs_path] then
                    log.error("Circular include detected: %s", abs_path)
                    error("Circular include: " .. abs_path)
                end

                -- Read included file
                local content = include_utils.read_file(abs_path)
                if not content then
                    log.error("Include file not found: %s (from %s)", abs_path, root_path)
                    error("Include file not found: " .. abs_path)
                end

                -- Parse as Pandoc markdown (same format as main document)
                local inc_doc = pandoc.read(content, "commonmark_x+sourcepos")

                -- Strip inline tracking spans for Pandoc version independence
                sourcepos_compat.normalize(inc_doc)

                -- Annotate blocks with source file for diagnostics
                include_utils.annotate_source_file(inc_doc.blocks, abs_path)

                -- Track for build graph
                local sha1 = hash_utils.sha1(content)
                includes[#includes + 1] = { path = abs_path, sha1 = sha1 }

                -- Mark as processed
                processed[abs_path] = true

                log.debug("Including: %s", abs_path)

                -- Recursively expand includes in included content
                local inc_dir = include_utils.dirname(abs_path)
                local expanded, sub_includes = M.expand_includes(
                    inc_doc, inc_dir, root_path, processed, log, depth + 1
                )

                -- Add sub-includes to our list
                for i = 1, #sub_includes do
                    includes[#includes + 1] = sub_includes[i]
                end

                -- Place the included document's shallowest heading one level
                -- below the heading in effect at the include point. Computing
                -- the offset relative to the included document's own root
                -- supports both standalone documents starting at `#` and
                -- legacy fragments whose root is authored at `##` or deeper.
                -- Relative depths (including malformed gaps) are preserved.
                -- Nested includes were already adjusted by the recursive call,
                -- so the outer adjustment composes over the expanded tree.
                local min_heading_level = nil
                for i = 1, #expanded.blocks do
                    local inc_block = expanded.blocks[i]
                    if inc_block.t == "Header"
                            and (not min_heading_level or inc_block.level < min_heading_level) then
                        min_heading_level = inc_block.level
                    end
                end

                local level_shift = 0
                if min_heading_level and heading_level > 0 then
                    level_shift = (heading_level + 1) - min_heading_level
                end

                -- Pandoc Header levels are positive integers and may exceed
                -- Markdown's six ATX source levels after include shifts. Keep
                -- those computed levels intact; writers decide how to render
                -- depths beyond their format's native heading range.
                if level_shift ~= 0 then
                    for i = 1, #expanded.blocks do
                        local inc_block = expanded.blocks[i]
                        if inc_block.t == "Header" then
                            local new_level = inc_block.level + level_shift
                            inc_block.level = new_level
                        end
                    end
                end

                -- Add expanded blocks using direct index assignment
                for i = 1, #expanded.blocks do
                    block_idx = block_idx + 1
                    new_blocks[block_idx] = expanded.blocks[i]
                end
            end
        else
            if block.t == "Header" then
                heading_level = block.level
            elseif include_utils.is_thematic_break(block) then
                heading_level = math.max(heading_level - 1, 0)
            end

            -- Direct index assignment instead of table.insert
            block_idx = block_idx + 1
            new_blocks[block_idx] = block
        end
    end

    doc.blocks = new_blocks
    return doc, includes
end

return M
