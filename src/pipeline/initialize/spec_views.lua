---Spec Views Handler for SpecCompiler.
---Handles view initialization from code blocks and inline syntax.
---
---View types are defined in models/{model}/types/views/{view_name}.lua.
---Each view type has its own inline_prefix (e.g., toc:, lof:, abbrev:).
---
---@module spec_views
local Queries = require("db.queries")
local hash_utils = require("infra.hash_utils")

local M = {
    name = "spec_views",
    prerequisites = {"spec_objects", "spec_floats_initialize"}  -- May reference spec_objects and floats
}

-- Cache for prefix-to-type lookup and dedicated handler types (queried from DB)
local prefix_to_type_cache = nil
local dedicated_prefixes_cache = nil

---Build cache of inline_prefix -> type_id mapping.
---@param data DataManager
local function build_prefix_cache(data)
    if prefix_to_type_cache then
        return
    end

    prefix_to_type_cache = {}
    dedicated_prefixes_cache = {}

    local types = data:query_all(Queries.content.select_view_types_with_prefix)

    for _, t in ipairs(types or {}) do
        local prefix = t.inline_prefix:upper()
        prefix_to_type_cache[prefix] = t.identifier

        -- Track prefixes that have dedicated handlers
        if t.needs_external_render == 1 then
            dedicated_prefixes_cache[prefix] = true
        end

        -- Also register aliases
        if t.aliases and t.aliases ~= "" then
            for alias in t.aliases:gmatch("[^,]+") do
                alias = alias:match("^%s*(.-)%s*$"):upper()  -- Trim and uppercase
                if alias ~= "" then
                    prefix_to_type_cache[alias] = t.identifier
                    if t.needs_external_render == 1 then
                        dedicated_prefixes_cache[alias] = true
                    end
                end
            end
        end
    end
end

---Check if a prefix has a dedicated handler (needs_external_render = 1).
---@param data DataManager
---@param prefix string Inline prefix (e.g., "MATH", "EQ")
---@return boolean has_dedicated True if type has dedicated handler
local function has_dedicated_handler(data, prefix)
    build_prefix_cache(data)
    return dedicated_prefixes_cache[prefix:upper()] or false
end

---Get the actual view type ID for a prefix.
---@param data DataManager
---@param prefix string Inline prefix (e.g., "MATH", "EQ")
---@return string|nil type_id Actual type identifier (e.g., "MATH_INLINE")
local function get_type_for_prefix(data, prefix)
    build_prefix_cache(data)
    return prefix_to_type_cache[prefix:upper()]
end

---Clear module-level caches (required for re-entrant engine.run_project calls).
function M.clear_cache()
    prefix_to_type_cache = nil
    dedicated_prefixes_cache = nil
end

---Parse inline view syntax from code elements
---Supports: `toc:`, `lof:`, `symbol: Class.method`, `math: expr`, `abbrev: Name (ABBR)`
---Also supports views with no content: `traceability_matrix:`
---@param text string Code text
---@return string|nil view_type, string|nil content
local function parse_inline_view(text)
    if not text then return nil, nil end

    -- Pattern: type: content (type must be alphanumeric/underscore, content can be empty)
    local type_part, content = text:match("^([%w_]+):%s*(.*)$")
    if type_part and #type_part > 0 then
        -- Use uppercase prefix as view_type (model-agnostic)
        return type_part:upper(), content
    end

    return nil, nil
end

---@param data DataManager
---@param contexts Context[]
---@param diagnostics Diagnostics
function M.on_initialize(data, contexts, diagnostics)
    data:begin_transaction()
    for _, ctx in ipairs(contexts) do
        local doc = ctx.doc
        local file_seq = 0
        local spec_id = ctx.spec_id or "default"

        -- Skip if no document (cached builds create project context without doc)
        if not doc then goto continue end

        -- Clear old views for this specification before inserting new ones.
        -- This prevents orphaned entries when content changes or is deleted.
        data:execute(Queries.content.delete_views_by_spec, { spec_id = spec_id })

        -- NOTE: Block views removed - views are inline-only (`type: content` in backticks)
        -- Code blocks with classes (e.g., ```bash) are either floats or plain code for highlighting

        -- Extract inline views from Code elements (backticks)
        -- Skip types that have dedicated handlers (needs_external_render = 1 in spec_view_types)
        -- Those types have their own on_initialize handlers that store views

        if doc.blocks and pandoc then
            local inline_views = {}

            local visitor = {
                Code = function(c)
                    local prefix, content = parse_inline_view(c.text)
                    -- Skip if this prefix has a dedicated handler (e.g., math: -> MATH_INLINE)
                    if prefix and not has_dedicated_handler(data, prefix) then
                        -- Only accept registered view types - ignore unknown prefixes
                        local view_type = get_type_for_prefix(data, prefix)
                        if view_type then
                            table.insert(inline_views, {
                                view_type = view_type,
                                content = content,
                                text = c.text
                            })
                        end
                    end
                end
            }

            for _, block in ipairs(doc.blocks) do
                pandoc.walk_block(block, visitor)
            end

            for _, view in ipairs(inline_views) do
                file_seq = file_seq + 1
                local content_key = spec_id .. ":" .. file_seq .. ":" .. view.text
                local content_sha = hash_utils.sha1(content_key)

                data:execute(Queries.content.insert_view, {
                    content_sha = content_sha,
                    specification_ref = spec_id,
                    view_type_ref = view.view_type,
                    from_file = ctx.source_path or "unknown",
                    file_seq = file_seq,
                    start_line = nil,  -- Inline views don't have line tracking
                    raw_ast = view.content
                })
            end
        end
        ::continue::
    end
    data:commit()
end

-- NOTE: on_transform() and on_render_Code() are not implemented here.
-- View resolution is handled by individual view type modules
-- (models/{model}/types/views/{view_name}.lua) which implement their own
-- on_initialize, on_transform, and on_render_Code handlers.
-- These are registered via the type_loader and run in the pipeline.

return M
