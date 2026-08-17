-- Test oracle for VC-029: reference.docx preset-chain cache invalidation.

return function(actual_doc, helpers)
    local errors = {}
    local function check(condition, message)
        if not condition then errors[#errors + 1] = message end
    end

    check(actual_doc and actual_doc.blocks and #actual_doc.blocks > 0,
        "expected a non-empty rendered document")

    local home = os.getenv("SPECCOMPILER_HOME") or "."
    local preset_loader = require("infra.format.docx.preset_loader")
    local chain, chain_err = preset_loader.resolve_chain_paths(
        home, "default", "test_preset_default"
    )
    check(chain ~= nil, "could not resolve fixture preset chain: " .. tostring(chain_err))
    if chain then
        check(#chain == 2, "expected two preset files in chain, got " .. #chain)
        check(chain[1]:match("models/default/styles/test_preset_default/preset%.lua$") ~= nil,
            "top preset is not first in resolved chain: " .. tostring(chain[1]))
        check(chain[2]:match("models/default/styles/test_preset_base/preset%.lua$") ~= nil,
            "extended base preset is not second in resolved chain: " .. tostring(chain[2]))
    end

    if chain then
        local reference_cache = require("infra.reference_cache")
        local store = {}
        local db = {
            exec_sql = function() end,
            query_all = function(_, _, params)
                local value = store[params.key]
                return value == nil and {} or {{value = value}}
            end,
            execute = function(_, _, params)
                store[params.key] = params.value
                return true
            end,
        }

        local probe_dir = helpers.build_dir .. "/reference-cache-probe"
        require("infra.process.task_runner").ensure_dir(probe_dir)
        local reference_path = probe_dir .. "/reference.docx"
        local base_copy = probe_dir .. "/base-preset.lua"

        local function read(path)
            local file = io.open(path, "rb")
            if not file then return nil end
            local content = file:read("*a")
            file:close()
            return content
        end
        local function write(path, content)
            local file = assert(io.open(path, "wb"))
            file:write(content)
            file:close()
        end

        write(reference_path, "reference fixture")
        write(base_copy, assert(read(chain[2]), "could not read base preset fixture"))
        local probe_chain = {chain[1], base_copy}

        local updated, update_err = reference_cache.update_hash(db, probe_chain)
        check(updated, "could not store preset-chain hash: " .. tostring(update_err))
        check(reference_cache.needs_rebuild(db, probe_chain, reference_path) == false,
            "unchanged preset chain unexpectedly invalidated reference.docx")

        write(base_copy, read(base_copy) .. "\n-- simulated base preset change\n")
        check(reference_cache.needs_rebuild(db, probe_chain, reference_path) == true,
            "changing the extended base preset did not invalidate reference.docx")
    end

    if #errors > 0 then
        return false, "Reference cache validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true
end
