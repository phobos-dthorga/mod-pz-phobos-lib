---------------------------------------------------------------
-- PhobosLib_Migrate.lua
-- Generic versioned migration framework for PZ B42 mods.
-- Mods register migrations at load time; a single OnGameStart
-- hook (server/SP host) runs any pending migrations and sends
-- result notifications to each player's client.
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
local _registry = {} -- { modId = { { from, to, fn, label }, ... } }

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
--- version is < `to`.
---
--- IMPORTANT: Migration functions must be safe to run on empty/fresh
--- state (no mod items, no known recipes). When no prior version is
--- recorded, all migrations run to handle pre-framework upgrades.
---
---@param modId string   Mod identifier (e.g. "PCP")
---@param from  string   Minimum installed version to trigger (nil = any)
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

    local installed = PhobosLib.getInstalledVersion(modId)

    -- No prior version recorded: treat as "0.0.0" so all migrations run.
    -- This handles both genuine fresh installs (migrations are no-ops on
    -- empty state) and pre-migration upgrades (e.g. v0.17.x -> current).
    if not installed then
        installed = "0.0.0"
        print("[PhobosLib:Migrate] " .. modId .. " no prior version — treating as " .. installed)
    end

    -- Already at or beyond current version
    if PhobosLib.compareVersions(installed, currentVersion) >= 0 then
        -- Consistency check: if version is stamped but NO migration guard
        -- keys exist, the version was stamped without migrations running
        -- (PhobosLib v1.8.0 bug). Reset to "0.0.0" so migrations re-run.
        local anyGuardExists = false
        for _, mig in ipairs(migrations) do
            local guardKey = _PREFIX .. "migration_" .. modId .. "_" .. mig.to .. "_done"
            if PhobosLib.getWorldModDataValue(guardKey, false) == true then
                anyGuardExists = true
                break
            end
        end

        if anyGuardExists then
            print("[PhobosLib:Migrate] " .. modId .. " already at " .. installed)
            return {}
        end

        -- Version stamped but no migrations ever ran — recover
        print("[PhobosLib:Migrate] " .. modId .. " RECOVERY — version " .. installed
            .. " stamped without migrations (v1.8.0 bug), resetting")
        installed = "0.0.0"
    end

    print("[PhobosLib:Migrate] " .. modId .. " upgrading " .. installed .. " → " .. currentVersion)

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
                print("[PhobosLib:Migrate]   " .. mig.label .. " — already done, skipping")
            else
                print("[PhobosLib:Migrate]   " .. mig.label .. " — running...")

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
                    print("[PhobosLib:Migrate]     " .. pName .. ": " .. (ok and "OK" or "FAIL") .. " — " .. tostring(msg))

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
    print("[PhobosLib:Migrate] " .. modId .. " now at " .. currentVersion)

    return results
end

---------------------------------------------------------------
-- Client Notification
---------------------------------------------------------------

--- Send migration result to a player's client via sendServerCommand.
--- Client should listen for "PCP" module, "migrateResult" command.
---@param player any
---@param modId  string
---@param result table  { label, ok, msg, to }
function PhobosLib.notifyMigrationResult(player, modId, result)
    pcall(function()
        sendServerCommand(player, modId, "migrateResult", {
            label  = result.label,
            status = result.ok and "ok" or "fail",
            msg    = result.msg,
            to     = result.to,
        })
    end)
end
