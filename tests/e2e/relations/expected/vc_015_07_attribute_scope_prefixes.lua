return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg)
        table.insert(errors, msg)
    end

    local links = {}
    local link_targets = {}
    local cite_count = 0

    actual_doc:walk({
        Link = function(link)
            local target = link.target or ""
            local text = pandoc.utils.stringify(link.content or {})
            table.insert(links, { text = text, target = target })
            link_targets[target] = (link_targets[target] or 0) + 1
        end,
        Cite = function()
            cite_count = cite_count + 1
        end,
    })

    if #links < 6 then
        err("Expected at least 6 links in rendered document")
    end

    if (link_targets["#figure:shared-b"] or 0) < 1 then
        err("Expected scoped figure reference target #figure:shared-b from attribute link")
    end
    if (link_targets["#SRC-A-fig-shared-a"] or 0) < 1 then
        err("Expected resolved figure reference target #SRC-A-fig-shared-a")
    end
    if (link_targets["#bar"] or 0) < 1 then
        err("Expected unknown-prefix fallback target #bar")
    end
    if (link_targets["#SRC-A"] or 0) < 1 then
        err("Expected PID target #SRC-A")
    end
    -- NOTE: [@SRC-A](@) produces #SRC-A (same as [SRC-A](@)) because Pandoc's
    -- commonmark_x parser strips the @ prefix from citation-style content.
    if (link_targets["##SRC-A"] or 0) < 1 then
        err("Expected header-style target ##SRC-A")
    end

    if cite_count < 1 then
        err("Expected @cite/@citep selector conversion to Cite node")
    end

    if #errors > 0 then
        return false, "Attribute/scope relation validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true
end
