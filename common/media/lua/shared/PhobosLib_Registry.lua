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
-- PhobosLib_Registry.lua
-- Factory for typed, validated registry instances.
-- Each registry stores definitions keyed by a configurable ID
-- field, validates against a PhobosLib_Schema definition, and
-- provides safe lookup/enumeration.
--
-- Supports optional schema version migration: when a definition
-- has schemaVersion < registry.schemaVersion, registered
-- migrator functions run sequentially to upgrade the definition
-- in-place before validation. Non-breaking — registries without
-- schemaVersion/migrators work exactly as before.
---------------------------------------------------------------

local _DEFAULT_TAG = "[PhobosLib:Registry]"

---------------------------------------------------------------
-- Registry metatable (shared across all instances)
---------------------------------------------------------------

local RegistryMT = {}
RegistryMT.__index = RegistryMT

--- Register a definition. Validates against schema, applies
--- defaults, stores if valid, logs errors if not.
--- @param def table  Raw definition table
--- @return boolean ok, table[]|nil errors
function RegistryMT:register(def)
    if self._sealed then
        local msg = "registry '" .. self._name .. "' is sealed; cannot register new definitions"
        PhobosLib.debug("PhobosLib", self._tag, msg)
        return false, {{ field = "*", message = "registry sealed", value = nil }}
    end

    if type(def) ~= "table" then
        local msg = "definition must be a table"
        PhobosLib.debug("PhobosLib", self._tag, msg)
        return false, {{ field = "*", message = msg, value = def }}
    end

    -- Schema version migration: upgrade definition in-place if needed.
    -- Only runs when the registry has schemaVersion + migrators configured
    -- AND the definition's schemaVersion is lower than the registry's.
    if self._schemaVersion and def.schemaVersion
            and type(def.schemaVersion) == "number"
            and def.schemaVersion < self._schemaVersion
            and self._migrators then
        local startVersion = def.schemaVersion
        for v = startVersion, self._schemaVersion - 1 do
            local migrator = self._migrators[v]
            if migrator then
                local mOk, mErr = PhobosLib.safecall(migrator, def)
                if mOk then
                    def.schemaVersion = v + 1
                else
                    PhobosLib.warn("PhobosLib", self._tag,
                        "Migration v" .. tostring(v) .. "→v" .. tostring(v + 1)
                        .. " failed for '" .. tostring(def[self._idField] or "?")
                        .. "': " .. tostring(mErr))
                end
            else
                -- No migrator for this step; bump version anyway
                -- (allows skipping intermediate versions if no changes)
                def.schemaVersion = v + 1
            end
        end
        if def.schemaVersion > startVersion then
            PhobosLib.debug("PhobosLib", self._tag,
                "Migrated '" .. tostring(def[self._idField] or "?")
                .. "' from schema v" .. tostring(startVersion)
                .. " to v" .. tostring(def.schemaVersion))
        end
    end

    -- Apply defaults before validation
    PhobosLib.applyDefaults(def, self._schema)

    -- Validate against schema
    local ok, errors = PhobosLib.validateSchema(def, self._schema)
    if not ok then
        local id = def[self._idField] or "unknown"
        local lines = PhobosLib.formatValidationErrors(errors, self._tag)
        for _, line in ipairs(lines) do
            PhobosLib.debug("PhobosLib", self._tag,
                "\"" .. tostring(id) .. "\" rejected: " .. line)
        end
        return false, errors
    end

    -- Extract ID
    local id = def[self._idField]
    if not id or id == "" then
        local msg = "definition has no '" .. self._idField .. "' field"
        PhobosLib.debug("PhobosLib", self._tag, msg)
        return false, {{ field = self._idField, message = msg, value = nil }}
    end

    -- Duplicate check
    if self._defs[id] and not self._allowOverwrite then
        local msg = "duplicate " .. self._idField .. " '" .. tostring(id) .. "'"
        PhobosLib.debug("PhobosLib", self._tag, msg)
        return false, {{ field = self._idField, message = msg, value = id }}
    end

    self._defs[id] = def
    return true, nil
end

--- Get a registered definition by ID.
--- @param id string
--- @return table|nil
function RegistryMT:get(id)
    return self._defs[id]
end

--- Get all registered definitions as a shallow-copied array.
--- @return table[]
function RegistryMT:getAll()
    local result = {}
    for _, def in pairs(self._defs) do
        result[#result + 1] = def
    end
    return result
end

--- Check if an ID is registered.
--- @param id string
--- @return boolean
function RegistryMT:exists(id)
    return self._defs[id] ~= nil
end

--- Count of registered definitions.
--- @return number
function RegistryMT:count()
    local n = 0
    for _ in pairs(self._defs) do
        n = n + 1
    end
    return n
end

--- Freeze the registry. Subsequent :register() calls will fail.
function RegistryMT:seal()
    self._sealed = true
end

--- Remove a definition by ID. Returns true if found and removed.
--- @param id string
--- @return boolean
function RegistryMT:remove(id)
    if self._defs[id] then
        self._defs[id] = nil
        return true
    end
    return false
end

---------------------------------------------------------------
-- Factory
---------------------------------------------------------------

--- Create a new typed registry instance.
--- @param opts table Configuration:
---   name:           string  (human-readable name for logs)
---   schema:         table   (PhobosLib_Schema definition)
---   idField:        string  (unique key field, default "id")
---   allowOverwrite: boolean (allow re-registration, default false)
---   tag:            string  (debug log prefix)
---   schemaVersion:  number  (optional — current schema version for migration)
---   migrators:      table   (optional — { [fromVersion] = function(def) } upgrade functions)
--- @return table Registry instance
function PhobosLib.createRegistry(opts)
    opts = opts or {}

    local registry = setmetatable({
        _name           = opts.name or "Unnamed",
        _schema         = opts.schema or { fields = {} },
        _idField        = opts.idField or "id",
        _allowOverwrite = opts.allowOverwrite or false,
        _tag            = opts.tag or _DEFAULT_TAG,
        _defs           = {},
        _sealed         = false,
        _schemaVersion  = opts.schemaVersion or nil,
        _migrators      = opts.migrators or nil,
    }, RegistryMT)

    return registry
end
