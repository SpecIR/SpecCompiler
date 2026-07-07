---Relation Analyzer Handler for SpecCompiler.
---Pipeline handler for RESOLVE phase.
---
---Type-driven relation analysis: filter, resolve, score, pick.
---
---For each unresolved relation:
---  1. Filter: find relation types whose constraints are compatible
---  2. Resolve: call the resolver (determined by extends chain) to find the target
---  3. Score: count matching non-NULL constraints across all 4 dimensions
---  4. Pick: highest specificity wins; ties mark the relation ambiguous
---
---@module relation_resolver
local logger = require("infra.logger")
local Queries = require("db.queries")
local cache_registry = require("pipeline.shared.cache_registry")
local hook_ctx = require("pipeline.shared.hook_ctx")

local M = {
    name = "relation_resolver",
    prerequisites = {"pid_generator"}
}

-- Cache for inference rules (loaded from database)
local inference_rules_cache = nil

-- Cache for resolver root map (type_id → root_type_id)
local resolver_root_cache = nil

-- Cache for object-type ancestry map (type_id → set of {self + ancestors})
local object_ancestry_cache = nil

---Clear module-level caches (required for re-entrant engine.run_project calls).
function M.clear_cache()
    inference_rules_cache = nil
    resolver_root_cache = nil
    object_ancestry_cache = nil
end
cache_registry.register(M.clear_cache)

-- ============================================================================
-- Inference Rules
-- ============================================================================

