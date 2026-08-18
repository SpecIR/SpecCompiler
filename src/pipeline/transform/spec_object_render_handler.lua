---Spec Object Render Handler for SpecCompiler.
---TRANSFORM phase handler that invokes type handlers to render spec objects.
---
---Types like COVER, DEDICATION, etc. can define header() and body() functions
---that transform the stored AST into styled output. This handler invokes the
---host-indexed object render hook to apply those transformations.
---
---@module spec_object_render_handler
local M = {
    name = "spec_object_render_handler",
    prerequisites = {"attributes", "spec_floats_transform", "relation_link_rewriter"}  -- Runs after float resolution and link rewriting
}

local logger = require("infra.logger")
local attribute_para = require("pipeline.shared.attribute_para_utils")
local render_utils = require("pipeline.shared.render_utils")
local ast_utils = require("pipeline.shared.ast_utils")
local spec_object_base = require("pipeline.shared.spec_object_base")
local Queries = require("db.queries")
local registry = require("contract.registry")
local hook_ctx = require("pipeline.shared.hook_ctx")

---Encode Pandoc blocks to JSON for storage.
---Uses pandoc.json.encode for consistency with section_handler.
---@param blocks table Array of Pandoc blocks
---@return string JSON representation
local function encode_ast(blocks)
    if not blocks or #blocks == 0 then return "[]" end

    return pandoc.json.encode(blocks)
end

-- Object render dispatch reads host:get_hook_inherited("object", type_ref, "render")
-- (overlaid default -> template).

---Query attributes for a spec object.
---Returns both string values and AST for rich content rendering.
---@param data DataManager
---@param object_id string Object identifier
---@return table attributes Map of attribute names to {value, ast} tables
local function get_object_attributes(data, object_id)
    local results = data:query_all(Queries.content.select_attributes_by_owner,
        {owner_id = object_id})

    local attrs = {}
    if results then
        for _, row in ipairs(results) do
            local name = row.name and row.name:lower() or ""
            attrs[name] = {
                value = row.string_value or row.raw_value or "",
                ast = row.ast  -- JSON-encoded Pandoc inlines (may be nil)
            }
        end
    end
    return attrs
end

---Query spec-level attributes (title, author, etc. set on the specification
---itself, not on any object or float). Returned as a flat name -> string map
---keyed by lowercase name; `raw_value` is used when `string_value` is absent.
---@param data DataManager
---@param spec_ref string Specification identifier
---@return table attrs Map of lowercase attribute name -> string value
local function get_spec_attributes(data, spec_ref)
    local results = data:query_all(Queries.content.select_spec_attributes,
        {spec_ref = spec_ref})

    local attrs = {}
    if results then
        for _, row in ipairs(results) do
            local name = row.name and row.name:lower() or ""
            attrs[name] = row.string_value or row.raw_value or ""
        end
    end
    return attrs
end

-- decode_ast: use ast_utils.decode_blocks (shared utility)
local decode_ast = ast_utils.decode_blocks

---Filter out Header blocks from an array of blocks.
---The stored AST includes the section header, but type handlers create their own
---styled header, so we need to exclude the original to avoid duplicates.
---@param blocks table Array of Pandoc blocks
---@return table filtered Blocks without Headers
local function filter_headers(blocks)
    if not blocks then return {} end
    local filtered = {}
    for _, block in ipairs(blocks) do
        -- Check block type (handles both table and userdata)
        local block_type = block.t or (block.tag) or ""
        if block_type ~= "Header" then
            table.insert(filtered, block)
        end
    end
    return filtered
end

---Was this blockquote extracted as an attribute of the current object?
---Mirrors the INITIALIZE-phase disambiguation: a blockquote is stripped iff
---its first paragraph's key matches a STORED attribute (case-insensitive).
---Prose blockquotes -- including `key:`-shaped ones whose key is not a
---declared attribute -- are never stripped.
---@param blockquote table Pandoc BlockQuote block
---@param attributes table Stored attribute map (lowercased names)
---@return boolean
local function is_extracted_attribute_blockquote(blockquote, attributes)
    local paras = attribute_para.collect_paragraphs(blockquote)
    if #paras == 0 then return false end
    local name = attribute_para.get_field_name(paras[1])
    return name ~= nil and attributes[name:lower()] ~= nil
end

