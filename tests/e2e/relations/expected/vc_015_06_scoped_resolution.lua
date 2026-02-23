-- Test oracle for VC-REL-004: Scoped resolution and header/PID normalization.
-- Floats are resolved to full anchors ({parent-pid}-{type-prefix}-{user-label})
-- with numbered display text (e.g., "Figure 1").

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    local link_targets = {}
    local target_counts = {}

    actual_doc:walk({
        Link = function(link)
            local target = link.target or ""
            local text = pandoc.utils.stringify(link.content or {})
            table.insert(link_targets, { text = text, target = target })

            target_counts[target] = (target_counts[target] or 0) + 1
        end
    })

    if #link_targets < 4 then
        err("Expected at least 4 resolved links, found " .. tostring(#link_targets))
    end

    if (target_counts["#SRC-001-fig-shared-label"] or 0) < 1 then
        err("Expected resolved figure reference to target #SRC-001-fig-shared-label")
    end
    if (target_counts["#SRC-002-fig-shared-label-two"] or 0) < 1 then
        err("Expected resolved figure reference to target #SRC-002-fig-shared-label-two")
    end
    if (target_counts["#SRC-002"] or 0) < 1 then
        err("Expected resolved PID target #SRC-002 from [@SRC-002](@)")
    end
    if (target_counts["##SRC-001"] or 0) < 1 then
        err("Expected header-id style target ##SRC-001 from [#SRC-001](@)")
    end

    if #errors > 0 then
        return false, "Scoped relation validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
