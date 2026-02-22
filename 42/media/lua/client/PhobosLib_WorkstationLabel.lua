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
-- Problem: ISWidgetTitleHeader.updateLabels() iterates ALL
-- recipe tags and builds IGUI_CraftingWindow_<tag> keys for
-- each.  Metadata tags like CannotBeResearched have no
-- translation entry, so they bleed through as raw keys
-- (e.g. "Requires: Chemistry Lab or IGUI_CraftingWindow_
-- CannotBeResearched").
--
-- Vanilla avoids this because its only CannotBeResearched
-- recipes pair it with AnySurfaceCraft (not a CraftBench),
-- so requiresSpecificWorkstation() returns false and the
-- "Requires:" section stays hidden.  Mods that combine a
-- real CraftBench tag with CannotBeResearched trigger the
-- display bug.
--
-- Fix: after calling the original updateLabels(), rebuild the
-- label using only tags that resolve to real translations.
--
-- Client-side only — auto-loads from 42/media/lua/client/.
---------------------------------------------------------------

require "ISUI/ISWidgetTitleHeader"

local _TAG = "[PhobosLib:WorkstationLabel]"

local _orig_updateLabels = ISWidgetTitleHeader.updateLabels

function ISWidgetTitleHeader:updateLabels()
    _orig_updateLabels(self)

    -- Only act on recipes that show the "Requires:" section
    if not self.recipe then return end

    local ok, reqWS = pcall(function()
        return self.recipe:requiresSpecificWorkstation()
    end)
    if not ok or not reqWS then return end

    local ok2, tags = pcall(function()
        return self.recipe:getTags()
    end)
    if not ok2 or not tags then return end

    -- Collect only tags that have a real IGUI_CraftingWindow_ translation
    -- (getText returns the raw key when no translation exists)
    local resolved = {}
    for i = 0, tags:size() - 1 do
        local tag  = tags:get(i)
        local key  = "IGUI_CraftingWindow_" .. tag
        local text = getText(key)
        if text ~= key then
            table.insert(resolved, text)
        end
    end

    -- If no tags resolved (shouldn't happen, but be safe), hide the label
    if #resolved == 0 then
        self.specificWorkstationLabel:setVisible(false)
        return
    end

    -- Rebuild the label text with comma + "or" formatting (vanilla pattern)
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
    out = out .. "."

    self.specificWorkstationLabel.text = out
end

print(_TAG .. " loaded [client]")
