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
-- PhobosLib_Migrate.lua
-- Generic versioned migration framework for PZ B42 mods.
-- Mods register migrations at load time; a single OnGameStart
-- hook (server/SP host) runs any pending migrations and sends
-- result notifications to each player's client.
--
-- Three migration outcomes:
--   1. Normal: installed < current → run pending migrations
--   2. Recovery: version stamped but no guards → reset to 0.0.0
--   3. Incompatible: downgrade or invalid version → invoke handler
--      (handler returns "skip", "reset", or "abort" policy)
--
-- World modData keys:
--   PhobosLib_version_<modId>           = "x.y.z"
--   PhobosLib_migration_<modId>_<to>_done = true
--
-- Requires: PhobosLib (PhobosLib_Reset for world modData helpers)
-- Part of PhobosLib -- shared by all Phobos PZ mods.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

local _PREFIX = "PhobosLib_"
local _TAG = "[PhobosLib:Migrate]"
local _registry = {} -- { modId = { { from, to, fn, label }, ... } }
local _incompatibleHandlers = {} -- { modId = function(info) -> "skip"|"reset"|"abort" }

---------------------------------------------------------------
-- Semver Comparison
---------------------------------------------------------------

--- Compare two "major.minor.patch" version strings.
--- Returns -1 if v1 < v2, 0 if equal, 1 if v1 > v2.
---@param v1 string
---@param v2 string
---@return number
function PhobosLib.compareVersions(v1, v2)
    if v1 == v2 then return 0 end
    if not v1 then return -1 end
    if not v2 then return 1 end

    local function parse(v)
        local parts = {}
        for n in string.gmatch(v, "(%d+)") do
            table.insert(parts, tonumber(n) or 0)
        end
        while #parts < 3 do table.insert(parts, 0) end
        return parts
    end

    local a, b = parse(v1), parse(v2)
    for i = 1, 3 do
        if a[i] < b[i] then return -1 end
        if a[i] > b[i] then return 1 end
    end
    return 0
end

---------------------------------------------------------------
-- Version Validation
---------------------------------------------------------------

--- Check if a string looks like a semver version (at least one numeric segment).
---@param v any
---@return boolean
local function isValidSemver(v)
    if type(v) ~= "string" then return false end
    local count = 0
    for _ in string.gmatch(v, "(%d+)") do count = count + 1 end
    return count >= 1
end

---------------------------------------------------------------
-- Incompatible Version Handling
---------------------------------------------------------------

--- Default handler for incompatible version states.
--- Used when no mod-specific handler is registered.
---@param info table  { modId, installed, currentVersion, reason, guardCount }
---@return string     "skip"|"reset"|"abort"
local function defaultIncompatibleHandler(info)
    print(_TAG .. " WARNING: " .. info.modId
        .. " incompatible version (reason=" .. info.reason
        .. ", installed=" .. tostring(info.installed)
        .. ", current=" .. info.currentVersion .. ")")

    if info.reason == "downgrade" then
        return "skip"   -- Don't re-run old migrations on newer save data
    elseif info.reason == "invalid" then
        return "reset"  -- Garbage version, start fresh
    else
        return "skip"   -- Unknown state, stamp and move on
    end
end

--- Invoke the incompatible handler for a mod and apply the returned policy.
---@param modId string
---@param installed string
---@param currentVersion string
---@param reason string         "downgrade"|"invalid"
---@param guardCount number
---@return table|nil results    Non-nil = early return with these results
---@return string|nil installed Nil = early return; string = continue with this installed
local function invokeIncompatibleHandler(modId, installed, currentVersion, reason, guardCount)
    local handler = _incompatibleHandlers[modId] or defaultIncompatibleHandler
    local info = {
        modId          = modId,
        installed      = installed,
        currentVersion = currentVersion,
        reason         = reason,
        guardCount     = guardCount,
    }

    local policyOk, policy = pcall(handler, info)
    if not policyOk then
        print(_TAG .. " ERROR: incompatible handler for " .. modId .. " threw: " .. tostring(policy))
        policy = "abort"
    end

    if policy == "skip" then
        print(_TAG .. " " .. modId .. " policy=skip: stamping " .. currentVersion .. ", no migrations")
        PhobosLib.setInstalledVersion(modId, currentVersion)
        return {{ label = "Version policy: skip", ok = true,
                  msg = "Skipped from " .. tostring(installed) .. " to " .. currentVersion,
                  to = currentVersion, reason = reason }}, nil
    elseif policy == "reset" then
        print(_TAG .. " " .. modId .. " policy=reset: treating as 0.0.0, running all migrations")
        return nil, "0.0.0"
    elseif policy == "abort" then
        print(_TAG .. " " .. modId .. " policy=abort: no stamp, no migrations")
        return {}, nil
    else
        print(_TAG .. " WARNING: unknown policy '" .. tostring(policy) .. "' from " .. modId .. " handler, aborting")
        return {}, nil
    end