---Filter out EXTRACTED attribute BlockQuotes from an array of blocks.
---Attributes are extracted during INITIALIZE phase and rendered by spec_object_base.
---The raw blockquotes should not appear in the rendered output; prose
---blockquotes pass through untouched.
---@param blocks table Array of Pandoc blocks
---@param attributes table Stored attribute map for the object (lowercased names)
---@return table filtered Blocks without extracted attribute BlockQuotes
local function filter_attribute_blockquotes(blocks, attributes)
    if not blocks then return {} end
    attributes = attributes or {}
    local filtered = {}
    for _, block in ipairs(blocks) do
        local block_type = block.t or (block.tag) or ""

        -- Check if block is a BlockQuote holding an extracted attribute
        if block_type == "BlockQuote" and is_extracted_attribute_blockquote(block, attributes) then
            -- Skip this attribute blockquote
            logger.debug("Filtered attribute blockquote")
        elseif block_type == "Div" then
            -- Check for wrapped BlockQuote (sourcepos)
            local div_content = block.c or block.content or {}
            if type(div_content[2]) == "table" then
                div_content = div_content[2]
            end
            -- If Div contains only an extracted attribute blockquote, skip it
            local is_attr_div = false
            if #div_content == 1 and div_content[1].t == "BlockQuote" then
                if is_extracted_attribute_blockquote(div_content[1], attributes) then
                    is_attr_div = true
                end
            end
            if not is_attr_div then
                table.insert(filtered, block)
            end
        else
            table.insert(filtered, block)
        end
    end
    return filtered
end

---Unwrap spec-object wrapper Divs from a previous transform run.
---Extracts children to top level so downstream filters can process them.
---@param blocks table Array of Pandoc blocks
---@return table unwrapped Blocks with spec-object wrappers replaced by their children
local function unwrap_spec_object_divs(blocks)
    if not blocks then return {} end
    local result = {}
    for _, block in ipairs(blocks) do
        local block_type = block.t or (block.tag) or ""

        if block_type == "Div" and render_utils.block_has_class(block, "spec-object") then
            -- Extract children to top level
            local children = block.content or (block.c and block.c[2]) or {}
            for _, child in ipairs(children) do
                table.insert(result, child)
            end
            logger.debug("Unwrapped spec-object Div for idempotent re-transform")
        else
            table.insert(result, block)
        end
    end
    return result
end

---Filter out Divs with the given class from previous transform runs.
---These may exist from a previous transform and should not be duplicated
---(spec_object_base.render_attributes() / the render hook add fresh ones).
---Filtering keeps type handler rendering idempotent across repeated TRANSFORMs.
---@param blocks table Array of Pandoc blocks
---@param class string Div class to drop (e.g., "spec-object-header")
---@return table filtered Blocks without Divs of that class
local function filter_divs_with_class(blocks, class)
    if not blocks then return {} end
    local filtered = {}
    for _, block in ipairs(blocks) do
        local block_type = block.t or (block.tag) or ""
        if block_type == "Div" and render_utils.block_has_class(block, class) then
            logger.debug("Filtered existing " .. class .. " Div (idempotent transform)")
        else
            table.insert(filtered, block)
        end
    end
    return filtered
end

---Default render for objects whose type declares no render hook anywhere on
---its extends chain (SECTION containers, plain data types like SYMBOL): the
---authored heading shifted to the constant -1 emit level with the PID as the
---anchor, the body passed through unchanged, and the attribute card. This is
---the path that guarantees attributes ALWAYS appear -- the raw `> key: value`
---blockquotes were already filtered from body_blocks by the caller.
---The heading keeps its authored inlines (formatting preserved); declarative
---schema options are honored: unnumbered/numbered gate the "unnumbered"
---class, skip_attributes suppresses the card, attr_order orders it.
---@param obj table Object row (level, pid, title_text, type_ref)
---@param unwrapped table Decoded blocks before header filtering
---@param body_blocks table Filtered body blocks
---@param attributes table Attribute map from get_object_attributes
---@param type_schema table The type's schema (render options)
---@return table blocks Rendered blocks
local function default_render(obj, unwrapped, body_blocks, attributes, type_schema)
    local header
    for _, block in ipairs(unwrapped) do
        local block_type = block.t or (block.tag) or ""
        if block_type == "Header" then
            header = block
            break
        end
    end

    local level = math.max((obj.level or 2) - 1, 1)
    if header then
        header.level = level
        -- Typed headings are authored as "TYPE: Title"; show the parsed title.
        -- Untyped headings stringify to exactly title_text and keep their
        -- authored inlines (preserving inline formatting).
        local authored = pandoc.utils.stringify(header.content)
        if obj.title_text and obj.title_text ~= "" and authored ~= obj.title_text then
            header.content = { pandoc.Str(obj.title_text) }
        end
    else
        header = pandoc.Header(level, { pandoc.Str(obj.title_text or obj.type_ref or "") })
    end
    if obj.pid and obj.pid ~= "" then
        header.attr.identifier = obj.pid
    end
    if (type_schema.unnumbered == true or type_schema.numbered == false)
        and not header.attr.classes:includes("unnumbered") then
        header.attr.classes:insert("unnumbered")
    end

    local blocks = { header }
    for _, block in ipairs(body_blocks) do
        table.insert(blocks, block)
    end

    if not type_schema.skip_attributes then
        local attr_div = spec_object_base.render_attributes(
            { attributes = attributes }, pandoc, type_schema.attr_order)
        if attr_div then
            table.insert(blocks, attr_div)
        end
    end

    return blocks
