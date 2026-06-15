---Relation Link Rewriter Handler for SpecCompiler.
---Pipeline handler for TRANSFORM phase.
---
---Rewrites links in stored AST using resolved relation data from ANALYZE phase.
---Uses the relation lookup (keyed by source_object_id + selector + target_text)
---to correctly rewrite scoped references to the right target anchor and display text.
---
---@module relation_link_rewriter
local Queries = require("db.queries")
local ast_utils = require("pipeline.shared.ast_utils")
local registry = require("contract.registry")
local hook_ctx = require("pipeline.shared.hook_ctx")

local M = {
    name = "relation_link_rewriter",
    prerequisites = { "float_numbering" }
}

---Preload the float type alias map: canonical_prefix -> {all_aliases}.
---Bridges the gap between original link text (e.g., "plantuml:label") and
---normalized target_text (e.g., "puml:label") in the database.
---@param data DataManager
---@return table prefix_aliases Map keyed by canonical (first) alias
local function load_prefix_aliases(data)
    local prefix_aliases = {}
    local float_types = data:query_all("SELECT identifier, aliases FROM spec_float_types")
    for _, ft in ipairs(float_types or {}) do
        if ft.aliases then
            local aliases = {}
            for alias in ft.aliases:gmatch("[^,]+") do
                aliases[#aliases + 1] = alias:lower()
            end
            -- Also include the lowercase type identifier (e.g., "chart" for CHART)
            local lower_id = ft.identifier and ft.identifier:lower() or ""
            local has_id = false
            for _, a in ipairs(aliases) do
                if a == lower_id then has_id = true; break end
            end
            if not has_id and lower_id ~= "" then
                aliases[#aliases + 1] = lower_id
            end
            if #aliases > 0 then
                prefix_aliases[aliases[1]] = aliases
            end
        end
    end
    return prefix_aliases
end

---Add lookup entries for all alias variants of a float relation's type prefix.
---The INITIALIZE phase normalizes "plantuml:label" -> "puml:label" but the AST
---link content retains the original prefix.
---@param lookup table The relation lookup being built (mutated)
---@param prefix_aliases table Map from load_prefix_aliases
---@param r table Resolved relation row
---@param entry table Lookup entry for this relation
local function add_alias_keys(lookup, prefix_aliases, r, entry)
    local canonical_prefix, label_part = r.target_text:match("^([^:]+):(.+)$")
    if not (canonical_prefix and label_part) then return end
    local aliases = prefix_aliases[canonical_prefix:lower()]
    if not aliases then return end
    local base_key = tostring(r.source_object_id) .. "|" .. r.link_selector .. "|"
    for _, alias in ipairs(aliases) do
        local alt_key = base_key .. alias .. ":" .. label_part
        if not lookup[alt_key] then
            lookup[alt_key] = entry
        end
    end
end

---Build relation-aware anchor lookup for link rewriting.
---Uses resolved spec_relations to map (source_object_id, selector, target_text)
---to the correct target anchor and display text. This respects scoped resolution:
---each source object's links resolve to the targets determined in ANALYZE phase.
---@param data DataManager
---@param spec_id string Specification identifier
---@return table lookup Map of "source_id|selector|target_text" -> {spec, anchor, display_text}
local function build_relation_lookup(data, spec_id, pctx, diagnostics)
    local lookup = {}

    -- Relation link-display dispatch reads the host's hook index:
    -- get_hook_inherited walks the extends chain (LABEL_REF/PID_REF roots).
    local host = registry.current()

    local prefix_aliases = load_prefix_aliases(data)

    -- Query all resolved relations with target details
    local relations = data:query_all(Queries.resolution.select_resolved_relations_with_targets, { spec_id = spec_id })

    for _, r in ipairs(relations or {}) do
        -- Skip structural relations (no link in AST to rewrite)
        if not r.target_text then goto continue_relation end

        local key = tostring(r.source_object_id) .. "|" .. r.link_selector .. "|" .. r.target_text

        local on_link = host and host:get_hook_inherited("relation", r.relation_type_ref, "render_link")

        if r.object_pid then
            -- Local display text: delegate to the relation type's
            -- render_link hook. Every relation type extends LABEL_REF or PID_REF,
            -- both of which register a default hook, so the lookup always
            -- resolves something. Cross-document spec prefix is added below.
            local local_display
            if on_link then
                local_display = on_link(hook_ctx.build(pctx, data, diagnostics, {
                    target = {
                        pid = r.object_pid,
                        title = r.object_title_text or "",
                        spec = r.object_spec,
                        type_ref = r.object_type_ref,
                        kind = "object",
                    },
                    source_object_id = r.source_object_id,
                    is_cross_doc = r.object_spec ~= spec_id,
                    selector = r.link_selector,
                }, "render_link", spec_id))
            end
            -- Safety net: if a relation type lacks any render_link hook up its
            -- extends chain (e.g. a custom type that sets extends = nil),
            -- fall back to the raw PID so we never emit an empty link.
            if not local_display then
                local_display = r.object_pid
            end

            local display_text
            if r.object_spec ~= spec_id then
                display_text = r.object_spec .. ": " .. local_display
            else
                display_text = local_display
            end

            lookup[key] = {
                spec = r.object_spec,
                anchor = r.object_pid,
                display_text = display_text
            }
        elseif r.float_anchor or r.float_label then
            local anchor = r.float_anchor or r.float_label
            local local_display
            if on_link then
                local_display = on_link(hook_ctx.build(pctx, data, diagnostics, {
                    target = {
                        label = r.float_label,
                        anchor = r.float_anchor,
                        number = r.float_number,
                        caption = r.caption_format,
                        spec = r.float_spec,
                        kind = "float",
                    },
                    source_object_id = r.source_object_id,
                    is_cross_doc = r.float_spec ~= spec_id,
                    selector = r.link_selector,
                }, "render_link", spec_id))
            end
            -- Safety net: only reached when a float relation type's extends
            -- chain has no render_link hook at all. The label alone beats
            -- emitting nothing.
            if not local_display then
                local_display = r.float_label or r.float_anchor or ""
            end
            local entry = {
                spec = r.float_spec,
                anchor = anchor,
                display_text = local_display
            }
            lookup[key] = entry

            add_alias_keys(lookup, prefix_aliases, r, entry)
        end
        ::continue_relation::
    end
    return lookup
end

---Build link target from resolved anchor.
---Uses internal link (#anchor) for same-document, external ({spec}.ext#anchor) for cross-document.
---@param resolved table { spec, anchor, display_text }
---@param current_spec string Current specification ID
---@return string Link target
local function build_link_target(resolved, current_spec)
    if resolved.spec == current_spec then
        -- Same document: use internal anchor
        return "#" .. resolved.anchor
    else
        -- Cross-document: use external link with placeholder extension
        return resolved.spec .. ".ext#" .. resolved.anchor
    end
end

---Rewrite links in stored ASTs using resolved relation data.
---Uses the relation lookup (keyed by source id + selector + target_text) to
---rewrite scoped references to the right target anchor and display text. The
---same walk serves spec_objects (source id = row id) and spec_attribute_values
---(source id = owner_object_id); only the queries and id field differ.
---@param data DataManager
---@param spec_id string Specification identifier
---@param relation_lookup table Map of "source_id|selector|target_text" -> {spec, anchor, display_text}
---@param select_query string Query returning rows with {id, ast, [source_id_field]}
---@param source_id_field string Row field holding the link source object id
---@param update_query string UPDATE statement taking {id, ast}
local function rewrite_links(data, spec_id, relation_lookup, select_query, source_id_field, update_query)
    if not pandoc then return end

    local rows = data:query_all(select_query, { spec_id = spec_id })

    for _, row in ipairs(rows or {}) do
        local decoded = pandoc.json.decode(row.ast)
        if decoded then
            local blocks = ast_utils.extract_blocks(decoded)

            if blocks and #blocks > 0 then
                -- Wrap in temp doc for walking
                local temp_doc = pandoc.Pandoc(blocks)

                local modified = false

                -- Create link rewriting filter using relation-aware lookup
                local link_filter = {
                    Link = function(link)
                        local target = link.target or ""
                        local content_text = pandoc.utils.stringify(link.content)

                        if target:match("^[@#]") then
                            -- Look up by (source id, selector, target_text)
                            local key = tostring(row[source_id_field]) .. "|" .. target .. "|" .. content_text
                            local resolved = relation_lookup[key]

                            if not resolved then
                                -- Language-qualified prefix ("src.sql:label"):
                                -- INITIALIZE normalizes it to the base alias
                                -- ("src:label"), which add_alias_keys registered.
                                local base_text = content_text:gsub("^([^:%.]+)%.[^:]*:", "%1:", 1)
                                if base_text ~= content_text then
                                    resolved = relation_lookup[tostring(row[source_id_field]) .. "|" .. target .. "|" .. base_text]
                                end
                            end

                            if resolved then
                                link.target = build_link_target(resolved, spec_id)
                                if resolved.display_text then
                                    link.content = { pandoc.Str(resolved.display_text) }
                                end
                                modified = true
                                return link
                            elseif target == "@" or target == "#" then
                                -- Fallback only for base selectors;
                                -- extended selectors left for type-specific handlers
                                if target == "#" then
                                    local label = content_text:match(":(.+)$") or content_text
                                    link.target = "#" .. label
                                else
                                    link.target = "#" .. content_text
                                end
                                modified = true
                                return link
                            end
                        end

                        return link
                    end
                }

                -- Apply filter
                temp_doc = temp_doc:walk(link_filter)

                -- If modified, update the stored AST
                if modified then
                    local new_ast = pandoc.json.encode(temp_doc.blocks)
                    data:execute(update_query, { id = row.id, ast = new_ast })
                end
            end
        end
    end
end

---Rewrite links in stored AST using resolved anchors.
---Resolution is handled by relation_analyzer in ANALYZE phase.
function M.on_transform(data, contexts, diagnostics)
    data:begin_transaction()
    for _, ctx in ipairs(contexts) do
        local spec_id = ctx.spec_id or "default"

        local relation_lookup = build_relation_lookup(data, spec_id, ctx, diagnostics)
        rewrite_links(data, spec_id, relation_lookup,
            Queries.content.objects_with_ast, "id", Queries.content.update_object_ast)
        rewrite_links(data, spec_id, relation_lookup,
            Queries.content.attributes_with_ast, "owner_object_id", Queries.content.update_attribute_ast)
    end
    data:commit()
end

return M
