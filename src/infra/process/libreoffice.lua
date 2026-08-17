---LibreOffice DOCX finalization: field updates and PDF export.
---Drives a headless LibreOffice through the UNO bridge (lo_update_fields.py,
---shipped alongside this module) to refresh Word fields (TOC page numbers,
---SEQ captions, cross-references) in a generated DOCX and/or export a PDF.
---
---Template postprocessors call maybe_finalize() from their finalize hook;
---everything is config-driven and degrades to a warning when LibreOffice or
---a UNO-capable Python is missing.
---
---@module infra.process.libreoffice
local M = {}

-- ============================================================================
-- Shell / Filesystem Helpers
-- ============================================================================

local function shell_quote(path)
    return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function read_binary(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function write_binary(path, data)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

local function command_output(cmd)
    local pipe = io.popen(cmd .. " 2>/dev/null")
    if not pipe then return nil end
    local out = pipe:read("*l")
    pipe:close()
    if out and out ~= "" then return out end
    return nil
end

local function command_exists(name)
    return command_output("command -v " .. shell_quote(name))
end

local function dirname(path)
    return tostring(path):match("^(.*)/[^/]+$") or "."
end

local function make_temp_dir()
    return command_output("mktemp -d 2>/dev/null")
end

local function remove_tree(path)
    if path and path ~= "" then
        os.execute("rm -rf " .. shell_quote(path))
    end
end

local function ensure_parent_dir(path)
    local dir = dirname(path)
    if dir and dir ~= "." then
        os.execute("mkdir -p " .. shell_quote(dir))
    end
end

local function replace_file(source, target)
    local data = read_binary(source)
    if not data then return false end
    return write_binary(target, data)
end

-- ============================================================================
-- Availability Detection
-- ============================================================================

local function python_can_import_uno(python)
    local ok = os.execute(shell_quote(python) .. " -c " .. shell_quote("import uno") .. " >/dev/null 2>&1")
    return ok == true or ok == 0
end

local function find_uno_python()
    -- /usr/bin/python3 first: distro UNO bindings (python3-uno) live there,
    -- and a pyenv/venv python3 on PATH usually cannot import uno.
    local candidates = {"/usr/bin/python3"}
    local path_python3 = command_exists("python3")
    if path_python3 then table.insert(candidates, path_python3) end
    local path_python = command_exists("python")
    if path_python then table.insert(candidates, path_python) end

    local seen = {}
    for _, candidate in ipairs(candidates) do
        if candidate and not seen[candidate] then
            seen[candidate] = true
            if candidate:match("^/") or command_exists(candidate) then
                if python_can_import_uno(candidate) then
                    return candidate
                end
            end
        end
    end
    return nil
end

---Locate the UNO helper script shipped next to this module.
---@return string|nil script_path Absolute path, or nil if not found
local function find_helper_script()
    local info = debug.getinfo(1, "S")
    if info and info.source and info.source:sub(1, 1) == "@" then
        local candidate = info.source:sub(2):gsub("libreoffice%.lua$", "lo_update_fields.py")
        if file_exists(candidate) then return candidate end
    end
    local home = os.getenv("SPECCOMPILER_HOME")
    if home then
        local candidate = home .. "/src/infra/process/lo_update_fields.py"
        if file_exists(candidate) then return candidate end
    end
    return nil
end

---Check whether LibreOffice finalization can run on this system.
---@return string|nil soffice Path to the soffice/libreoffice binary
---@return string|nil python Path to a UNO-capable Python (or reason when soffice is nil)
function M.available()
    local soffice = command_exists("libreoffice") or command_exists("soffice")
    if not soffice then
        return nil, "LibreOffice not found on PATH"
    end
    local python = find_uno_python()
    if not python then
        return nil, "no Python executable with UNO support found"
    end
    if not find_helper_script() then
        return nil, "lo_update_fields.py helper script not found"
    end
    return soffice, python
end

-- ============================================================================
-- Configuration
-- ============================================================================

local function docx_config(config)
    return (config and config.docx) or config or {}
end

local function truthy(value)
    if value == true then return true end
    if type(value) == "string" then
        local normalized = value:lower()
        return normalized == "1" or normalized == "true" or normalized == "yes" or normalized == "on"
    end
    return false
end

local function field_update_enabled(config)
    local docx = docx_config(config)
    if docx.update_fields ~= nil then return truthy(docx.update_fields) end
    if docx.libreoffice_update_fields ~= nil then return truthy(docx.libreoffice_update_fields) end
    if docx.refresh_fields ~= nil then return truthy(docx.refresh_fields) end
    return false
end

local function pdf_export_enabled(config)
    local docx = docx_config(config)
    if docx.export_pdf ~= nil then return truthy(docx.export_pdf) end
    if docx.pdf ~= nil then return truthy(docx.pdf) end
    if docx.libreoffice_export_pdf ~= nil then return truthy(docx.libreoffice_export_pdf) end
    return false
end

local function default_pdf_path(path)
    local stem = tostring(path):gsub("%.docx$", "")
    if stem == path then return path .. ".pdf" end
    return stem .. ".pdf"
end

local function pdf_output_path(path, config)
    local docx = docx_config(config)
    local configured = docx.pdf_path or docx.export_pdf_path
    if configured and configured ~= "" then
        if configured:match("^/") then return configured end
        return ((config and config.project_root) or ".") .. "/" .. configured
    end
    return default_pdf_path(path)
end

---Resolve what LibreOffice finalization the config asks for.
---@param path string Path to the DOCX file
---@param config table|nil Configuration (docx.update_fields, docx.export_pdf, ...)
---@return table|nil opts {update_docx, export_pdf, pdf_path} or nil when disabled
function M.resolve_options(path, config)
    local update_docx = field_update_enabled(config)
    local export_pdf = pdf_export_enabled(config)
    if not update_docx and not export_pdf then return nil end
    return {
        update_docx = update_docx,
        export_pdf = export_pdf,
        pdf_path = export_pdf and pdf_output_path(path, config) or nil,
    }
end

-- ============================================================================
-- Finalization
-- ============================================================================

---Run LibreOffice finalization on a DOCX file.
---@param path string Path to the DOCX file
---@param opts table {update_docx boolean, export_pdf boolean, pdf_path string|nil}
---@param log table Logger instance
---@return boolean success
function M.finalize(path, opts, log)
    local soffice, python_or_reason = M.available()
    if not soffice then
        log.warn("[DOCX-LO] %s; skipping LibreOffice finalization for %s", python_or_reason, path)
        return false
    end
    local python = python_or_reason

    local script_path = find_helper_script()
    local temp_dir = make_temp_dir()
    if not temp_dir then
        log.warn("[DOCX-LO] Could not create temporary directory; skipping LibreOffice finalization for %s", path)
        return false
    end

    local profile_dir = temp_dir .. "/lo-profile"
    local updated_docx_path = temp_dir .. "/updated.docx"
    local target_docx = opts.update_docx and updated_docx_path or "-"
    local target_pdf = opts.export_pdf and opts.pdf_path or "-"
    local port = tostring(23000 + (os.time() % 20000))

    if target_pdf ~= "-" then
        ensure_parent_dir(target_pdf)
    end

    local cmd = table.concat({
        shell_quote(python),
        shell_quote(script_path),
        shell_quote(path),
        shell_quote(target_docx),
        shell_quote(target_pdf),
        shell_quote(profile_dir),
        shell_quote(port),
        shell_quote(soffice),
    }, " ")

    local ok = os.execute(cmd)
    local success = ok == true or ok == 0

    if success and opts.update_docx then
        if file_exists(updated_docx_path) and replace_file(updated_docx_path, path) then
            log.info("[DOCX-FIELDS] Updated DOCX fields in place: %s", path)
        else
            success = false
            log.warn("[DOCX-FIELDS] LibreOffice did not produce updated DOCX for %s", path)
        end
    end

    if success and opts.export_pdf then
        if file_exists(target_pdf) then
            log.info("[DOCX-PDF] Generated LibreOffice PDF: %s", target_pdf)
        else
            success = false
            log.warn("[DOCX-PDF] LibreOffice did not produce PDF for %s", path)
        end
    end

    remove_tree(temp_dir)

    if not success then
        log.warn("[DOCX-LO] LibreOffice finalization failed for %s", path)
    end
    return success
end

---Run LibreOffice finalization when the config asks for it; no-op otherwise.
---@param path string Path to the DOCX file
---@param config table|nil Configuration
---@param log table Logger instance
---@return boolean ran_successfully False when disabled or failed
function M.maybe_finalize(path, config, log)
    local opts = M.resolve_options(path, config)
    if not opts then return false end
    local ok, result = pcall(M.finalize, path, opts, log)
    if not ok then
        log.warn("[DOCX-LO] LibreOffice finalization failed for %s: %s", path, tostring(result))
        return false
    end
    return result == true
end

return M
