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

local M = {
    name = "relation_link_rewriter",
    prerequisites = { "float_numbering" }
}

---Build relation-aware anchor lookup for link rewriting.
---Uses resolved spec_relations to map (source_object_id, selector, target_text)
---to the correct target anchor and display text. This respects scoped resolution:
---each source object's links resolve to the targets determined in ANALYZE phase.
---@param data DataManager
---@param spec_id string Specification identifier
---@return table lookup Map of "source_id|selector|target_text" -> {spec, anchor, display_text}
local function build_relation_lookup(data, spec_id)
    local lookup = {}

    -- Preload float type alias map: canonical_prefix -> {all_aliases}
    -- This bridges the gap between original link text (e.g., "plantuml:label")
    -- and normalized target_text (e.g., "puml:label") in the database.
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

    -- Query all resolved relations with target details
    local relations = data:query_all(Queries.resolution.select_resolved_relations_with_targets, { spec_id = spec_id })

    for _, r in ipairs(relations or {}) do
        local key = tostring(r.source_object_id) .. "|" .. r.link_selector .. "|" .. r.target_text

        if r.object_pid then
            local display_text
            -- Sections: show title instead of PID for friendly display
            if r.object_type_ref == "SECTION" and r.object_title_text and r.object_title_text ~= "" then
                if r.object_spec ~= spec_id then
                    -- Cross-document: prefix with spec identifier
                    display_text = r.object_spec .. ": " .. r.object_title_text
                else
                    -- Same document: title only
                    display_text = r.object_title_text
                end
            else
                -- Non-section objects: PID is the meaningful identifier
                display_text = r.object_pid
            end
            lookup[key] = {
                spec = r.object_spec,
                anchor = r.object_pid,
                display_text = display_text
            }
        elseif r.float_anchor or r.float_label then
            local anchor = r.float_anchor or r.float_label
            local caption_format = r.caption_format or "Item"
            local display_text = caption_format .. " " .. (r.float_number or "?")
            local entry = {
                spec = r.float_spec,
                anchor = anchor,
                display_text = display_text
            }
            lookup[key] = entry

            -- Add entries for all alias variants of the float type prefix.
            -- The INITIALIZE phase normalizes "plantuml:label" → "puml:label"
            -- but the AST link content retains the original prefix.
            local canonical_prefix, label_part = r.target_text:match("^([^:]+):(.+)$")
            if canonical_prefix and label_part then
                local aliases = prefix_aliases[canonical_prefix:lower()]
                if aliases then
                    local base_key = tostring(r.source_object_id) .. "|" .. r.link_selector .. "|"
                    for _, alias in ipairs(aliases) do
                        local alt_key = base_key .. alias .. ":" .. label_part
                        if not lookup[alt_key] then
                            lookup[alt_key] = entry
                        end
                    end
                end
            end
        end
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

---Rewrite links in stored AST using resolved relation data.
---Uses the relation lookup (keyed by source_object_id + selector + target_text)
---to correctly rewrite scoped references to the right target anchor and display text.
---@param data DataManager
---@param spec_id string Specification identifier
---@param relation_lookup table Map of "source_id|selector|target_text" -> {spec, anchor, display_text}
local function rewrite_links_in_ir(data, spec_id, relation_lookup)
    if not pandoc then return end

    -- Get all spec_objects with AST
    local objects = data:query_all(Queries.content.objects_with_ast, { spec_id = spec_id })

    for _, obj in ipairs(objects or {}) do
        local decoded = pandoc.json.decode(obj.ast)
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
                            -- Look up by (source_object_id, selector, target_text)
                            local key = tostring(obj.id) .. "|" .. target .. "|" .. content_text
                            local resolved = relation_lookup[key]

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
                    data:execute(Queries.content.update_object_ast, { id = obj.id, ast = new_ast })
                end
            end
        end
    end
end

---Rewrite links in attribute ASTs using resolved relation data.
---Mirrors rewrite_links_in_ir but for spec_attribute_values instead of spec_objects.
---Attribute links (e.g., traceability: [SF-AUTH](@)) are stored in spec_attribute_values.ast.
---@param data DataManager
---@param spec_id string Specification identifier
---@param relation_lookup table Map of "source_id|selector|target_text" -> {spec, anchor, display_text}
local function rewrite_links_in_attribute_ast(data, spec_id, relation_lookup)
    if not pandoc then return end

    local attrs = data:query_all(Queries.content.attributes_with_ast, { spec_id = spec_id })

    for _, attr in ipairs(attrs or {}) do
        local decoded = pandoc.json.decode(attr.ast)
        if decoded then
            local blocks = ast_utils.extract_blocks(decoded)

            if blocks and #blocks > 0 then
                local temp_doc = pandoc.Pandoc(blocks)
                local modified = false

                local link_filter = {
                    Link = function(link)
                        local target = link.target or ""
                        local content_text = pandoc.utils.stringify(link.content)

                        if target:match("^[@#]") then
                            -- owner_object_id is the source for attribute links
                            local key = tostring(attr.owner_object_id) .. "|" .. target .. "|" .. content_text
                            local resolved = relation_lookup[key]

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

                temp_doc = temp_doc:walk(link_filter)

                if modified then
                    local new_ast = pandoc.json.encode(temp_doc.blocks)
                    data:execute(Queries.content.update_attribute_ast, { id = attr.id, ast = new_ast })
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

        local relation_lookup = build_relation_lookup(data, spec_id)
        rewrite_links_in_ir(data, spec_id, relation_lookup)
        rewrite_links_in_attribute_ast(data, spec_id, relation_lookup)
    end
    data:commit()
end

return M
