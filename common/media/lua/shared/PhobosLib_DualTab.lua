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
-- PhobosLib_DualTab.lua
-- Shared dual-dimension tab bar widget for terminal screens.
-- Renders two rows of tabs (e.g. category × status) with
-- active highlighting and callback-driven navigation.
--
-- Eliminates ~80-100 lines of duplicated tab rendering code
-- per screen. Used by POSnet FreeAgents, WholesalerDir,
-- Assignments, and any future dual-filtered terminal views.
--
-- Usage:
--   local newY = PhobosLib_DualTab.create({
--       panel   = contentPanel,
--       y       = startY,
--       tabs1   = { {id="all", labelKey="UI_All"}, ... },
--       tabs2   = { {id="active", labelKey="UI_Active"}, ... },
--       active1 = currentTab1,
--       active2 = currentTab2,
--       colours = W.COLOURS,
--       btnH    = ctx.btnH,
--       onTabChange = function(tab1, tab2)
--           POS_ScreenManager.replaceCurrent(screenId, { ... })
--       end,
--   })
---------------------------------------------------------------

require "PhobosLib"

PhobosLib_DualTab = {}

local TAB_GAP     = 2   -- px between tabs
local TAB_PADDING = 4   -- px text inset within active label
local TAB_ROW_GAP = 4   -- px between tab rows

--- Render a single tab row.
---@param config table
---@param tabs table Array of { id, labelKey, label? }
---@param activeId string Currently active tab ID
---@param y number Current Y position
---@param otherActiveId string The OTHER dimension's current tab
---@param isRow1 boolean True if this is row 1
---@return number newY
local function renderTabRow(config, tabs, activeId, y, otherActiveId, isRow1)
    local panel = config.panel
    local W = config._W
    local C = config.colours
    local btnH = config.btnH or 24
    local panelW = panel:getWidth()

    local tabW = math.floor(panelW / #tabs) - TAB_GAP
    local tabX = 0

    for _, tab in ipairs(tabs) do
        local label = tab.label
            or (tab.labelKey and PhobosLib.safeGetText(tab.labelKey))
            or tab.id

        if activeId == tab.id then
            -- Active: render as bright label with ">" prefix
            W.createLabel(panel, tabX + TAB_PADDING, y + 2,
                "> " .. label, C.textBright)
        else
            -- Inactive: render as button
            local tabId = tab.id
            W.createButton(panel, tabX, y, tabW, btnH,
                label, nil, function()
                    if config.onTabChange then
                        if isRow1 then
                            config.onTabChange(tabId, otherActiveId)
                        else
                            config.onTabChange(otherActiveId, tabId)
                        end
                    end
                end)
        end

        tabX = tabX + tabW + TAB_GAP
    end

    return y + btnH + TAB_ROW_GAP
end

--- Create a dual-dimension tab bar (two rows of filter tabs).
---
--- @param config table Configuration:
---   panel      ISPanel   The content panel to render into
---   y          number    Starting Y position
---   tabs1      table     Array of { id, labelKey?, label? } for row 1
---   tabs2      table     Array of { id, labelKey?, label? } for row 2
---   active1    string    Active tab ID for row 1
---   active2    string    Active tab ID for row 2
---   colours    table     Colour table (from POS_TerminalWidgets.COLOURS)
---   btnH       number?   Button height (default 24)
---   onTabChange function(tab1, tab2) Called when any tab is clicked
---   _W         table     Widget module (POS_TerminalWidgets) — required for createLabel/createButton
---
--- @return number newY  Y position after both tab rows + separator
function PhobosLib_DualTab.create(config)
    if not config or not config.panel then return config and config.y or 0 end

    local y = config.y or 0

    -- Row 1
    y = renderTabRow(config, config.tabs1, config.active1, y,
        config.active2, true)

    -- Row 2
    y = renderTabRow(config, config.tabs2, config.active2, y,
        config.active1, false)

    return y
end

--- Create a single-dimension tab bar (one row of filter tabs).
--- Convenience wrapper for screens that only need one filter dimension.
---
--- @param config table Same as create() but uses tabs1 + active1 only
--- @return number newY
function PhobosLib_DualTab.createSingle(config)
    if not config or not config.panel then return config and config.y or 0 end

    local y = config.y or 0

    y = renderTabRow(config, config.tabs1, config.active1, y,
        nil, true)

    return y
end