end

---------------------------------------------------------------
-- Version Tracking (World modData)
---------------------------------------------------------------

--- Read the installed version of a mod from world modData.
--- Returns nil for first install (key absent).
---@param modId string
---@return string|nil
function PhobosLib.getInstalledVersion(modId)
    local key = _PREFIX .. "version_" .. modId
    return PhobosLib.getWorldModDataValue(key, nil)
end

--- Write the installed version of a mod to world modData.
---@param modId string
---@param version string
function PhobosLib.setInstalledVersion(modId, version)
    pcall(function()
        getGameTime():getModData()[_PREFIX .. "version_" .. modId] = version
    end)
end

---------------------------------------------------------------
-- Migration Registry
---------------------------------------------------------------

--- Register a versioned migration.
--- Migrations run in registration order when the installed
--- version is < `to`.  All migrations from the save's stamped
--- version forward are executed automatically.
---
--- The `from` parameter is retained for documentation and
--- readability at call sites but does NOT gate execution.
--- All migrations where installed < to will run regardless
--- of `from`.
---
--- IMPORTANT: Migration functions must be safe to run on empty/fresh
--- state (no mod items, no known recipes). When no prior version is
--- recorded, all migrations run to handle pre-framework upgrades.
---
---@param modId string   Mod identifier (e.g. "PCP")
---@param from  string|nil  Documentation only: the version this migrates FROM (nil = any). Not used in execution.
---@param to    string   Target version this migration upgrades to
---@param fn    function function(player) -> boolean ok, string msg
---@param label string   Human-readable description for logging
function PhobosLib.registerMigration(modId, from, to, fn, label)
    if not _registry[modId] then _registry[modId] = {} end
    table.insert(_registry[modId], {
        from  = from,
        to    = to,
        fn    = fn,
        label = label or ("migrate to " .. to),
    })
end

--- Register a handler for incompatible version states.
---
--- Called when runMigrations detects a version that cannot be
--- migrated through the normal path (downgrade or invalid version).
---
--- The handler receives a table:
---   { modId, installed, currentVersion, reason, guardCount }
---
--- reason is one of:
---   "downgrade" — installed > currentVersion, guards exist
---   "invalid"   — installed is not a valid semver string
---
--- The handler must return a policy string:
---   "skip"  — stamp currentVersion, do NOT run migrations
---   "reset" — treat as 0.0.0, run ALL migrations from scratch
---   "abort" — do NOT stamp, do NOT run, return empty results
---
--- If no handler is registered, a sensible default is used:
---   "downgrade" -> "skip", "invalid" -> "reset"
---
---@param modId   string
---@param handler function  function(info: table) -> "skip"|"reset"|"abort"
function PhobosLib.registerIncompatibleHandler(modId, handler)
    if type(modId) ~= "string" or modId == "" then
        print(_TAG .. " registerIncompatibleHandler: invalid modId")
        return
    end
    if type(handler) ~= "function" then
        print(_TAG .. " registerIncompatibleHandler: handler must be a function")
        return
    end
    _incompatibleHandlers[modId] = handler
    print(_TAG .. " registered incompatible handler for " .. modId)
end

---------------------------------------------------------------
-- Migration Execution
---------------------------------------------------------------

