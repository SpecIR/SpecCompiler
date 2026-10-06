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

local task_runner = require("infra.process.task_runner")
local zip_utils = require("infra.format.zip_utils")

local is_windows = package.config:sub(1, 1) == "\\"

-- LibreOffice can take a while to start, update fields and export.
local RUN_TIMEOUT_MS = 300000

-- ============================================================================
-- Process / Filesystem Helpers (no shell: identical on POSIX and Windows)
-- ============================================================================

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

---Resolve a command name to its path via PATH (`command -v` / `where`).
local function command_exists(name)
    local ok, out
    if is_windows then
        ok, out = task_runner.spawn_sync("where", { name })
    else
        ok, out = task_runner.spawn_sync("sh", { "-c", 'command -v "$1"', "sh", name })
    end
    local path = ok and out:match("^%s*([^\r\n]+)")
    if path and path ~= "" then return path end
    return nil
end

local function dirname(path)
    return tostring(path):match("^(.*)[/\\][^/\\]+$") or "."
end

local function make_temp_dir()
    local dir = zip_utils.temp_path("_lo")
    if zip_utils.mkdir_p(dir) then return dir end
    return nil
end

local function remove_tree(path)
    if path and path ~= "" then
        zip_utils.rmdir_r(path)
    end
end

local function ensure_parent_dir(path)
    local dir = dirname(path)
    if dir and dir ~= "." then
        zip_utils.mkdir_p(dir)
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
    return (task_runner.spawn_sync(python, { "-c", "import uno" }))
end

---Locate soffice: PATH first, then the standard Windows install locations
---(the Windows installer does not put LibreOffice on PATH).
local function find_soffice()
    local soffice = command_exists("libreoffice") or command_exists("soffice")
    if soffice or not is_windows then return soffice end
    for _, root in ipairs({ os.getenv("ProgramFiles"), os.getenv("ProgramFiles(x86)") }) do
        local candidate = root .. "\\LibreOffice\\program\\soffice.exe"
        if file_exists(candidate) then return candidate end
    end
    return nil
end

local function find_uno_python(soffice)
    -- LibreOffice's own Python (Windows bundles one next to soffice.exe) and
    -- /usr/bin/python3 first: distro UNO bindings (python3-uno) live there,
    -- and a pyenv/venv python3 on PATH usually cannot import uno.
    local candidates = {}
    if is_windows then
        table.insert(candidates, dirname(soffice) .. "\\python.exe")
    else
        table.insert(candidates, "/usr/bin/python3")
    end
    local path_python3 = command_exists("python3")
    if path_python3 then table.insert(candidates, path_python3) end
    local path_python = command_exists("python")
    if path_python then table.insert(candidates, path_python) end

    local seen = {}
    for _, candidate in ipairs(candidates) do
        if candidate and not seen[candidate] then
            seen[candidate] = true
            if file_exists(candidate) and python_can_import_uno(candidate) then
                return candidate
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
    local soffice = find_soffice()
    if not soffice then
        return nil, "LibreOffice not found on PATH"
    end
    local python = find_uno_python(soffice)
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
        if configured:match("^/") or configured:match("^%a:[/\\]") then return configured end
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

    local success = task_runner.spawn_sync(python, {
        script_path,
        path,
        target_docx,
        target_pdf,
        profile_dir,
        port,
        soffice,
    }, { timeout = RUN_TIMEOUT_MS })

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