---Load relation inference rules from the database.
---Each rule defines a constraint pattern: {selector, source, attr, target}.
---NULL constraints act as wildcards (match anything but don't add specificity).
---@param data DataManager
---@return table rules Array of {source, target, attr, rel_type, selector}
local function load_inference_rules(data)
    if inference_rules_cache then
        return inference_rules_cache
    end

    inference_rules_cache = data:query_all(Queries.resolution.inference_rules) or {}
    return inference_rules_cache
end

-- ============================================================================
-- Resolver Root Map
-- ============================================================================

---Compute the resolver root for every relation type by walking the extends chain.
---The root is the topmost ancestor (where extends IS NULL). Types whose root has
---a registered resolver can participate in resolution.
---@param data DataManager
---@return table map type_id → root_type_id
local function compute_resolver_root_map(data)
    if resolver_root_cache then
        return resolver_root_cache
    end

    local types = data:query_all([[
        SELECT identifier, extends FROM spec_relation_types
    ]], {})

    -- Build parent map
    local parent_of = {}
    for _, t in ipairs(types or {}) do
        parent_of[t.identifier] = t.extends
    end

    -- Walk to root for each type
    local roots = {}
    for _, t in ipairs(types or {}) do
        local current = t.identifier
        local visited = {}
        while current do
            if visited[current] then break end  -- cycle guard
            visited[current] = true
            if not parent_of[current] then
                roots[t.identifier] = current
                break
            end
            current = parent_of[current]
        end
    end

    resolver_root_cache = roots
    return roots
end

-- ============================================================================
-- Object-Type Ancestry
-- ============================================================================

---Build a map from each object type to its ancestors via the `extends` chain,
---keyed by ancestor type and valued by distance (0 = the type itself, 1 = its
---parent, ...). Used to make target-type constraints extends-aware: a constraint
---like "SECTION" should match SECTION descendants (e.g. ABNT textual chapters
---INTRODUCTION/DEVELOPMENT/CONCLUSION, which extend TEXTUAL -> SECTION), not only
---objects whose type is literally SECTION. The distance lets the scorer prefer
---the closest (most specific) match.
---@param data DataManager
---@return table map type_id → { ancestor_type_id → distance } (0 = self)
local function compute_object_ancestry_map(data)
    if object_ancestry_cache then
        return object_ancestry_cache
    end

    local types = data:query_all([[
        SELECT identifier, extends FROM spec_object_types
    ]], {})

    local parent_of = {}
    for _, t in ipairs(types or {}) do
        parent_of[t.identifier] = t.extends
    end

    local ancestry = {}
    for _, t in ipairs(types or {}) do
        local dist = {}
        local current = t.identifier
        local d = 0
        while current and dist[current] == nil do  -- dist[current] doubles as cycle guard
            dist[current] = d
            current = parent_of[current]
            d = d + 1
        end
        ancestry[t.identifier] = dist
    end

    object_ancestry_cache = ancestry
    return ancestry
end

-- ============================================================================
-- CSV Matching
-- ============================================================================

---Match a CSV or scalar constraint against an input value.
---@param csv_or_scalar string|nil
---@param value string|nil
---@param case_insensitive boolean|nil
---@return boolean
local function csv_matches(csv_or_scalar, value, case_insensitive)
    if csv_or_scalar == nil then
        return true
    end
    if not value then
        return false
    end
    local needle = value
    if case_insensitive then
        needle = needle:lower()
    end
    for item in csv_or_scalar:gmatch("[^,]+") do
        local candidate = item:match("^%s*(.-)%s*$")
        if case_insensitive then
            candidate = candidate:lower()
        end
        if candidate == needle then
            return true
        end
    end
    return false
end

---Return the minimal extends-chain distance at which a target-type constraint
---matches a resolved object's type, or nil if it doesn't match at all. Distance
---0 is an exact-type match; larger distances are matches via ancestors (e.g. an
---ABNT INTRODUCTION matching a "SECTION" constraint through TEXTUAL -> SECTION).
---The scorer uses this so a type-specific xref (e.g. XREF_DIC targeting DIC,
---distance 0) outranks the generic XREF_SEC/XREF_SECP (SECTION, distance > 0)
---when both could match. Types absent from the ancestry map (e.g. float types,
---which are not object types) fall back to a direct match at distance 0.
---@param constraint string CSV or scalar of allowed target types
---@param type_ref string|nil Resolved target's concrete type
---@param ancestry table type_id → { ancestor → distance }
---@return integer|nil distance Minimal matching distance, or nil if no match
local function target_type_match_distance(constraint, type_ref, ancestry)
    if not type_ref then
        return nil
    end
    local chain = ancestry and ancestry[type_ref]
    if chain then
        local best = nil
        for ancestor, distance in pairs(chain) do
            if csv_matches(constraint, ancestor, false) then
                if best == nil or distance < best then
                    best = distance
                end
            end
        end
        return best
    end
    if csv_matches(constraint, type_ref, false) then
        return 0
    end
    return nil
end

-- ============================================================================
-- Step 1: Filter Candidates
-- ============================================================================

---Filter relation types whose pre-resolution constraints are compatible.
---Checks selector, source_attribute, and source_type (target_type is deferred
---until after resolution). NULL constraints are wildcards — they always match.
---@param rules table Inference rules
---@param link_selector string|nil Link selector
---@param source_attribute string|nil Source attribute name
---@param source_type string|nil Source object type
---@param resolver_root_map table Type ID → resolver root ID
---@return table candidates Array of {rule, resolver_root}
local function filter_candidates(rules, link_selector, source_attribute, source_type, resolver_root_map)
    local candidates = {}

    for _, rule in ipairs(rules) do
        if rule.selector ~= nil and not csv_matches(rule.selector, link_selector, false) then
            goto skip
        end
        if rule.attr ~= nil and not csv_matches(rule.attr, source_attribute, true) then
            goto skip
        end
        if rule.source ~= nil and not csv_matches(rule.source, source_type, false) then
            goto skip
        end

        table.insert(candidates, {
            rule = rule,
            resolver_root = resolver_root_map[rule.rel_type]
        })

        ::skip::
    end

    return candidates
end

-- ============================================================================
-- Step 2: Resolve Targets
-- ============================================================================

---Call each unique resolver once (grouped by resolver root).
---@param data DataManager
---@param candidates table Candidates from filter step
---@param spec_id string Specification ID
---@param target_text string Raw link target text
---@param source_object_id integer|nil Source object ID
---@return table resolver_results Map of resolver_root → {target, is_ambiguous}
local function resolve_targets(data, candidates, spec_id, target_text, source_object_id)
    local resolver_results = {}
    local seen_roots = {}

    for _, c in ipairs(candidates) do
        local root = c.resolver_root
        if root and not seen_roots[root] then
            seen_roots[root] = true
            local fn = data:get_resolver(root)
            if fn then
                -- The resolver IS the relation type's `resolve` DATA hook: it
                -- takes the frozen DATA ctx (target_text/source_object_id on
                -- the subject -- source_object_id MUST NOT be dropped, it
                -- drives local-scope label resolution) and returns one
                -- {target, ambiguous} table.
                local dctx = hook_ctx.build_data({}, data, nil,
                    { target_text = target_text, source_object_id = source_object_id },
                    "resolve", spec_id)
                local res = fn(dctx)
                if res and res.target then
                    resolver_results[root] = { target = res.target, is_ambiguous = res.ambiguous }
                end
            end
        end
    end

    return resolver_results
end

-- ============================================================================
-- Step 3: Score and Pick Winner
-- ============================================================================

---Score candidates across all 4 constraint dimensions and pick the winner.
---Specificity = count of non-NULL constraints that matched. Higher wins.
---Candidates whose target_type constraint doesn't match are eliminated.
---@param candidates table Filtered candidates
---@param resolver_results table resolver_root → {target, is_ambiguous}
---@param ancestry table Object-type ancestry map for extends-aware target matching
---@return string|nil inferred_type The winning type identifier
---@return string|nil tie_a First tied type (if ambiguous)
---@return string|nil tie_b Second tied type (if ambiguous)
---@return table|nil winning_resolution {target, is_ambiguous} from the winner's resolver root
local function score_and_pick(candidates, resolver_results, ancestry)
    local scored = {}

    for _, c in ipairs(candidates) do
        local resolved = c.resolver_root and resolver_results[c.resolver_root] or nil
        local specificity = 0
        -- Extends-chain distance of the target-type match (0 = exact). Used as a
        -- tie-breaker so the closest (most specific) target type wins. Candidates
        -- without a target constraint sort last via a large sentinel.
        local target_distance = math.huge

        -- Count each non-NULL constraint that matched (filtering already
        -- verified selector, attr, and source — just count them here)
        if c.rule.selector ~= nil then specificity = specificity + 1 end
        if c.rule.attr ~= nil then specificity = specificity + 1 end
        if c.rule.source ~= nil then specificity = specificity + 1 end

        -- Target type: verify match (requires resolution) and count. Matching is
        -- extends-aware so a constraint like "SECTION" accepts SECTION descendants
        -- (e.g. ABNT textual chapters); the match distance breaks ties in favour
        -- of the closest target type (e.g. XREF_DIC's exact DIC beats XREF_SECP's
        -- SECTION reached through DIC -> TRACEABLE -> SECTION).
        if c.rule.target ~= nil then
            if resolved then
                local distance = target_type_match_distance(c.rule.target, resolved.target.type_ref, ancestry)
                if distance ~= nil then
                    specificity = specificity + 1
                    target_distance = distance
                else
                    goto skip  -- target type doesn't match constraint
                end
            else
                goto skip  -- has target constraint but resolution failed
            end
        end

        table.insert(scored, {
            rule = c.rule,
            specificity = specificity,
            target_distance = target_distance,
            resolved = resolved
        })

        ::skip::
    end

    -- Sort by specificity descending, then by target match distance ascending
    -- (closer / more specific target type wins the tie).
    table.sort(scored, function(a, b)
        if a.specificity ~= b.specificity then
            return a.specificity > b.specificity
        end
        return a.target_distance < b.target_distance
    end)

    -- Tie detection: ambiguous only when specificity AND target distance tie
    if #scored >= 2
        and scored[1].specificity == scored[2].specificity
        and scored[1].target_distance == scored[2].target_distance then
        return nil, scored[1].rule.rel_type, scored[2].rule.rel_type, scored[1].resolved
    end

    if #scored > 0 then
        return scored[1].rule.rel_type, nil, false, scored[1].resolved
    end

    return nil, nil, nil, nil
end

-- ============================================================================
-- Apply Resolution to Database
-- ============================================================================

---Store the resolved target in the database.
---@param data DataManager
---@param rel_id integer Relation ID
---@param resolved table {target={id, kind, type_ref}, is_ambiguous=bool}
local function apply_resolution(data, rel_id, resolved)
    if resolved.target.kind == "object" then
        data:execute(Queries.resolution.resolve_relation_to_object, {
            id = rel_id,
            target_object_id = resolved.target.id,
            is_ambiguous = resolved.is_ambiguous and 1 or 0
        })
    elseif resolved.target.kind == "float" then
        data:execute(Queries.resolution.resolve_relation_to_float, {
            id = rel_id,
            target_float_id = resolved.target.id,
            is_ambiguous = resolved.is_ambiguous and 1 or 0
        })
    end
end

-- ============================================================================
-- Core Analysis Loop
-- ============================================================================

---Analyze a single relation: filter compatible types, resolve target, score, pick winner.
---@param data DataManager
---@param rel table Relation row from database
---@param rules table Inference rules
---@param resolver_root_map table Type ID → resolver root ID
---@param ancestry table Object-type ancestry map for extends-aware target matching
local function analyze_relation(data, rel, rules, resolver_root_map, ancestry)
    -- Step 1: Filter types whose constraints are compatible
    local candidates = filter_candidates(
        rules, rel.link_selector, rel.source_attribute, rel.source_type, resolver_root_map
    )

    if #candidates == 0 then return end

    -- Step 2: Resolve the target (each unique resolver called once)
    local resolver_results = resolve_targets(
        data, candidates, rel.specification_ref, rel.target_text, rel.source_object_id
    )

    -- Step 3: Score all 4 dimensions and pick the winner
    local inferred, tie_a, tie_b, winning_resolved = score_and_pick(candidates, resolver_results, ancestry)

    -- Apply resolution (target_object_id or target_float_id)
    if winning_resolved then
        apply_resolution(data, rel.id, winning_resolved)
    end

    -- Apply type inference
    if inferred then
        data:execute(Queries.resolution.update_relation_type, { id = rel.id, type_ref = inferred })
    elseif tie_a and tie_b then
        data:execute(Queries.resolution.mark_relation_ambiguous, { id = rel.id })
    end
end

-- ============================================================================
-- Pipeline Handler
-- ============================================================================

---@param data DataManager
---@param contexts Context[]
---@param diagnostics Diagnostics
function M.on_resolve(data, contexts, diagnostics)
    data:begin_transaction()

    -- Pre-pass: null out stale cross-doc references from cached documents.
    -- Also nulls type_ref so stale relations get re-analyzed.
    data:execute(Queries.resolution.null_dangling_object_targets)
    data:execute(Queries.resolution.null_dangling_float_targets)

    -- Rebuilt specs delete and re-insert their objects/floats, and SQLite
    -- reuses the freed rowids: a cached doc's resolved target id can end up
    -- pointing at a different object without ever dangling. Unresolve every
    -- inbound relation targeting a rebuilt (dirty) spec so it re-resolves by
    -- target_text below.
    for _, ctx in ipairs(contexts) do
        if ctx.doc then
            local spec_id = ctx.spec_id or "default"
            data:execute(Queries.resolution.unresolve_inbound_object_relations, { spec_id = spec_id })
            data:execute(Queries.resolution.unresolve_inbound_float_relations, { spec_id = spec_id })
        end
    end

    -- Collect specs to analyze: dirty contexts + any cached specs with
    -- newly-unresolved relations (from the null-out above)
    local specs_to_analyze = {}
    for _, ctx in ipairs(contexts) do
        specs_to_analyze[ctx.spec_id or "default"] = true
    end

    local stale_specs = data:query_all(Queries.resolution.specs_with_unresolved_relations)
    for _, row in ipairs(stale_specs or {}) do
        specs_to_analyze[row.specification_ref] = true
    end

    -- Load inference rules, resolver root map, and object-type ancestry (cached per run)
    local rules = load_inference_rules(data)
    local resolver_root_map = compute_resolver_root_map(data)
    local ancestry = compute_object_ancestry_map(data)

    -- Analyze all affected specs
    for spec_id in pairs(specs_to_analyze) do
        local relations = data:query_all(
            Queries.resolution.unresolved_relations_for_analysis,
            { spec_id = spec_id }
        )

        local inferred_count = 0
        for _, rel in ipairs(relations or {}) do
            analyze_relation(data, rel, rules, resolver_root_map, ancestry)
            inferred_count = inferred_count + 1
        end

        if inferred_count > 0 then
            logger.info(string.format("Analyzed %d relations in %s", inferred_count, spec_id))
        end
    end

    data:commit()
end

return M
