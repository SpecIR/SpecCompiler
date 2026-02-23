-- Test oracle for VC-REL-003: Citation Cross References
-- Verifies @cite/@citep selector syntax creates proper Cite elements

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Count Cite elements and collect metadata
    local cite_count = 0
    local cite_keys = {}
    local normal_citations = 0
    local author_in_text = 0

    actual_doc:walk({
        Cite = function(el)
            cite_count = cite_count + 1
            for _, citation in ipairs(el.citations or {}) do
                cite_keys[citation.id] = true
                if citation.mode == "NormalCitation" then
                    normal_citations = normal_citations + 1
                elseif citation.mode == "AuthorInText" then
                    author_in_text = author_in_text + 1
                end
            end
        end
    })

    -- Verify expected citation keys exist
    local expected_keys = {"smith2024", "jones2023", "doe2022"}
    for _, key in ipairs(expected_keys) do
        if not cite_keys[key] then
            err("Missing citation key: " .. key)
        end
    end

    -- Verify citation count (minimum expected: 9 individual citations)
    -- Normal: smith2024, jones2023, doe2022, smith2024;jones2023 (2), jones2023
    -- Author-in-text: smith2024, jones2023, doe2022, smith2024
    if cite_count < 8 then
        err("Expected at least 8 Cite elements, found " .. cite_count)
    end

    -- Verify both citation modes exist
    if normal_citations < 4 then
        err("Expected at least 4 NormalCitation modes, found " .. normal_citations)
    end
    if author_in_text < 3 then
        err("Expected at least 3 AuthorInText modes, found " .. author_in_text)
    end

    if #errors > 0 then
        return false, "Citation validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
