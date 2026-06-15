---Configuration and Metadata Extraction for SpecCompiler.
---Handles project.yaml metadata parsing and validation.

local utils = require("pandoc.utils")
local path = require("pandoc.path")
local logger = require("infra.logger")

local M = {}

-- Create logger. Manifest-only configuration (HLR-CFG-001): the effective
-- log level comes from project.yaml `logging.level` (applied by the engine via
-- logger.configure). This module-level adapter only gates config-parse debug
-- lines and defaults to INFO; no env override.
local log = logger.create_adapter("INFO")

---Abort with error message and exit.
---@param msg string Error message
local function abort_with_error(msg)
    io.stderr:write("ERROR: " .. msg .. "\n")
    os.exit(1)
end

---Validates project metadata structure and required fields.
---@param meta table Pandoc metadata table
local function validate_metadata(meta)
    local project_meta = meta.project
    local doc_files = meta.doc_files

    if not project_meta then
        abort_with_error("Missing 'project' section in project.yaml")
    elseif not doc_files or #doc_files == 0 then
        abort_with_error("Missing or empty 'doc_files' in project.yaml")
    end
end

---Extract and transform metadata from project.yaml.
---@param meta table Pandoc metadata table from --metadata-file
---@return table project_info Extracted project configuration
function M.extract_metadata(meta)
    validate_metadata(meta)

    -- Extract project section
    local project = {}
    for k, v in pairs(meta.project) do
        v = utils.stringify(v)
        project[k] = v
        log.debug("Extracted project.%s: %s", k, v)
    end

    -- Extract doc_files list
    local files = {}
    for i, v in ipairs(meta.doc_files) do
        v = utils.stringify(v)
        files[i] = v
        log.debug("Extracted doc_file: %s", v)
    end

    -- Extract paths with defaults
    local output_dir = utils.stringify(meta.output_dir or "build")
    local db_file = path.join({output_dir, "specir.db"})

    -- Extract template (model) for handler loading
    local template = meta.template and utils.stringify(meta.template) or "default"
    log.debug("Template: %s", template)

    -- Extract logging configuration
    local logging = nil
    if meta.logging and type(meta.logging) == "table" then
        logging = {
            level = meta.logging.level and utils.stringify(meta.logging.level) or "INFO",
            format = meta.logging.format and utils.stringify(meta.logging.format) or "auto",
            color = meta.logging.color,
        }
    end

    -- Extract validation policy configuration.
    -- Format: validation: { rule: error|warn|ignore, ... }
    local validation = nil
    if meta.validation and type(meta.validation) == "table" then
        validation = {}
        for k, v in pairs(meta.validation) do
            local rule_name = type(k) == "string" and k or utils.stringify(k)
            local level = utils.stringify(v):lower()
            if level == "error" or level == "warn" or level == "ignore" then
                validation[rule_name] = level
            end
        end
        if next(validation) == nil then
            validation = nil
        end
    end

    -- Extract output formats
    local output_formats = {}
    if meta.output_formats and type(meta.output_formats) == "table" then
        for i, v in ipairs(meta.output_formats) do
            output_formats[i] = utils.stringify(v)
        end
    else
        -- Support individual format flags
        local format_flags = {"gfm", "html5", "docx", "json"}
        for _, format in ipairs(format_flags) do
            if meta[format] == true then
                table.insert(output_formats, format)
            end
        end
    end
    -- Default to docx if no format specified
    if #output_formats == 0 then
        output_formats = {"docx"}
    end

    -- DOCX configuration
    local docx_config = nil
    -- Support both meta.docx.preset and top-level meta.style
    local preset = nil
    if meta.docx and meta.docx.preset then
        preset = utils.stringify(meta.docx.preset)
    elseif meta.style then
        preset = utils.stringify(meta.style)
    end

    if meta.docx and type(meta.docx) == "table" then
        docx_config = {
            reference_doc = meta.docx.reference_doc and utils.stringify(meta.docx.reference_doc) or nil,
            preset = preset,
            table_of_contents = meta.docx.table_of_contents,
            toc_depth = meta.docx.toc_depth and tonumber(utils.stringify(meta.docx.toc_depth)) or nil,
            number_sections = meta.docx.number_sections,
        }
        for k, v in pairs(meta.docx) do
            local key = type(k) == "string" and k or utils.stringify(k)
            if docx_config[key] == nil then
                if type(v) == "boolean" or type(v) == "number" then
                    docx_config[key] = v
                else
                    docx_config[key] = utils.stringify(v)
                end
            end
        end
    elseif preset then
        -- Create docx_config with just preset if style is specified at top level
        docx_config = {
            reference_doc = nil,
            preset = preset,
        }
    end

    -- HTML5 configuration
    local html5_config = nil
    if meta.html5 and type(meta.html5) == "table" then
        html5_config = {
            number_sections = meta.html5.number_sections,
            table_of_contents = meta.html5.table_of_contents,
            toc_depth = meta.html5.toc_depth and tonumber(utils.stringify(meta.html5.toc_depth)) or nil,
            highlight_style = meta.html5.highlight_style and utils.stringify(meta.html5.highlight_style) or nil,
            standalone = meta.html5.standalone,
            embed_resources = meta.html5.embed_resources,
            resource_path = meta.html5.resource_path and utils.stringify(meta.html5.resource_path) or nil,
        }
    end

    -- LaTeX configuration. Keep this generic so template postprocessors can
    -- receive model-specific keys such as uspsc_zip without changing core code.
    local latex_config = nil
    if meta.latex and type(meta.latex) == "table" then
        latex_config = {}
        for k, v in pairs(meta.latex) do
            local key = type(k) == "string" and k or utils.stringify(k)
            if type(v) == "boolean" or type(v) == "number" then
                latex_config[key] = v
            elseif key == "filters" and type(v) == "table" then
                latex_config[key] = {}
                for i, item in ipairs(v) do
                    latex_config[key][i] = utils.stringify(item)
                end
            elseif key == "variables" and type(v) == "table" then
                latex_config[key] = {}
                for vk, vv in pairs(v) do
                    latex_config[key][type(vk) == "string" and vk or utils.stringify(vk)] = utils.stringify(vv)
                end
            else
                latex_config[key] = utils.stringify(v)
            end
        end
    end

    -- New outputs format: [{format, path}, ...]
    local outputs = nil
    if meta.outputs and type(meta.outputs) == "table" then
        outputs = {}
        for _, output in ipairs(meta.outputs) do
            if output.format and output.path then
                local raw_path = utils.stringify(output.path)
                if not path.is_absolute(raw_path) then
                    raw_path = path.join({output_dir, raw_path})
                end
                table.insert(outputs, {
                    format = utils.stringify(output.format),
                    path = raw_path
                })
            end
        end
        if #outputs == 0 then
            outputs = nil
        end
    end

    return {
        project = project,
        template = template,
        files = files,
        output_dir = output_dir,
        output_format = utils.stringify(meta.output_format or "docx"),
        output_formats = output_formats,
        outputs = outputs,  -- New multi-format outputs array
        db_file = db_file,
        -- Logging configuration (from project.yaml)
        logging = logging,
        -- Validation policy configuration (from project.yaml)
        validation = validation,
        -- DOCX configuration
        docx = docx_config,
        -- HTML5 configuration
        html5 = html5_config,
        -- LaTeX configuration
        latex = latex_config,
        -- Bibliography/citation configuration
        bibliography = meta.bibliography and utils.stringify(meta.bibliography) or nil,
    }
end

return M
