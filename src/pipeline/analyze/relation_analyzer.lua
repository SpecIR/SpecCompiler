---Relation Analyzer Handler for SpecCompiler.
---Pipeline handler for ANALYZE phase.
---
---Type-driven relation analysis: filter, resolve, score, pick.
---
---For each unresolved relation:
---  1. Filter: find relation types whose constraints are compatible
---  2. Resolve: call the resolver (determined by extends chain) to find the target
---  3. Score: count matching non-NULL constraints across all 4 dimensions
---  4. Pick: highest specificity wins; ties mark the relation ambiguous
---
---@module relation_analyzer
local logger = require("infra.logger")
local Queries = require("db.queries")
local cache_registry = require("pipeline.shared.cache_registry")

local M = {
    name = "relation_analyzer",
    prerequisites = {"pid_generator"}
}

-- Cache for inference rules (loaded from database)
local inference_rules_cache = nil

-- Cache for resolver root map (type_id → root_type_id)
local resolver_root_cache = nil

---Clear module-level caches (required for re-entrant engine.run_project calls).
function M.clear_cache()
    inference_rules_cache = nil
    resolver_root_cache = nil
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
                local result, is_ambiguous = fn(data, spec_id, target_text, source_object_id)
                if result then
                    resolver_results[root] = { target = result, is_ambiguous = is_ambiguous }
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
---@return string|nil inferred_type The winning type identifier
---@return string|nil tie_a First tied type (if ambiguous)
---@return string|nil tie_b Second tied type (if ambiguous)
---@return table|nil winning_resolution {target, is_ambiguous} from the winner's resolver root
local function score_and_pick(candidates, resolver_results)
    local scored = {}

    for _, c in ipairs(candidates) do
        local resolved = c.resolver_root and resolver_results[c.resolver_root] or nil
        local specificity = 0

        -- Count each non-NULL constraint that matched (filtering already
        -- verified selector, attr, and source — just count them here)
        if c.rule.selector ~= nil then specificity = specificity + 1 end
        if c.rule.attr ~= nil then specificity = specificity + 1 end
        if c.rule.source ~= nil then specificity = specificity + 1 end

        -- Target type: verify match (requires resolution) and count
        if c.rule.target ~= nil then
            if resolved then
                if csv_matches(c.rule.target, resolved.target.type_ref, false) then
                    specificity = specificity + 1
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
            resolved = resolved
        })

        ::skip::
    end

    -- Sort by specificity descending
    table.sort(scored, function(a, b)
        return a.specificity > b.specificity
    end)

    -- Tie detection
    if #scored >= 2 and scored[1].specificity == scored[2].specificity then
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
local function analyze_relation(data, rel, rules, resolver_root_map)
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
    local inferred, tie_a, tie_b, winning_resolved = score_and_pick(candidates, resolver_results)

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
function M.on_analyze(data, contexts, diagnostics)
    data:begin_transaction()

    -- Pre-pass: null out stale cross-doc references from cached documents.
    -- Also nulls type_ref so stale relations get re-analyzed.
    data:execute(Queries.resolution.null_dangling_object_targets)
    data:execute(Queries.resolution.null_dangling_float_targets)

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

    -- Load inference rules and resolver root map (cached per run)
    local rules = load_inference_rules(data)
    local resolver_root_map = compute_resolver_root_map(data)

    -- Analyze all affected specs
    for spec_id in pairs(specs_to_analyze) do
        local relations = data:query_all(
            Queries.resolution.unresolved_relations_for_analysis,
            { spec_id = spec_id }
        )

        local inferred_count = 0
        for _, rel in ipairs(relations or {}) do
            analyze_relation(data, rel, rules, resolver_root_map)
            inferred_count = inferred_count + 1
        end

        if inferred_count > 0 then
            logger.info(string.format("Analyzed %d relations in %s", inferred_count, spec_id))
        end
    end

    data:commit()
end

return M
