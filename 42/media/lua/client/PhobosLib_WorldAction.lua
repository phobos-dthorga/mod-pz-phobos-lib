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
-- PhobosLib_WorldAction.lua
-- Client-side world object context menu registration system.
--
-- Provides a generic API for mods to register right-click
-- context menu actions on world objects identified by sprite
-- name.  Multiple mods can register actions for the same
-- sprite; all matching entries are shown.
--
-- Hook: Events.OnFillWorldObjectContextMenu
--   Fires when the player right-clicks a world object.
--
-- Part of PhobosLib >= 1.12.0 (red-unavailable support added 1.14.0)
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:WorldAction]"

---------------------------------------------------------------
-- Action registry
---------------------------------------------------------------

--- Internal registry: { {sprites=table, label=string, test=fn|nil, action=fn, guard=fn|nil, tooltip=string|nil}, ... }
PhobosLib._worldActionEntries = PhobosLib._worldActionEntries or {}

--- Whether the event hook has been installed.
local _hookInstalled = false

---------------------------------------------------------------
-- Sprite matching
---------------------------------------------------------------

--- Get the sprite name from a world object, safely.
---@param obj any  IsoObject
---@return string|nil
local function getSpriteName(obj)
    if not obj then return nil end
    local ok, sprite = pcall(function() return obj:getSprite() end)
    if not ok or not sprite then return nil end
    local nameOk, name = pcall(function() return sprite:getName() end)
    if not nameOk then return nil end
    return name or nil
end

--- Check whether an object's sprite matches any name in a list.
---@param obj any         IsoObject
---@param sprites table   List of sprite name strings
---@return boolean
local function matchesSprite(obj, sprites)
    local name = getSpriteName(obj)
    if not name then return false end
    for _, s in ipairs(sprites) do
        if name == s then return true end
    end
    return false
end

---------------------------------------------------------------
-- Tooltip formatting
---------------------------------------------------------------

--- Format test failure reason(s) into a red-coloured tooltip string.
--- Handles string, table-of-strings, or nil (generic fallback).
--- All <RGB>/<LINE> markup is centralised here — mods provide plain text only.
---@param baseTooltip string|nil  The normal tooltip text (shown above reasons)
---@param reasons string|table|nil  Failure reason(s) from the test function
---@return string  Formatted tooltip with red-coloured requirement lines
local function formatFailureTooltip(baseTooltip, reasons)
    local lines = {}

    -- Normal tooltip first (if present)
    if baseTooltip then
        table.insert(lines, baseTooltip)
    end

    -- Failure reasons in red
    if type(reasons) == "table" then
        for _, r in ipairs(reasons) do
            table.insert(lines, "<RGB:1,0,0> " .. tostring(r))
        end
    elseif type(reasons) == "string" then
        table.insert(lines, "<RGB:1,0,0> " .. reasons)
    else
        table.insert(lines, "<RGB:1,0,0> Requirements not met.")
    end

    return table.concat(lines, " <LINE> ")
end

---------------------------------------------------------------
-- Context menu handler
---------------------------------------------------------------