end

---TRANSFORM phase: Invoke type handlers to render spec objects.
---@param data DataManager
---@param contexts Context[]
---@param diagnostics Diagnostics
function M.on_transform(data, contexts, diagnostics)
    local log = logger.create_diagnostic_adapter(diagnostics, "RENDER")

    data:begin_transaction()
    -- Cache spec-level attributes per specification_ref across all objects in
    -- this transform run. Handlers read ctx.spec_attributes (populated below)
    -- instead of re-querying.
    local spec_attributes_cache = {}
    local spec_info_cache = {}
    local function spec_attributes_for(spec_ref)
        if not spec_ref then return {} end
        local cached = spec_attributes_cache[spec_ref]
        if cached == nil then
            cached = get_spec_attributes(data, spec_ref)
            spec_attributes_cache[spec_ref] = cached
        end
        return cached
    end
    local function spec_info_for(spec_ref)
        if not spec_ref then return {} end
        local cached = spec_info_cache[spec_ref]
        if cached == nil then
            cached = data:query_one(Queries.content.select_specification_for_render,
                { spec_id = spec_ref }) or {}
            spec_info_cache[spec_ref] = cached
        end
        return cached
    end

    local host = registry.current()
    for _, ctx in ipairs(contexts) do
        local spec_id = ctx.spec_id or "default"

        -- Query spec objects for this spec that might need type handler rendering
        local objects = data:query_all(Queries.content.select_typed_objects_by_spec,
            { spec_id = spec_id })

        if not objects or #objects == 0 then
            log.debug("No typed spec objects found for rendering")
            goto continue
        end

        log.debug("Processing %d typed spec objects for rendering", #objects)

        local rendered_count = 0
        for _, obj in ipairs(objects) do
            local render = host and host:get_hook_inherited("object", obj.type_ref, "render")

            -- Filter out headers, attribute blockquotes, and existing spec-object-attributes divs
            -- - Headers: renders create their own heading
            -- - Attribute blockquotes: rendered as DefinitionList by spec_object_base
            -- - Spec-object-attributes divs: prevent duplicate attribute rendering
            local desc = host and host:get_descriptor("object", obj.type_ref)
            local type_schema = desc and desc.schema or {}
            local attributes = get_object_attributes(data, obj.id)

            local decoded_blocks = decode_ast(obj.ast) or {}
            local unwrapped = unwrap_spec_object_divs(decoded_blocks)
            -- Sequential filtering: remove elements that renders will recreate
            local body_blocks = filter_headers(unwrapped)
            body_blocks = filter_attribute_blockquotes(body_blocks, attributes)
            body_blocks = filter_divs_with_class(body_blocks, "spec-object-attributes")
            body_blocks = filter_divs_with_class(body_blocks, "spec-object-header")

            local ok, result
            if render then
                -- The object render hook receives the canonical frozen ctx
                -- (HLR-EXT-009): invariant core + the object subject. spec_id is
                -- the object's own specification.
                -- The rendering type's schema carries declarative render options
                -- (attr_order, show_pid, ...) for the host card renderer.
                local subject = {
                    object = obj,
                    attributes = attributes,
                    specification = spec_info_for(obj.specification_ref),
                    spec_attributes = spec_attributes_for(obj.specification_ref),
                    element = body_blocks,
                    header_level = obj.level or 2,
                    type_schema = type_schema,
                }
                local render_ctx = hook_ctx.build(
                    ctx, data, diagnostics, subject, "render", obj.specification_ref)

                -- Call the host-indexed object render hook
                ok, result = pcall(render, render_ctx)
            else
                -- No render hook anywhere on the extends chain: default render
                -- (heading at the constant -1 shift + body + attribute card).
                ok, result = pcall(default_render,
                    obj, unwrapped, body_blocks, attributes, type_schema)
            end

            if ok and result and #result > 0 then
                -- Encode new blocks and update database
                local new_ast = encode_ast(result)

                data:execute(Queries.content.update_object_ast, {
                    ast = new_ast,
                    id = obj.id
                })

                rendered_count = rendered_count + 1
                log.debug("Rendered %s: %s", obj.type_ref, obj.pid or obj.title_text or tostring(obj.id))
            elseif not ok then
                log.warn("Handler error for %s '%s': %s", obj.type_ref, obj.pid or obj.title_text or tostring(obj.id), tostring(result))
            end
        end

        log.info("Rendered %d spec objects", rendered_count)

        ::continue::
    end
    data:commit()
end

return M
