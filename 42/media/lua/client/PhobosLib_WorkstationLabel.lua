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
-- PhobosLib_WorkstationLabel.lua
-- Filters untranslated tags from the crafting window's
-- "Requires: ..." workstation label.
--
-- Problem: Both vanilla ISWidgetTitleHeader.updateLabels()
-- and Neat Crafting's NC_RecipeInfoPanel.prerender() iterate
-- ALL recipe tags and build IGUI_CraftingWindow_<tag> keys
-- with no filtering.  Metadata tags like CannotBeResearched
-- have no translation entry, causing raw keys to bleed
-- through (e.g. "Requires: Chemistry Lab or
-- IGUI_CraftingWindow_CannotBeResearched").
--
-- Two code paths:
--   Path 1 (vanilla): hook ISWidgetTitleHeader.updateLabels()
--   Path 2 (NC):      hook NC_RecipeInfoPanel.prerender() +
--                      drawText() to intercept workstation
--                      text rendering
--
-- NC is a soft dependency — detected at runtime via
-- OnGameStart.  If NC is absent, only Path 1 is active.
--
-- Client-side only — auto-loads from 42/media/lua/client/.
---------------------------------------------------------------

require "ISUI/ISWidgetTitleHeader"

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:WorkstationLabel]"

---------------------------------------------------------------
-- Shared utility: build filtered workstation text
---------------------------------------------------------------

--- Build a "Requires: X, Y or Z." string using only tags
--- that have a real IGUI_CraftingWindow_* translation.
--- Returns the formatted string, or nil if no tags resolved.
---@param recipe userdata  Java craftRecipe object
---@return string|nil
local function buildFilteredText(recipe)
    local ok, tags = pcall(function()
        return recipe:getTags()
    end)
    if not ok or not tags then return nil end

    -- Collect only tags that resolve to a real translation
    -- (getText returns the raw key when no translation exists)
    local resolved = {}
    for i = 0, tags:size() - 1 do
        local tag = tags:get(i)
        local key = "IGUI_CraftingWindow_" .. tag
        local text = getText(key)
        if text ~= key then
            table.insert(resolved, text)
        end
    end

    if #resolved == 0 then return nil end

    -- Format with comma + "or" + period (vanilla pattern)
    local out = getText("IGUI_CraftingWindow_RequiresA")
    for i, name in ipairs(resolved) do
        out = out .. " " .. name
        if #resolved > 1 and i < #resolved then
            if i < #resolved - 1 then
                out = out .. ","
            else
                out = out .. " " .. getText("IGUI_CraftingWindow_Or")
            end
        end
    end
    return out .. "."
end

---------------------------------------------------------------
-- Path 1: Vanilla ISWidgetTitleHeader hook
---------------------------------------------------------------

local _origVanilla = ISWidgetTitleHeader.updateLabels

function ISWidgetTitleHeader:updateLabels()
    _origVanilla(self)

    if not self.recipe then return end

    local ok, reqWS = pcall(function()
        return self.recipe:requiresSpecificWorkstation()
    end)
    if not ok or not reqWS then return end

    local filtered = buildFilteredText(self.recipe)
    if filtered then
        self.specificWorkstationLabel.text = filtered
    else
        self.specificWorkstationLabel:setVisible(false)
    end
end

print(_TAG .. " vanilla hook installed")

---------------------------------------------------------------
-- Path 2: Neat Crafting NC_RecipeInfoPanel hook
-- Installed at OnGameStart so NC classes are available.
-- Soft dependency: skipped entirely if NC is not loaded.
---------------------------------------------------------------

local function installNCHooks()
    if not NC_RecipeInfoPanel then
        print(_TAG .. " Neat Crafting not detected — NC hooks skipped")
        return
    end

    -- Cache the "Requires:" prefix for locale-safe detection
    local requiresPrefix = getText("IGUI_CraftingWindow_RequiresA")

    -- Save originals
    local _origPrerender = NC_RecipeInfoPanel.prerender
    local _origDrawText  = NC_RecipeInfoPanel.drawText

    --- Hook prerender: pre-compute filtered workstation text
    --- and store on self for the drawText hook to consume.
    function NC_RecipeInfoPanel:prerender()
        self._phlibWsOverride = nil

        if self.logic then
            local ok, recipe = pcall(function()
                return self.logic:getRecipe()
            end)
            if ok and recipe then
                local ok2, reqWS = pcall(function()
                    return recipe:requiresSpecificWorkstation()
                end)
                if ok2 and reqWS then
                    self._phlibWsOverride = buildFilteredText(recipe)
                end
            end
        end

        _origPrerender(self)

        -- Belt and suspenders: clear override after prerender
        self._phlibWsOverride = nil
    end

    --- Hook drawText: intercept the workstation text call and
    --- substitute with the filtered version.  Identified by
    --- matching the "Requires:" prefix (locale-safe).
    function NC_RecipeInfoPanel:drawText(text, x, y, r, g, b, a, font)
        if self._phlibWsOverride
            and type(text) == "string"
            and requiresPrefix
            and text:sub(1, #requiresPrefix) == requiresPrefix then

            -- Compute available width for truncation
            local maxW = self.width - x - 5
            local ok, truncated = pcall(NeatTool.truncateText,
                self._phlibWsOverride, maxW, font, "...")
            if ok and truncated then
                text = truncated
            end

            -- Consume the override so subsequent drawText
            -- calls in this prerender pass through unmodified
            self._phlibWsOverride = nil
        end

        return _origDrawText(self, text, x, y, r, g, b, a, font)
    end

    print(_TAG .. " Neat Crafting hooks installed")
end

Events.OnGameStart.Add(installNCHooks)

print(_TAG .. " loaded [client]")
