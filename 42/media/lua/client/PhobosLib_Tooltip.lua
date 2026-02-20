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
-- PhobosLib_Tooltip.lua
-- Client-side tooltip line appender for item tooltips.
--
-- Provides a provider registry that mods can use to append
-- coloured text lines below the vanilla item tooltip.
--
-- Hooks ISToolTipInv.render() once (on first registration).
-- After the vanilla tooltip is fully drawn, checks item type
-- against registered prefixes and draws extra lines below.
--
-- Drawing approach proven by EHR (Extensive Health Rework B42):
--   self:drawText()  for coloured text lines
--   self:drawRect()  for background fill
--   self:drawRectBorder()  for border outline
--
-- Part of PhobosLib >= 1.9.0
---------------------------------------------------------------

require "ISUI/ISToolTipInv"

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:Tooltip]"

---------------------------------------------------------------
-- Provider registry
---------------------------------------------------------------

--- Internal provider registry: { {prefix=string, provider=function}, ... }
PhobosLib._tooltipProviders = PhobosLib._tooltipProviders or {}

--- Whether the ISToolTipInv.render hook has been installed.
local _hookInstalled = false

--- Reference to the original ISToolTipInv.render function.
local _originalRender = nil

---------------------------------------------------------------
-- Tooltip rendering
---------------------------------------------------------------

--- Collect lines from all matching providers for the given item.
---@param item any  InventoryItem
---@return table|nil  Array of {text=string, r=number, g=number, b=number} or nil
local function collectLines(item)
    local fullType = item:getFullType()
    if not fullType then return nil end

    local allLines = nil

    for _, entry in ipairs(PhobosLib._tooltipProviders) do
        if string.find(fullType, entry.prefix, 1, true) then
            local ok, lines = pcall(entry.provider, item)
            if ok and lines and #lines > 0 then
                if not allLines then allLines = {} end
                for _, line in ipairs(lines) do
                    table.insert(allLines, line)
                end
            end
        end
    end

    return allLines
end

--- Draw extra lines below the vanilla tooltip.
--- Called after originalRender() completes.
---@param self any  ISToolTipInv instance
---@param lines table  Array of {text, r, g, b}
local function drawExtraLines(self, lines)
    local font = UIFont.Small
    local tm = getTextManager()
    local fontHgt = tm:getFontHeight(font)
    local padding = 10
    local lineSpacing = 2

    -- Calculate total extra height needed
    local totalExtraH = padding  -- top gap before first line
    for _ = 1, #lines do
        totalExtraH = totalExtraH + fontHgt + lineSpacing
    end

    -- Calculate max width of new lines
    local maxLineW = 0
    for _, line in ipairs(lines) do
        local w = tm:MeasureStringX(font, line.text or "")
        if w > maxLineW then maxLineW = w end
    end
    local neededW = maxLineW + (padding * 2)

    -- Expand tooltip dimensions
    local oldH = self.height
    local newH = oldH + totalExtraH
    self:setHeight(newH)

    if neededW > self.width then
        self:setWidth(neededW)
    end

    -- Draw background extension
    local bg = self.backgroundColor
    self:drawRect(0, oldH, self.width, totalExtraH, bg.a, bg.r, bg.g, bg.b)

    -- Redraw border at full expanded size
    local bd = self.borderColor
    self:drawRectBorder(0, 0, self.width, newH, bd.a, bd.r, bd.g, bd.b)

    -- Draw each line
    local y = oldH + padding / 2
    for _, line in ipairs(lines) do
        local r = line.r or 1.0
        local g = line.g or 1.0
        local b = line.b or 1.0
        self:drawText(line.text or "", padding, y, r, g, b, 1.0, font)
        y = y + fontHgt + lineSpacing
    end
end

--- Replacement ISToolTipInv.render that appends extra lines.
local function hookedRender(self)
    -- Call original render first (vanilla tooltip fully drawn)
    _originalRender(self)

    -- Append extra lines (all in pcall for B42 resilience)
    pcall(function()
        local item = self.item
        if not item then return end

        local lines = collectLines(item)
        if not lines or #lines == 0 then return end

        drawExtraLines(self, lines)
    end)
end

---------------------------------------------------------------
-- Hook installation
---------------------------------------------------------------

--- Install the ISToolTipInv.render hook (once).
local function installHook()
    if _hookInstalled then return end
    if not ISToolTipInv or not ISToolTipInv.render then
        print(_TAG .. " WARNING: ISToolTipInv.render not found, hook skipped")
        return
    end

    _originalRender = ISToolTipInv.render
    ISToolTipInv.render = hookedRender
    _hookInstalled = true
    print(_TAG .. " ISToolTipInv.render hook installed")
end

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------

--- Register a tooltip line provider for items matching a module prefix.
---
--- The provider function receives the item being hovered and should
--- return an array of line tables, or nil to skip:
---   { {text="Purity: Lab-Grade (99%)", r=0.4, g=0.6, b=1.0}, ... }
---
--- Multiple providers can match the same item (lines are concatenated).
--- Providers are called in registration order.
---
---@param modulePrefix string  Item fullType prefix to match (e.g. "PhobosChemistryPathways.")
---@param provider function    function(item) -> {{text=string, r=number, g=number, b=number}, ...} | nil
function PhobosLib.registerTooltipProvider(modulePrefix, provider)
    if type(modulePrefix) ~= "string" or modulePrefix == "" then
        print(_TAG .. " registerTooltipProvider: invalid modulePrefix")
        return
    end
    if type(provider) ~= "function" then
        print(_TAG .. " registerTooltipProvider: provider must be a function")
        return
    end

    table.insert(PhobosLib._tooltipProviders, {
        prefix = modulePrefix,
        provider = provider,
    })

    -- Install hook on first registration
    installHook()

    print(_TAG .. " registered provider for prefix '" .. modulePrefix .. "'")
end