--- Event handler for OnFillWorldObjectContextMenu.
---@param playerNum number       Player index
---@param context any            ISContextMenu
---@param worldobjects table     Table of IsoObject that were right-clicked
---@param test boolean           True if testing for context menu availability
local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test then return end
    if #PhobosLib._worldActionEntries == 0 then return end

    local player = getSpecificPlayer(playerNum)
    if not player then return end

    -- Deduplicate: when a square has multiple stacked objects with the
    -- same sprite, avoid showing the same entry more than once.
    local shownEntries = {}

    for _, obj in ipairs(worldobjects) do
        for idx, entry in ipairs(PhobosLib._worldActionEntries) do
            if shownEntries[idx] then
                -- Already shown (or shown-as-red) for a previous object
            else

            local shouldShow = true

            -- Check sprite match
            if shouldShow then
                if not matchesSprite(obj, entry.sprites) then
                    shouldShow = false
                end
            end

            -- Check guard function (e.g. mod active, sandbox option)
            if shouldShow and entry.guard then
                local guardOk, guardResult = pcall(entry.guard)
                if not guardOk or guardResult ~= true then
                    shouldShow = false
                end
            end

            -- Check test function (e.g. player has required items)
            -- Test failures show the option in red (notAvailable) instead
            -- of hiding it, so the player knows the interaction exists.
            local testFailed = false
            local testReasons = nil
            if shouldShow and entry.test then
                local testOk, testResult, tReasons = pcall(entry.test, player, obj)
                if not testOk or testResult ~= true then
                    testFailed = true
                    if testOk then testReasons = tReasons end
                end
            end

            if shouldShow then
                shownEntries[idx] = true

                local label = entry.label or "Action"
                local option = context:addOption(label, player, entry.action, obj)

                -- Mark red/unclickable when test failed
                if testFailed and option then
                    option.notAvailable = true
                end

                -- Build tooltip: failure reasons in red, or normal tooltip
                local tooltipText = nil
                if testFailed then
                    tooltipText = formatFailureTooltip(entry.tooltip, testReasons)
                elseif entry.tooltip then
                    tooltipText = entry.tooltip
                end

                if tooltipText and option then
                    local tooltipObj = ISWorldObjectContextMenu.addToolTip()
                    if tooltipObj then
                        tooltipObj.description = tooltipText
                        option.toolTip = tooltipObj
                    end
                end
            end

            end -- else (not already shown)
        end
    end
end

---------------------------------------------------------------
-- Hook installation
---------------------------------------------------------------

--- Install the event hook (once).
local function installHook()
    if _hookInstalled then return end
    Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
    _hookInstalled = true
    print(_TAG .. " OnFillWorldObjectContextMenu hook installed")
end

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------

--- Register a context menu action for world objects matching specific sprites.
---
--- When the player right-clicks a world object whose sprite name matches
--- one of the registered sprite names, the specified context menu option
--- is added.  Multiple registrations for the same sprite are all shown.
---
--- @param config table  Configuration table with fields:
---   sprites  (table)     List of sprite name strings to match (required)
---   label    (string)    Context menu display text (required)
---   action   (function)  Callback: function(player, obj) (required)
---   test     (function)  Optional: function(player, obj) -> boolean [, reasons].
---                          Return true to show the option as normal.
---                          Return false to show the option in red (notAvailable)
---                          with an optional reason tooltip.  The second return
---                          value can be a plain string or a table of plain
---                          strings — PhobosLib handles all <RGB>/<LINE> markup.
---                          Examples:
---                            return false                          -- generic fallback
---                            return false, "Requires: Empty Jar"   -- single reason
---                            return false, {"Need A", "Need B"}    -- multiple reasons
---   guard    (function)  Optional: function() -> boolean.
---                          Global guard (sandbox option, mod active).
---                          Checked before test().  Guard failures hide
---                          the option entirely (not shown in red).
---   tooltip  (string)    Optional: tooltip description text.  When test
---                          fails, this text is shown above the red reasons.
function PhobosLib.registerWorldObjectAction(config)
    if type(config) ~= "table" then
        print(_TAG .. " registerWorldObjectAction: config must be a table")
        return
    end
    if type(config.sprites) ~= "table" or #config.sprites == 0 then
        print(_TAG .. " registerWorldObjectAction: sprites must be a non-empty table")
        return
    end
    if type(config.label) ~= "string" or config.label == "" then
        print(_TAG .. " registerWorldObjectAction: label must be a non-empty string")
        return
    end
    if type(config.action) ~= "function" then
        print(_TAG .. " registerWorldObjectAction: action must be a function")
        return
    end
    if config.test ~= nil and type(config.test) ~= "function" then
        print(_TAG .. " registerWorldObjectAction: test must be a function or nil")
        return
    end
    if config.guard ~= nil and type(config.guard) ~= "function" then
        print(_TAG .. " registerWorldObjectAction: guard must be a function or nil")
        return
    end

    table.insert(PhobosLib._worldActionEntries, {
        sprites = config.sprites,
        label   = config.label,
        action  = config.action,
        test    = config.test,
        guard   = config.guard,
        tooltip = config.tooltip,
    })

    -- Install hook on first registration
    installHook()

    print(_TAG .. " registered action '" .. config.label .. "' for sprites: " .. table.concat(config.sprites, ", "))
end
