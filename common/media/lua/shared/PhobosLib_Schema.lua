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
-- PhobosLib_Schema.lua
-- Generic table-against-schema validator.
-- Validates data tables against declarative schema definitions,
-- applies defaults for missing optional fields, and returns
-- structured error lists.
---------------------------------------------------------------

local _TAG = "[PhobosLib:Schema]"

---------------------------------------------------------------
-- Type checking
---------------------------------------------------------------

local function isArray(t)
    if type(t) ~= "table" then return false end
    local n = #t
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
            return false
        end
    end
    return true
end

local function checkType(value, expectedType)
    if expectedType == "string" then
        return type(value) == "string"
    elseif expectedType == "number" then
        return type(value) == "number"
    elseif expectedType == "boolean" then
        return type(value) == "boolean"
    elseif expectedType == "table" then
        return type(value) == "table"
    elseif expectedType == "array" then
        return type(value) == "table"
    end
    return false
end

---------------------------------------------------------------
-- Internal: recursive field validation
---------------------------------------------------------------

local function validateField(value, fieldDef, path, errors)
    -- Required check
    if value == nil then
        if fieldDef.required then
            errors[#errors + 1] = {
                field = path,
                message = "missing required field",
                value = nil,
            }
        end
        return
    end

    -- Type check
    if fieldDef.type and not checkType(value, fieldDef.type) then
        errors[#errors + 1] = {
            field = path,
            message = "expected type '" .. fieldDef.type .. "', got '" .. type(value) .. "'",
            value = value,
        }
        return
    end

    -- String constraints
    if fieldDef.type == "string" then
        if fieldDef.enum then
            local valid = false
            for _, v in ipairs(fieldDef.enum) do
                if v == value then valid = true; break end
            end
            if not valid then
                errors[#errors + 1] = {
                    field = path,
                    message = "invalid value '" .. tostring(value) .. "'; expected one of: " .. table.concat(fieldDef.enum, ", "),
                    value = value,
                }
            end
        end
        if fieldDef.minLength and #value < fieldDef.minLength then
            errors[#errors + 1] = {
                field = path,
                message = "string length " .. #value .. " is below minimum " .. fieldDef.minLength,
                value = value,
            }
        end
    end

    -- Number constraints
    if fieldDef.type == "number" then
        if fieldDef.min and value < fieldDef.min then
            errors[#errors + 1] = {
                field = path,
                message = "must be at least " .. tostring(fieldDef.min),
                value = value,
            }
        end
        if fieldDef.max and value > fieldDef.max then
            errors[#errors + 1] = {
                field = path,
                message = "must be at most " .. tostring(fieldDef.max),
                value = value,
            }
        end
    end

    -- Nested table with sub-schema
    if fieldDef.type == "table" and fieldDef.fields then
        for fieldName, subDef in pairs(fieldDef.fields) do
            validateField(value[fieldName], subDef, path .. "." .. fieldName, errors)
        end
    end
end

---------------------------------------------------------------
-- Internal: recursive default application
---------------------------------------------------------------

local function applyFieldDefaults(data, fieldsDef)
    for fieldName, fieldDef in pairs(fieldsDef) do
        if data[fieldName] == nil and fieldDef.default ~= nil then
            if type(fieldDef.default) == "table" then
                -- Shallow copy default tables to prevent shared mutation
                local copy = {}
                for k, v in pairs(fieldDef.default) do
                    copy[k] = v
                end
                data[fieldName] = copy
            else
                data[fieldName] = fieldDef.default
            end
        end
        -- Recurse into nested table schemas
        if fieldDef.type == "table" and fieldDef.fields
                and type(data[fieldName]) == "table" then
            applyFieldDefaults(data[fieldName], fieldDef.fields)
        end
    end
end

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------

--- Validate a data table against a schema definition.
--- @param data   table  The data to validate
--- @param schema table  Schema with { schemaVersion, fields }
--- @return boolean ok, table[] errors
function PhobosLib.validateSchema(data, schema)
    if type(data) ~= "table" then
        return false, {{ field = "*", message = "data must be a table", value = data }}
    end
    if type(schema) ~= "table" or type(schema.fields) ~= "table" then
        return false, {{ field = "*", message = "invalid schema (missing fields table)", value = nil }}
    end

    -- Schema version check (warn only, don't reject)
    if schema.schemaVersion and data.schemaVersion
            and data.schemaVersion ~= schema.schemaVersion then
        PhobosLib.debug("PhobosLib", _TAG,
            "schemaVersion mismatch: data has v" .. tostring(data.schemaVersion)
            .. ", schema expects v" .. tostring(schema.schemaVersion))
    end

    local errors = {}
    for fieldName, fieldDef in pairs(schema.fields) do
        validateField(data[fieldName], fieldDef, fieldName, errors)
    end

    return #errors == 0, errors
end

--- Apply default values from schema to data (mutates in place).
--- Only fills fields where data[key] == nil and default is defined.
--- @param data   table
--- @param schema table
--- @return table data (same reference)
function PhobosLib.applyDefaults(data, schema)
    if type(data) ~= "table" or type(schema) ~= "table" then return data end
    if type(schema.fields) ~= "table" then return data end

    applyFieldDefaults(data, schema.fields)
    return data
end

--- Format validation errors into human-readable log strings.
--- @param errors table[]  Array of {field, message, value}
--- @param tag    string   Log prefix
--- @return string[]
function PhobosLib.formatValidationErrors(errors, tag)
    local lines = {}
    tag = tag or _TAG
    for _, err in ipairs(errors) do
        local valStr = ""
        if err.value ~= nil then
            valStr = " (got: " .. tostring(err.value) .. ")"
        end
        lines[#lines + 1] = tag .. " " .. err.field .. ": " .. err.message .. valStr
    end
    return lines
end
