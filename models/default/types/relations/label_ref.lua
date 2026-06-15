---Base relation type for label-based cross-references (# selector).
---Owns scoped label resolution (local -> spec -> global). Concrete types use extends = "LABEL_REF".
---
---@module label_ref
local Queries = require("db.queries")

---Parse target_text for explicit scope (ScopedRef: scope:prefix:label).
---@param target_text string The stored target text
---@return string|nil label The label to match against
---@return string|nil scope The explicit scope PID, or nil
local function parse_scoped_target(target_text)
    if not target_text then return nil, nil end
    local scope, prefix, label_part = target_text:match("^([^:]+):([^:]+):(.+)$")
    if scope and prefix and label_part then
        return prefix .. ":" .. label_part, scope
    end
    return target_text, nil
end

---Resolve a label reference with scoped resolution.
---Uses 3-step closest-to-global resolution with ambiguity detection.
---For explicit scope (ScopedRef), uses strict resolution with no fallback.
---@param dctx table frozen DATA ctx (dctx.data, dctx.spec_id,
---       dctx.subject.target_text, dctx.subject.source_object_id)
---@return table resolution { target = {id,type_ref,kind} | nil, ambiguous = boolean }
local function resolve(dctx)
    local data = dctx.data
    local spec_id = dctx.spec_id
    local target_text = dctx.subject.target_text
    local source_object_id = dctx.subject.source_object_id

    local raw_label = target_text:match("^#?(.+)$")
    if not raw_label or raw_label == "" then return { target = nil, ambiguous = false } end

    local label, explicit_scope = parse_scoped_target(raw_label)
    if not label then return { target = nil, ambiguous = false } end

    if explicit_scope then
        -- object_by_pid_in_spec/_cross_doc return {id, type_ref}; only id is used
        -- here (bind name is :spec, not :spec_id)
        local scope_obj = data:query_one(Queries.resolution.object_by_pid_in_spec,
            { spec = spec_id, pid = explicit_scope })

        if not scope_obj then
            scope_obj = data:query_one(Queries.resolution.object_by_pid_cross_doc,
                { pid = explicit_scope })
        end

        if scope_obj then
            local result = data:query_one(Queries.resolution.float_by_label_in_scope_typed,
                { label = label, scope_id = scope_obj.id })
            return { target = result, ambiguous = false }
        end
        return { target = nil, ambiguous = false }
    end

    if source_object_id then
        local results = data:query_all(Queries.resolution.float_by_label_in_scope_typed,
            { label = label, scope_id = source_object_id })

        if #results == 1 then
            return { target = results[1], ambiguous = false }
        elseif #results > 1 then
            return { target = results[1], ambiguous = true }
        end
    end

    local results = data:query_all(Queries.resolution.unified_by_label_in_spec,
        { spec = spec_id, label = label })

    if #results == 1 then
        return { target = results[1], ambiguous = false }
    elseif #results > 1 then
        return { target = results[1], ambiguous = true }
    end

    results = data:query_all(Queries.resolution.unified_by_label_global,
        { label = label })

    if #results == 1 then
        return { target = results[1], ambiguous = false }
    elseif #results > 1 then
        return { target = results[1], ambiguous = true }
    end

    return { target = nil, ambiguous = false }
end

return {
    kind = "relation",
    schema = {
        id = "LABEL_REF",
        long_name = "Label Reference",
        description = "Base relation type for label-based cross-references (# selector)",
        link_selector = "#",
    },
    hooks = {
        ---Default display rule for label-based refs. Sections render by title (the
        ---prose convention "see Chapter 3 Introduction"); everything else renders by
        ---PID (for objects) or "<caption> <number>" (for floats). Concrete subtypes
        ---(XREF_SEC, XREF_FIGURE, ...) can override by defining their own
        ---render_link; those without one inherit this behaviour via the host's
        ---extends-chain hook resolution (get_hook_inherited).
        render_link = function(ctx)
            local target = ctx.subject.target
            if target.kind == "float" then
                local caption = target.caption or "Item"
                return caption .. " " .. (target.number or "?")
            end
            if target.type_ref == "SECTION" and target.title and target.title ~= "" then
                return target.title
            end
            return target.pid
        end,
        resolve = resolve,
    },
}
