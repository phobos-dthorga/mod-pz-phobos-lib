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
-- For items with matching providers, performs a FULL RENDER
-- REPLACEMENT that replicates the vanilla render flow with
-- expanded dimensions to accommodate extra lines. For items
-- with no matching providers, delegates to the original render
-- unchanged.
--
-- Why full replacement? The vanilla render draws background,
-- border, and Java DoTooltip at the measured size. Trying to
-- extend AFTER the original render causes clipping because
-- the Java ObjectTooltip already rendered at its measured dims.
-- By replicating the flow with expanded dimensions, we draw
-- background/border at the full size BEFORE Java renders, and
-- our extra lines fit below the Java content.
--
-- Reference: ISToolTipInv.lua (vanilla), EHR_TooltipSystem.lua
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

--- Full render replacement for items with provider lines.
--- Replicates the vanilla ISToolTipInv.render() flow (lines 43-107)
--- but with expanded dimensions to accommodate extra lines below
--- the Java ObjectTooltip content.
---@param self any  ISToolTipInv instance
local function hookedRender(self)
    -- Fast path: if no item or no matching providers, delegate unchanged
    local item = self.item
    if not item then
        return _originalRender(self)
    end

    local lines = nil
    pcall(function()
        lines = collectLines(item)
    end)

    if not lines or #lines == 0 then
        return _originalRender(self)
    end

    -- From here: full render replacement (matching vanilla flow)
    -- Wrapped in pcall for B42 API resilience — if anything fails,
    -- fall back to original render
    local renderOk, renderErr = pcall(function()
        -- Context menu guard (same as vanilla line 45)
        if ISContextMenu.instance and ISContextMenu.instance.visibleCheck then
            return
        end

        -- Mouse position (same as vanilla lines 47-56)
        local mx = getMouseX() + 24
        local my = getMouseY() + 24
        if not self.followMouse then
            mx = self:getX()
            my = self:getY()
            if self.anchorBottomLeft then
                mx = self.anchorBottomLeft.x
                my = self.anchorBottomLeft.y
            end
        end

        -- PADX (vanilla uses 0, kept for compatibility)
        local PADX = 0

        -- Measure-only pass (same as vanilla lines 58-66)
        self.tooltip:setX(mx + PADX)
        self.tooltip:setY(my)
        self.tooltip:setWidth(50)
        self.tooltip:setMeasureOnly(true)
        self.item:DoTooltip(self.tooltip)
        self.tooltip:setMeasureOnly(false)

        -- Get vanilla measured dimensions
        local tw = self.tooltip:getWidth()
        local th = self.tooltip:getHeight()

        -- Calculate extra height for provider lines
        local font = UIFont.Small
        local tm = getTextManager()
        local fontHgt = tm:getFontHeight(font)
        local padding = 10
        local lineSpacing = 2

        local extraH = padding  -- gap above first provider line
        for _ = 1, #lines do
            extraH = extraH + fontHgt + lineSpacing
        end

        -- Calculate max provider line width
        local maxLineW = 0
        for _, line in ipairs(lines) do
            local w = tm:MeasureStringX(font, line.text or "")
            if w > maxLineW then maxLineW = w end
        end

        -- Expanded dimensions
        local totalW = math.max(tw, maxLineW + padding * 2)
        local totalH = th + extraH

        -- Screen clamping (same as vanilla lines 68-81)
        local myCore = getCore()
        local maxX = myCore:getScreenWidth()
        local maxY = myCore:getScreenHeight()

        self.tooltip:setX(math.max(0, math.min(mx + PADX, maxX - totalW - 1)))
        if not self.followMouse and self.anchorBottomLeft then
            self.tooltip:setY(math.max(0, math.min(my - totalH, maxY - totalH - 1)))
        else
            self.tooltip:setY(math.max(0, math.min(my, maxY - totalH - 1)))
        end

        -- Joyfocus / context menu positioning (same as vanilla lines 83-92)
        if self.contextMenu and self.contextMenu.joyfocus then
            local playerNum = self.contextMenu.player
            self.tooltip:setX(getPlayerScreenLeft(playerNum) + 60)
            self.tooltip:setY(getPlayerScreenTop(playerNum) + 60)
        elseif self.contextMenu and self.contextMenu.currentOptionRect then
            if self.contextMenu.currentOptionRect.height > 32 then
                self:setY(my + self.contextMenu.currentOptionRect.height)
            end
            self:adjustPositionToAvoidOverlap(self.contextMenu.currentOptionRect)
        end

        -- Set panel dimensions with EXPANDED size (same as vanilla lines 94-97)
        self:setX(self.tooltip:getX() - PADX)
        self:setY(self.tooltip:getY())
        self:setWidth(totalW + PADX)
        self:setHeight(totalH)

        -- Avoid overlap with mouse cursor (same as vanilla lines 99-101)
        if self.followMouse and (self.contextMenu == nil) then
            self:adjustPositionToAvoidOverlap({ x = mx - 24 * 2, y = my - 24 * 2, width = 24 * 2, height = 24 * 2 })
        end

        -- Draw background and border at EXPANDED size (same as vanilla lines 103-104)
        self:drawRect(0, 0, self.width, self.height,
            self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
        self:drawRectBorder(0, 0, self.width, self.height,
            self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)

        -- Render Java tooltip content (same as vanilla line 105)
        -- Java renders at its original measured size within the expanded panel
        self.item:DoTooltip(self.tooltip)

        -- Draw provider lines below vanilla content
        local y = th + padding / 2
        for _, line in ipairs(lines) do
            local r = line.r or 1.0
            local g = line.g or 1.0
            local b = line.b or 1.0
            self:drawText(line.text or "", padding, y, r, g, b, 1.0, font)
            y = y + fontHgt + lineSpacing
        end
    end)

    -- If pcall failed, fall back to original render
    if not renderOk then
        print(_TAG .. " render error: " .. tostring(renderErr))
        _originalRender(self)
    end
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
    print(_TAG .. " ISToolTipInv.render hook installed (full render replacement)")
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
