--  ________________________________________________________________________
-- / Copyright (c) 2026 Phobos A. D'thorga                                \
-- |                                                                        |
-- |           /\_/\                                                         |
-- |         =/ o o \=    Phobos' PZ Modding                                |
-- |          (  V  )     All rights reserved.                              |
-- |     /\  / \   / \                                                      |
-- |    /  \/   '-'   \   This source code is part of the Phobos            |
-- |   /  /  \  ^  /\  \  mod suite for Project Zomboid (Build 42).         |
-- |  (__/    \_/ \/  \__)                                                  |
-- |     |   | |  | |     Unauthorised copying, modification, or            |
-- |     |___|_|  |_|     distribution of this file is prohibited.          |
-- |                                                                        |
-- \________________________________________________________________________/
--

---------------------------------------------------------------
-- PhobosLib_DataLoader.lua
-- Batch loader for data-only Lua definition files.
-- Loads files via require, validates against a registry's
-- schema, and registers valid definitions.
---------------------------------------------------------------

local _DEFAULT_TAG = "[PhobosLib:Loader]"

---------------------------------------------------------------
-- Single file loader
---------------------------------------------------------------

--- Load and register a single definition file.
--- The file may return either a single record table or an array of record
--- tables. An array is detected by checking whether `result[1]` is a table.
--- When an array is returned, each element is registered individually.
--- @param path     string  require path (e.g. "Definitions/Archetypes/scavenger_trader")
--- @param registry table   PhobosLib registry instance
--- @param tag      string  optional log prefix
--- @return boolean ok, table[]|nil errors
function PhobosLib.loadDefinition(path, registry, tag)
    tag = tag or _DEFAULT_TAG

    -- Attempt require
    local requireOk, result = pcall(require, path)
    if not requireOk then
        local msg = "require failed for '" .. tostring(path) .. "': " .. tostring(result)
        PhobosLib.debug("PhobosLib", tag, msg)
        return false, {{ field = "*", message = msg, value = path }}
    end

    -- Check result is a table
    if type(result) ~= "table" then
        local msg = "'" .. tostring(path) .. "' did not return a table (got " .. type(result) .. ")"
        PhobosLib.debug("PhobosLib", tag, msg)
        return false, {{ field = "*", message = msg, value = path }}
    end

    -- Array detection: if result[1] is a table, treat as array of records.
    -- Each element is registered individually.
    if result[1] and type(result[1]) == "table" then
        local allOk = true
        local allErrors = {}
        for _, record in ipairs(result) do
            local ok, errors = registry:register(record)
            if not ok then
                allOk = false
                if errors then
                    for _, err in ipairs(errors) do
                        allErrors[#allErrors + 1] = err
                    end
                end
            end
        end
        if not allOk then return false, allErrors end
        return true
    end

    -- Single record (existing behaviour)
    return registry:register(result)
end

---------------------------------------------------------------
-- Batch loader
---------------------------------------------------------------

--- Load multiple definition files and register them.
--- @param opts table Configuration:
---   registry: table     PhobosLib registry instance
---   paths:    string[]  require paths for definition files
---   tag:      string    optional log prefix
--- @return table { loaded=number, failed=number, errors=table[] }
function PhobosLib.loadDefinitions(opts)
    opts = opts or {}
    local registry = opts.registry
    local paths = opts.paths or {}
    local tag = opts.tag or _DEFAULT_TAG

    if not registry then
        PhobosLib.debug("PhobosLib", tag, "loadDefinitions called without a registry")
        return { loaded = 0, failed = 0, errors = {} }
    end

    local loaded = 0
    local failed = 0
    local allErrors = {}

    for _, path in ipairs(paths) do
        local ok, errors = PhobosLib.loadDefinition(path, registry, tag)
        if ok then
            loaded = loaded + 1
        else
            failed = failed + 1
            if errors then
                for _, err in ipairs(errors) do
                    allErrors[#allErrors + 1] = err
                end
            end
        end
    end

    PhobosLib.debug("PhobosLib", tag,
        "Loaded " .. tostring(loaded) .. "/" .. tostring(loaded + failed)
        .. " definitions" .. (failed > 0 and (" (" .. tostring(failed) .. " failed)") or ""))

    return { loaded = loaded, failed = failed, errors = allErrors }
end