--- Run all pending migrations for a mod.
--- Skips migrations already marked done in world modData.
--- Updates installed version on completion.
---
---@param modId          string   Mod identifier
---@param currentVersion string   Current mod version (from mod.info)
---@param players        table    Array of IsoGameCharacter
---@return table results  { { label, ok, msg, to }, ... }
function PhobosLib.runMigrations(modId, currentVersion, players)
    local migrations = _registry[modId]
    if not migrations or #migrations == 0 then
        PhobosLib.setInstalledVersion(modId, currentVersion)
        return {}
    end

    local rawInstalled = PhobosLib.getInstalledVersion(modId)
    local installed = rawInstalled

    -- No prior version recorded: treat as "0.0.0" so all migrations run.
    -- This handles both genuine fresh installs (migrations are no-ops on
    -- empty state) and pre-migration upgrades (e.g. v0.17.x -> current).
    if not installed then
        installed = "0.0.0"
        print(_TAG .. " " .. modId .. " no prior version — treating as " .. installed)
    elseif not isValidSemver(installed) then
        -- Non-nil but not a valid version string (garbage/corruption)
        print(_TAG .. " " .. modId .. " invalid version string: '" .. tostring(installed) .. "'")
        local results, newInstalled = invokeIncompatibleHandler(
            modId, installed, currentVersion, "invalid", 0)
        if results then return results end
        installed = newInstalled or "0.0.0"
    end

    -- Count guard keys (used by multiple branches below)
    local guardCount = 0
    for _, mig in ipairs(migrations) do
        local guardKey = _PREFIX .. "migration_" .. modId .. "_" .. mig.to .. "_done"
        if PhobosLib.getWorldModDataValue(guardKey, false) == true then
            guardCount = guardCount + 1
        end
    end

    -- Version comparison
    local cmp = PhobosLib.compareVersions(installed, currentVersion)

    if cmp > 0 then
        -- installed > currentVersion: either downgrade or v1.8.0 bug
        if guardCount > 0 then
            -- Guards exist → legitimate downgrade (newer save, older mod)
            print(_TAG .. " " .. modId .. " downgrade detected: " .. installed .. " > " .. currentVersion)
            local results, newInstalled = invokeIncompatibleHandler(
                modId, installed, currentVersion, "downgrade", guardCount)
            if results then return results end
            installed = newInstalled or "0.0.0"
        else
            -- No guards → version stamped without migrations (v1.8.0 bug)
            print(_TAG .. " " .. modId .. " RECOVERY — version " .. installed
                .. " stamped without migrations (v1.8.0 bug), resetting")
            installed = "0.0.0"
        end
    elseif cmp == 0 then
        -- installed == currentVersion
        if guardCount > 0 then
            print(_TAG .. " " .. modId .. " already at " .. installed)
            return {}
        else
            -- Version stamped but no migrations ever ran — recover
            print(_TAG .. " " .. modId .. " RECOVERY — version " .. installed
                .. " stamped without migrations (v1.8.0 bug), resetting")
            installed = "0.0.0"
        end
    end
    -- else: cmp < 0 → normal upgrade, fall through to migration loop

    print(_TAG .. " " .. modId .. " upgrading " .. installed .. " → " .. currentVersion)

    local results = {}

    for _, mig in ipairs(migrations) do
        -- Skip if installed version is already >= target
        if PhobosLib.compareVersions(installed, mig.to) >= 0 then
            -- Already past this migration
        else
            -- Check world modData guard
            local guardKey = _PREFIX .. "migration_" .. modId .. "_" .. mig.to .. "_done"
            local alreadyDone = PhobosLib.getWorldModDataValue(guardKey, false) == true

            if alreadyDone then
                print(_TAG .. "   " .. mig.label .. " — already done, skipping")
            else
                print(_TAG .. "   " .. mig.label .. " — running...")

                local migOk = true
                local migMsg = ""

                for _, player in ipairs(players) do
                    local ok, msg = false, "unknown error"
                    local success, err = pcall(function()
                        ok, msg = mig.fn(player)
                    end)
                    if not success then
                        ok = false
                        msg = "error: " .. tostring(err)
                    end

                    local pName = "unknown"
                    pcall(function() pName = player:getUsername() or "player" end)
                    print(_TAG .. "     " .. pName .. ": " .. (ok and "OK" or "FAIL") .. " — " .. tostring(msg))

                    if not ok then migOk = false end
                    migMsg = tostring(msg)
                end

                -- Mark migration done
                pcall(function()
                    getGameTime():getModData()[guardKey] = true
                end)

                table.insert(results, {
                    label = mig.label,
                    ok    = migOk,
                    msg   = migMsg,
                    to    = mig.to,
                })
            end
        end
    end

    -- Stamp final version
    PhobosLib.setInstalledVersion(modId, currentVersion)
    print(_TAG .. " " .. modId .. " now at " .. currentVersion)

    return results
end

---------------------------------------------------------------
-- Client Notification
---------------------------------------------------------------

--- Send migration result to a player's client via sendServerCommand.
--- Client should listen for "PCP" module, "migrateResult" command.
---@param player any
---@param modId  string
---@param result table  { label, ok, msg, to, reason? }
function PhobosLib.notifyMigrationResult(player, modId, result)
    pcall(function()
        sendServerCommand(player, modId, "migrateResult", {
            label  = result.label,
            status = result.ok and "ok" or "fail",
            msg    = result.msg,
            to     = result.to,
            reason = result.reason,  -- "downgrade"|"invalid"|nil
        })
    end)
end
