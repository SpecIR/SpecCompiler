-- Test oracle for VC-FLOAT-007: markdown-driven data_loader coverage
-- Verifies chart config artifacts reflect expected injection behavior.

local CHART_DIR = "tests/e2e/floats/build/charts"

local function read_file(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local content = f:read("*a")
    f:close()
    return content
end

local function list_chart_json_files()
    local files = {}
    local handle = io.popen("find " .. CHART_DIR .. " -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort")
    if not handle then
        return files
    end
    for line in handle:lines() do
        table.insert(files, line)
    end
    handle:close()
    return files
end

local function find_chart_by_marker(marker)
    for _, path in ipairs(list_chart_json_files()) do
        local content = read_file(path)
        if content and content:find(marker, 1, true) then
            local decoded = pandoc.json.decode(content)
            return decoded, path
        end
    end
    return nil, nil
end

local function assert_original_dataset(cfg, errors, label)
    local source = cfg and cfg.dataset and cfg.dataset.source
    if not source or not source[2] then
        table.insert(errors, label .. ": expected original dataset source")
        return
    end
    if source[2][1] ~= "ORIGINAL" or source[2][2] ~= 1 then
        table.insert(errors, label .. ": dataset should remain ORIGINAL/1 when injection fails or is skipped")
    end
end

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    local params_cfg = find_chart_by_marker("DL_CASE_PARAMS")
    if not params_cfg then
        err("Missing chart artifact for DL_CASE_PARAMS")
    else
        local source = params_cfg.dataset and params_cfg.dataset.source
        local row = source and source[2]
        if not row then
            err("DL_CASE_PARAMS: missing injected dataset row")
        else
            if row[1] ~= 3.5 then err("DL_CASE_PARAMS: expected alpha=3.5") end
            if row[2] ~= 7 then err("DL_CASE_PARAMS: expected count=7") end
            if row[3] ~= "delta" then err("DL_CASE_PARAMS: expected name=delta") end
            if row[4] ~= "default" then
                err("DL_CASE_PARAMS: expected default spec_id propagation")
            end
            if row[5] ~= "alpha=3.5,name=delta" then
                err("DL_CASE_PARAMS: expected params_raw to preserve attrs.params")
            end
        end
    end

    local fallback_cfg = find_chart_by_marker("DL_CASE_FALLBACK")
    if not fallback_cfg then
        err("Missing chart artifact for DL_CASE_FALLBACK")
    else
        local source = fallback_cfg.dataset and fallback_cfg.dataset.source
        if not source or not source[1] or source[1][1] ~= "x" or source[1][2] ~= "y" then
            err("DL_CASE_FALLBACK: expected default gauss view injection with x/y headers")
        elseif #source ~= 6 then
            err("DL_CASE_FALLBACK: expected 5 data points + header from gauss params")
        end
    end

    local missing_cfg = find_chart_by_marker("DL_CASE_MISSING")
    if not missing_cfg then
        err("Missing chart artifact for DL_CASE_MISSING")
    else
        assert_original_dataset(missing_cfg, errors, "DL_CASE_MISSING")
    end

    local nonfunc_cfg = find_chart_by_marker("DL_CASE_NONFUNC")
    if not nonfunc_cfg then
        err("Missing chart artifact for DL_CASE_NONFUNC")
    else
        assert_original_dataset(nonfunc_cfg, errors, "DL_CASE_NONFUNC")
    end

    local throw_cfg = find_chart_by_marker("DL_CASE_THROW")
    if not throw_cfg then
        err("Missing chart artifact for DL_CASE_THROW")
    else
        assert_original_dataset(throw_cfg, errors, "DL_CASE_THROW")
    end

    local unknown_cfg = find_chart_by_marker("DL_CASE_UNKNOWN")
    if not unknown_cfg then
        err("Missing chart artifact for DL_CASE_UNKNOWN")
    else
        assert_original_dataset(unknown_cfg, errors, "DL_CASE_UNKNOWN")
    end

    local sankey_cfg = find_chart_by_marker("DL_CASE_SANKEY")
    if not sankey_cfg then
        err("Missing chart artifact for DL_CASE_SANKEY")
    else
        if sankey_cfg.dataset ~= nil then
            err("DL_CASE_SANKEY: expected dataset to be cleared for sankey injection")
        end
        local series = sankey_cfg.series and sankey_cfg.series[1]
        if not series then
            err("DL_CASE_SANKEY: missing series[1]")
        else
            if not series.data or #series.data ~= 2 then
                err("DL_CASE_SANKEY: expected 2 injected nodes")
            end
            if not series.links or #series.links ~= 1 then
                err("DL_CASE_SANKEY: expected 1 injected link")
            elseif series.links[1].value ~= 4 then
                err("DL_CASE_SANKEY: expected injected link value=4")
            end
        end
    end

    local noview_cfg = find_chart_by_marker("DL_CASE_NOVIEW")
    if not noview_cfg then
        err("Missing chart artifact for DL_CASE_NOVIEW")
    else
        assert_original_dataset(noview_cfg, errors, "DL_CASE_NOVIEW")
    end

    if #errors > 0 then
        return false, "Data view injection validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
