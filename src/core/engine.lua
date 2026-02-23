---Main Entry Point for SpecCompiler.

local Pipeline = require("core.pipeline")
local DataManager = require("db.manager")
local Diagnostics = require("core.diagnostics")
local DbHandler = require("db.handler")
-- Type system loader (registers object/float/relation/view types from models)
local TypeLoader = require("core.type_loader")
local FileWalker = require("infra.io.file_walker")
local DocumentWalker = require("infra.io.document_walker")
local reference_cache = require("infra.reference_cache")
local reference_generator = require("infra.format.docx.reference_generator")
local logger = require("infra.logger")
local include_handler = require("pipeline.shared.include_handler")
local task_runner = require("infra.process.task_runner")
local sourcepos_compat = require("pipeline.shared.sourcepos_compat")
local build_cache = require("db.build_cache")
local hash_utils = require("infra.hash_utils")

local M = {}

---Get directory from file path
---@param path string File path
---@return string Directory
local function dirname(path)
    local dir = path:match("(.*/)")
    return dir or "."
end

---Compute current hashes for all known includes of a document.
---Queries build_graph for include paths from previous build.
---@param data DataManager Data manager instance
---@param root_path string Root document path
---@return table include_hashes Map of include_path -> current_sha1
local function compute_include_hashes(data, root_path)
    local include_hashes = {}

    -- Get include paths from previous build
    local includes = data:query_all([[
        SELECT node_path FROM build_graph WHERE root_path = :root
    ]], { root = root_path })

    for _, inc in ipairs(includes or {}) do
        local hash, err = hash_utils.sha1_file(inc.node_path)
        if hash then
            include_hashes[inc.node_path] = hash
        end
        -- If file doesn't exist anymore, it won't be in include_hashes
        -- which will cause a cache miss (good - we want to rebuild)
    end

    return include_hashes
end

---Check whether the current project invocation will emit DOCX output.
---@param project_info table Project configuration from config.extract_metadata()
---@return boolean
local function wants_docx_output(project_info)
    if project_info.outputs and type(project_info.outputs) == "table" then
        for _, o in ipairs(project_info.outputs) do
            if o and o.format == "docx" then
                return true
            end
        end
    end

    if project_info.output_format == "docx" then
        return true
    end

    if project_info.output_formats and type(project_info.output_formats) == "table" then
        for _, f in ipairs(project_info.output_formats) do
            if f == "docx" then
                return true
            end
        end
    end

    return false
end

---Check and rebuild reference.docx if preset has changed.
---@param db table Database handler
---@param project_info table Project configuration from config.extract_metadata()
---@param log table Logger instance
local function check_reference_cache(db, project_info, log)
    local speccompiler_home = os.getenv("SPECCOMPILER_HOME")
    if not speccompiler_home then
        log.debug("SPECCOMPILER_HOME not set, skipping reference cache check")
        return
    end

    if not wants_docx_output(project_info) then
        log.debug("DOCX output not requested, skipping reference cache check")
        return
    end

    -- Determine template and preset
    local template = project_info.template or "default"
    local preset_name = (project_info.docx and project_info.docx.preset) or "default"

    -- Determine paths
    local preset_loader = require("infra.format.docx.preset_loader")
    local preset_path = preset_loader.resolve_path(speccompiler_home, template, preset_name)
    if not preset_path then
        log.debug("Preset not found: %s/%s, skipping reference cache check", template, preset_name)
        return
    end

    -- Reference path: use docx.reference_doc if specified, otherwise default to output_dir
    local reference_path = project_info.docx and project_info.docx.reference_doc
    if not reference_path then
        local output_dir = project_info.output_dir or "build"
        reference_path = output_dir .. "/reference.docx"
    end

    -- Check if rebuild is needed
    if reference_cache.needs_rebuild(db, preset_path, reference_path) then
        logger.info("Rebuilding reference.docx (preset changed)", {
            preset = template .. "/" .. preset_name,
            reference_path = reference_path
        })

        local ok, err = reference_generator.generate_from_preset(
            speccompiler_home,
            template,
            preset_name,
            reference_path,
            function(msg) log.debug(msg) end
        )

        if ok then
            local hash_ok, hash_err = reference_cache.update_hash(db, preset_path)
            if hash_ok then
                logger.info("reference.docx rebuilt successfully", {
                    reference_path = reference_path
                })
            else
                logger.error("Failed to update preset hash: " .. (hash_err or "unknown"))
            end
        else
            logger.error("Failed to rebuild reference.docx: " .. (err or "unknown"))
        end
    else
        log.debug("reference.docx is up-to-date")
    end
end

---Run build for a project (from project.yaml metadata).
---This is the main entry point called by filter.lua via Meta(meta).
---@param project_info table Project configuration from config.extract_metadata()
function M.run_project(project_info)
    -- Reset module-level pipeline caches from any prior run.
    -- In production each invocation is a fresh Pandoc process, but test oracles
    -- (and future re-entrant callers) may invoke run_project multiple times
    -- in the same process with different templates/databases.
    local ProofLoader = require("core.proof_loader")
    ProofLoader.reset()
    require("pipeline.initialize.attributes").clear_cache()
    require("pipeline.initialize.specifications").clear_cache()
    require("pipeline.initialize.spec_floats").clear_cache()
    require("pipeline.initialize.spec_views").clear_cache()
    require("pipeline.initialize.spec_relations").clear_cache()
    require("pipeline.analyze.relation_analyzer").clear_cache()
    require("pipeline.transform.view_materializer").clear_cache()

    -- Configure logger from project.yaml settings (with env var override)
    local logging_config = project_info.logging or {}
    local env_level = os.getenv("SPECCOMPILER_LOG_LEVEL")
    if env_level then
        logging_config.level = env_level
    end
    logger.configure(logging_config)

    -- Create log adapter with configured settings
    local log = logger.create_adapter(logging_config.level or "INFO")
    local diag = Diagnostics.new(log)

    -- Log startup info
    log.info("Starting SpecCompiler...")
    log.info("Template: %s", project_info.template or "default")
    log.info("Output directory: %s", project_info.output_dir)
    log.info("Documents to process: %d", #project_info.files)

    -- Ensure output directory exists (using portable luv-based mkdir)
    task_runner.ensure_dir(project_info.output_dir)

    -- Databases are transient build artifacts. If an older specir.db exists
    -- with an incompatible schema, delete it so the new schema can initialize.
    local function db_schema_compatible(db_file)
        if not db_file or not task_runner.file_exists(db_file) then
            return true
        end

        local ok, sqlite = pcall(require, "lsqlite3")
        if not ok or not sqlite then
            -- If sqlite isn't available here, don't risk deleting.
            return true
        end

        local db0 = sqlite.open(db_file)
        if not db0 then
            return false
        end

        local has_id = false
        -- New schema uses INTEGER PRIMARY KEY `id` on spec_objects.
        for row in db0:nrows("PRAGMA table_info(spec_objects)") do
            if row and row.name == "id" then
                has_id = true
                break
            end
        end

        db0:close()
        return has_id
    end

    if project_info.db_file and task_runner.file_exists(project_info.db_file) then
        if not db_schema_compatible(project_info.db_file) then
            log.warn("specir.db schema mismatch detected, rebuilding: %s", project_info.db_file)
            os.remove(project_info.db_file)
        end
    end

    -- Create database in output directory
    local db = DbHandler.new({
        db_file = project_info.db_file,
        log = log
    })

    -- Check and rebuild reference.docx if preset has changed
    check_reference_cache(db, project_info, log)

    local data = DataManager.new(db, log)

    -- Create pipeline
    local pipeline = Pipeline.new({
        log = log,
        diagnostics = diag,
        data = data,
        validation = project_info.validation,
        project_info = project_info
    })

    -- Register core handlers (INITIALIZE phase)
    pipeline:register_handler(require("pipeline.initialize.specifications"))
    pipeline:register_handler(require("pipeline.initialize.spec_objects"))
    pipeline:register_handler(require("pipeline.initialize.spec_floats"))
    pipeline:register_handler(require("pipeline.initialize.spec_relations"))
    pipeline:register_handler(require("pipeline.initialize.spec_views"))
    pipeline:register_handler(require("pipeline.initialize.attributes"))

    -- Register PID generator (ANALYZE phase, runs before relation_analyzer)
    pipeline:register_handler(require("pipeline.analyze.pid_generator"))

    -- Register relation analyzer (ANALYZE phase, type-driven resolution + inference)
    pipeline:register_handler(require("pipeline.analyze.relation_analyzer"))

    -- Register verify handler (VERIFY phase)
    pipeline:register_handler(require("pipeline.verify.verify_handler"))

    -- Register view materializer handler (TRANSFORM phase, pre-computes view data)
    pipeline:register_handler(require("pipeline.transform.view_materializer"))

    -- Register float resolver handler (TRANSFORM phase)
    pipeline:register_handler(require("pipeline.transform.spec_floats"))

    -- Register external render handler (TRANSFORM phase, runs after float resolver)
    pipeline:register_handler(require("pipeline.transform.external_render_handler"))

    -- Register specification render handler (TRANSFORM phase, renders document title)
    pipeline:register_handler(require("pipeline.transform.specification_render_handler"))

    -- Register spec object render handler (TRANSFORM phase, invokes type handlers)
    pipeline:register_handler(require("pipeline.transform.spec_object_render_handler"))

    -- Register float numbering (TRANSFORM phase, assigns numbers before link rewriting)
    pipeline:register_handler(require("pipeline.emit.float_numbering"))

    -- Register relation link rewriter (TRANSFORM phase, rewrites AST links after resolution)
    pipeline:register_handler(require("pipeline.transform.relation_link_rewriter"))

    -- Register FTS indexer (EMIT phase - populates FTS tables for web app search)
    pipeline:register_handler(require("pipeline.emit.fts_indexer"))

    -- Register emitter (EMIT phase - format-agnostic, handles docx, html5, markdown, json)
    pipeline:register_handler(require("pipeline.emit.emitter"))

    -- Load model types based on template
    TypeLoader.load_model(data, pipeline, "default")
    if project_info.template and project_info.template ~= "default" then
        TypeLoader.load_model(data, pipeline, project_info.template)
    end

    -- Load proof views from models (after types are loaded)
    ProofLoader.load_model("default")
    if project_info.template and project_info.template ~= "default" then
        ProofLoader.load_model(project_info.template)
    end
    ProofLoader.create_views(data)

    -- Generate EAV pivot views (after types are loaded)
    local schema_init = require("db.schema.init")
    schema_init.initialize_views(data)

    -- Process all documents (with incremental build caching)
    local cache = build_cache.new(data)
    local walkers = {}
    local cached_count = 0
    local cached_spec_ids = {}  -- Track cached doc spec_ids for EMIT phase
    local pending_cache_updates = {}  -- Deferred until after successful pipeline execution

    for i, file_path in ipairs(project_info.files) do
        -- Compute current file hash
        local current_hash, hash_err = hash_utils.sha1_file(file_path)
        if not current_hash then
            error("Failed to hash " .. file_path .. ": " .. (hash_err or "unknown"))
        end

        -- Check if document (and its includes) need rebuilding
        local include_hashes = compute_include_hashes(data, file_path)
        local is_dirty = cache:is_document_dirty_with_includes(file_path, current_hash, include_hashes)

        if not is_dirty then
            -- Document unchanged - skip parsing, use cached DB state
            log.info("[%d/%d] Cached: %s", i, #project_info.files, file_path)
            cached_count = cached_count + 1
            local spec_id = file_path:match("([^/]+)%.md$") or ("doc_" .. i)
            table.insert(cached_spec_ids, spec_id)
            goto continue
        end

        log.info("[%d/%d] Processing: %s", i, #project_info.files, file_path)

        local content, err = FileWalker.read_file(file_path)
        if not content then
            error("Failed to read " .. file_path .. ": " .. (err or "unknown"))
        end

        -- Parse with pandoc.read() directly (no subprocess!)
        local doc = pandoc.read(content, "commonmark_x+sourcepos")

        -- Strip inline tracking spans for Pandoc version independence
        sourcepos_compat.normalize(doc)

        -- Expand includes in document
        local doc_dir = dirname(file_path)
        local processed = { [file_path] = true }

        local includes
        doc, includes = include_handler.expand_includes(
            doc, doc_dir, file_path, processed, log
        )

        -- Collect include entries (build graph updated after pipeline succeeds)
        local include_entries = {}
        for _, inc in ipairs(includes) do
            table.insert(include_entries, { path = inc.path, hash = inc.sha1 })
        end

        -- Buffer cache update: hash + build_graph deferred until after pipeline
        -- This prevents stale cache entries when a later document errors.
        table.insert(pending_cache_updates, {
            file_path = file_path,
            hash = current_hash,
            includes = include_entries
        })

        -- Create document walker (needed for TRANSFORM and EMIT phases)
        local spec_id = file_path:match("([^/]+)%.md$") or ("doc_" .. i)
        local walker = DocumentWalker.new(doc, {
            spec_id = spec_id,
            source_path = file_path
        })
        table.insert(walkers, walker)

        ::continue::
    end

    if cached_count > 0 then
        log.info("Skipped %d cached document(s)", cached_count)
    end

    -- Execute pipeline with all document walkers
    pipeline:execute(walkers, { cached_spec_ids = cached_spec_ids })

    -- Apply deferred cache updates ONLY after successful verification.
    -- If verification found errors, don't update hashes — this forces
    -- re-processing on the next build so cross-doc relations get a fresh
    -- chance to resolve (prevents cache poisoning from partial builds).
    if not diag:has_errors() then
        for _, update in ipairs(pending_cache_updates) do
            cache:update_document_hash(update.file_path, update.hash)
            cache:update_build_graph(update.file_path, update.includes)
            -- Track includes in build graph (for compute_include_hashes on next build)
            for _, inc in ipairs(update.includes) do
                include_handler.track_include(data, update.file_path, inc.path, inc.hash)
            end
        end
    end

    -- Break reference chain so SQLite connection releases fully.
    -- cache → data → db → sqlite holds the connection alive after close on WSL2.
    cache = nil
    pending_cache_updates = nil

    -- Close database connection for clean exit
    db:close()

    -- Force garbage collection to finalize any lingering SQLite userdata
    collectgarbage("collect")

    -- Sync filesystem to ensure files are flushed (helps with WSL2/Windows interop)
    os.execute("sync")

    if not diag:has_errors() then
        log.info("SpecCompiler build complete. Processed %d document(s).", #project_info.files)
    end
    return diag
end

return M
