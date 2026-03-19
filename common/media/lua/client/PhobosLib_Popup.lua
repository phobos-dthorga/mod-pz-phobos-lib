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
-- PhobosLib_Popup.lua
-- Generic popup system for PZ B42 mods.
--
-- Provides three popup types:
--   1. Guide  — first-time tutorial/introduction with
--               "Don't show again" checkbox
--   2. Notice — one-time migration/announcement popup
--               with optional shouldShow() condition gate
--   3. Changelog — version-based "What's New" popup
--               that fires on major/minor version bumps
--
-- Series support: mods can declare series membership via
-- options.series to consolidate popups across a mod family.
-- When multiple mods share a series ID, their popups are
-- grouped into a single window with collapsible per-mod
-- sections (toggle bar hidden for single-mod series).
--
-- Mods register popups at file load time via:
--   PhobosLib.registerGuidePopup(modId, options)
--   PhobosLib.registerNoticePopup(modId, noticeId, options)
--   PhobosLib.registerChangelogPopup(modId, options)
--
-- An OnGameStart hook evaluates all registrations, groups
-- series members, builds a display queue, and shows one
-- popup at a time.
--
-- Persistence: player:getModData() with transmitModData()
-- for multiplayer sync.
--
-- Client-side only — auto-loads from 42/media/lua/client/.
---------------------------------------------------------------

require "ISUI/ISCollapsableWindow"
require "ISUI/ISRichTextPanel"
require "ISUI/ISTickBox"
require "ISUI/ISButton"

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:Popup]"

---------------------------------------------------------------
-- Layout constants
---------------------------------------------------------------

local FONT_HGT   = getTextManager():getFontHeight(UIFont.Small)
local BORDER      = 12
local TICK_HGT    = FONT_HGT + 6
local BTN_HGT     = math.max(24, FONT_HGT + 8)
local TOGGLE_HGT  = BTN_HGT + 4
local BTN_W_CLOSE = 120
local BTN_W_GUIDE = 140

-- Button colour palettes (border + background) by popup mode
local CLR_CLOSE_CHANGELOG = {
    border = { r = 0.40, g = 0.55, b = 0.80, a = 1.0  },
    bg     = { r = 0.10, g = 0.15, b = 0.25, a = 0.85 },
}
local CLR_CLOSE_NOTICE = {
    border = { r = 0.70, g = 0.55, b = 0.20, a = 1.0  },
    bg     = { r = 0.20, g = 0.15, b = 0.05, a = 0.85 },
}
local CLR_GUIDE_BTN = {
    border = { r = 0.40, g = 0.40, b = 0.40, a = 0.7  },
    bg     = { r = 0.08, g = 0.08, b = 0.10, a = 0.80 },
}

---------------------------------------------------------------
-- Registries
---------------------------------------------------------------

PhobosLib._guideRegistry     = PhobosLib._guideRegistry     or {}
PhobosLib._noticeRegistry    = PhobosLib._noticeRegistry    or {}
PhobosLib._changelogRegistry = PhobosLib._changelogRegistry or {}
PhobosLib._popupQueue        = PhobosLib._popupQueue        or {}
PhobosLib._seriesRegistry    = PhobosLib._seriesRegistry    or {}

---------------------------------------------------------------
-- Utilities
---------------------------------------------------------------

--- Extract "major.minor" from a semver string, dropping patch.
---@param version string|nil
---@return string|nil
local function getMajorMinor(version)
    if type(version) ~= "string" then return nil end
    local major, minor = string.match(version, "^(%d+)%.(%d+)")
    if major and minor then return major .. "." .. minor end
    return nil
end

local safeGetText = PhobosLib.safeGetText

---------------------------------------------------------------
-- ModData Keys
---------------------------------------------------------------

local function guideKey(modId)
    return "PhobosLib_guide_" .. modId
end

local function noticeKey(modId, noticeId)
    return "PhobosLib_notice_" .. modId .. "_" .. noticeId
end

local function changelogKey(modId)
    return "PhobosLib_changelog_" .. modId
end

---------------------------------------------------------------
-- Series Helpers
---------------------------------------------------------------

--- Ensure a series entry exists in the series registry.
--- First call with a displayName wins; subsequent calls
--- are silently ignored (load-order independent).
---@param seriesId string
---@param displayName string|nil
local function ensureSeries(seriesId, displayName)
    if not PhobosLib._seriesRegistry[seriesId] then
        PhobosLib._seriesRegistry[seriesId] = {
            displayName = displayName or seriesId,
            modIds      = {},
        }
    elseif displayName and PhobosLib._seriesRegistry[seriesId].displayName == seriesId then
        -- Upgrade from fallback to real name
        PhobosLib._seriesRegistry[seriesId].displayName = displayName
    end
end

--- Track a modId as belonging to a series.
---@param seriesId string
---@param modId string
local function trackSeriesMod(seriesId, modId)
    local sr = PhobosLib._seriesRegistry[seriesId]
    if not sr then return end
    -- Avoid duplicates (simple linear scan — tiny lists)
    for _, id in ipairs(sr.modIds) do
        if id == modId then return end
    end
    table.insert(sr.modIds, modId)
end

--- Build the window title for a series popup.
---@param seriesId string
---@param suffixKey string   Translation key for type suffix (e.g. "IGUI_PhobosLib_SeriesChangelogTitle")
---@return string
local function seriesWindowTitle(seriesId, suffixKey)
    local sr = PhobosLib._seriesRegistry[seriesId]
    local name = sr and sr.displayName or seriesId
    local suffix = safeGetText(suffixKey)
    -- em-dash separator: \226\128\148 is UTF-8 for —
    return name .. "  \226\128\148  " .. suffix
end

--- Check if ANY mod in a series has a registered guide.
---@param seriesId string
---@return boolean
local function seriesHasGuide(seriesId)
    local sr = PhobosLib._seriesRegistry[seriesId]
    if not sr then return false end
    for _, modId in ipairs(sr.modIds) do
        if PhobosLib._guideRegistry[modId] then return true end
    end
    return false
end

---------------------------------------------------------------
-- _GuideWindow — ISCollapsableWindow subclass
---------------------------------------------------------------

local _GuideWindow = ISCollapsableWindow:derive("PhobosLib_GuideWindow")

function _GuideWindow:new(x, y, w, h, registration)
    local o = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.title           = registration.title or safeGetText("IGUI_PhobosLib_GuideDefaultTitle")
    o.resizable       = false
    o.pin             = true
    o._registration   = registration
    o.backgroundColor = registration.backgroundColor
                        or { r = 0, g = 0, b = 0, a = 0.92 }
    o.borderColor     = registration.borderColor
                        or { r = 0.45, g = 0.45, b = 0.45, a = 1 }
    return o
end

function _GuideWindow:createChildren()
    PhobosLib.makeWindowResizable(self, 400, 300)
    ISCollapsableWindow.createChildren(self)

    local y = self:titleBarHeight() + BORDER
    local x = BORDER + 1
    local bottomReserve = TICK_HGT + BORDER * 3

    -- Scrollable rich-text panel
    self.richText = ISRichTextPanel:new(x, y,
        self.width - x * 2, self.height - y - bottomReserve)
    self.richText:initialise()
    self.richText:instantiate()
    self.richText:noBackground()
    self.richText.autosetheight = false
    self.richText.clip = true
    self.richText:addScrollBars()
    self.richText.backgroundColor = { r = 0, g = 0, b = 0, a = 0.25 }
    self.richText.borderColor     = { r = 1, g = 1, b = 1, a = 0.08 }
    self.richText:setAnchorRight(true)
    self.richText:setAnchorBottom(true)
    self:addChild(self.richText)

    -- Build content via callback (safe for getText at display time)
    local contentOk, content = pcall(self._registration.buildContent)
    if not contentOk then
        content = "<TEXT> <RGB:1,0.3,0.3> " .. safeGetText("IGUI_PhobosLib_ErrorBuildGuide")
                  .. tostring(content) .. " <LINE> "
    end
    self.richText.text = content or ""
    self.richText:paginate()

    -- "Don't show again" tick box
    local tickY = self.height - TICK_HGT - BORDER
    self.tickBox = ISTickBox:new(x, tickY,
        self.width - x * 2, TICK_HGT, "", self, self.onTickChanged)
    self.tickBox:initialise()
    self.tickBox:addOption(safeGetText("IGUI_PhobosLib_DontShowAgain"))
    self.tickBox:setAnchorTop(false)
    self.tickBox:setAnchorBottom(true)
    self:addChild(self.tickBox)
end

function _GuideWindow:onTickChanged(index, selected)
    -- state is read in close()
end

function _GuideWindow:close()
    local player = getPlayer()
    if player and self.tickBox and self.tickBox:isSelected(1) then
        player:getModData()[guideKey(self._registration.modId)] = true
        pcall(function() player:transmitModData() end)
    end
    self:setVisible(false)
    self:removeFromUIManager()
    PhobosLib._showNextPopup()
end

---------------------------------------------------------------
-- _ChangelogWindow — ISCollapsableWindow subclass
---------------------------------------------------------------

local _ChangelogWindow = ISCollapsableWindow:derive("PhobosLib_ChangelogWindow")

function _ChangelogWindow:new(x, y, w, h, registration)
    local o = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.title           = registration.title or safeGetText("IGUI_PhobosLib_ChangelogDefaultTitle")
    o.resizable       = false
    o.pin             = false
    o._registration   = registration
    o.backgroundColor = registration.backgroundColor
                        or { r = 0.04, g = 0.04, b = 0.06, a = 0.95 }
    o.borderColor     = registration.borderColor
                        or { r = 0.40, g = 0.55, b = 0.80, a = 1.00 }
    return o
end

function _ChangelogWindow:createChildren()
    PhobosLib.makeWindowResizable(self, 400, 300)
    ISCollapsableWindow.createChildren(self)

    local barH    = self:titleBarHeight()
    local x       = BORDER
    local y       = barH + BORDER
    local btnRowH = BTN_HGT + BORDER * 2
    local innerW  = self.width  - x * 2
    local innerH  = self.height - y - btnRowH

    -- Scrollable rich-text body
    self.richText = ISRichTextPanel:new(x, y, innerW, innerH)
    self.richText:initialise()
    self.richText:instantiate()
    self.richText:noBackground()
    self.richText.autosetheight = false
    self.richText.clip          = true
    self.richText:addScrollBars()
    self.richText.backgroundColor = { r = 0, g = 0, b = 0, a = 0.30 }
    self.richText.borderColor     = { r = 1, g = 1, b = 1, a = 0.07 }
    self.richText:setAnchorRight(true)
    self.richText:setAnchorBottom(true)
    self:addChild(self.richText)

    -- Build content via callback (pass lastSeenVersion so mod can filter)
    local contentOk, content = pcall(
        self._registration.buildContent,
        self._registration._lastSeenVersion
    )
    if not contentOk then
        content = "<TEXT> <RGB:1,0.3,0.3> " .. safeGetText("IGUI_PhobosLib_ErrorBuildChangelog")
                  .. tostring(content) .. " <LINE> "
    end
    self.richText.text = content or ""
    self.richText:paginate()

    -- "Got it!" button (centered)
    local btnY = self.height - BTN_HGT - BORDER
    local btnX = math.floor((self.width - BTN_W_CLOSE) / 2)

    self.btnClose = ISButton:new(btnX, btnY, BTN_W_CLOSE, BTN_HGT,
        safeGetText("IGUI_PhobosLib_GotIt"), self, _ChangelogWindow.onGotIt)
    self.btnClose:initialise()
    self.btnClose:instantiate()
    self.btnClose.borderColor     = CLR_CLOSE_CHANGELOG.border
    self.btnClose.backgroundColor = CLR_CLOSE_CHANGELOG.bg
    self.btnClose:setAnchorBottom(true)
    self.btnClose:setAnchorLeft(false)
    self.btnClose:setAnchorRight(false)
    self:addChild(self.btnClose)

    -- "Open Guide" button (only if a guide is registered for same modId)
    local modId = self._registration.modId
    if PhobosLib._guideRegistry[modId] then
        local tutX = self.width - BTN_W_GUIDE - BORDER
        self.btnGuide = ISButton:new(tutX, btnY, BTN_W_GUIDE, BTN_HGT,
            safeGetText("IGUI_PhobosLib_OpenGuide"),
            self, _ChangelogWindow.onOpenGuide)
        self.btnGuide:initialise()
        self.btnGuide:instantiate()
        self.btnGuide.borderColor     = CLR_GUIDE_BTN.border
        self.btnGuide.backgroundColor = CLR_GUIDE_BTN.bg
        self.btnGuide:setAnchorBottom(true)
        self.btnGuide:setAnchorLeft(false)
        self.btnGuide:setAnchorRight(false)
        self:addChild(self.btnGuide)
    end
end

function _ChangelogWindow:onGotIt()
    self:close()
end

function _ChangelogWindow:onOpenGuide()
    local modId = self._registration.modId
    local guideReg = PhobosLib._guideRegistry[modId]
    if not guideReg then return end

    -- Clear guide dismissed flag
    local player = getPlayer()
    if player then
        player:getModData()[guideKey(modId)] = nil
        pcall(function() player:transmitModData() end)
    end

    -- Close changelog (stamps version)
    self:close()

    -- Show guide on next tick (one-frame delay for clean transition)
    local function showGuide()
        PhobosLib._showGuidePopup(guideReg)
        Events.OnTick.Remove(showGuide)
    end
    Events.OnTick.Add(showGuide)
end

function _ChangelogWindow:close()
    -- Stamp current major.minor version
    local player = getPlayer()
    if player then
        local mm = getMajorMinor(self._registration.currentVersion)
        if mm then
            player:getModData()[changelogKey(self._registration.modId)] = mm
            pcall(function() player:transmitModData() end)
        end
    end
    self:setVisible(false)
    self:removeFromUIManager()
    PhobosLib._showNextPopup()
end

---------------------------------------------------------------
-- _NoticeWindow — ISCollapsableWindow subclass
-- One-time notice popup with "Got it!" button.
-- Guards via player modData key (shown once per character).
---------------------------------------------------------------

local _NoticeWindow = ISCollapsableWindow:derive("PhobosLib_NoticeWindow")

function _NoticeWindow:new(x, y, w, h, registration)
    local o = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.title           = registration.title or safeGetText("IGUI_PhobosLib_NoticeDefaultTitle")
    o.resizable       = false
    o.pin             = false
    o._registration   = registration
    o.backgroundColor = registration.backgroundColor
                        or { r = 0.04, g = 0.04, b = 0.06, a = 0.95 }
    o.borderColor     = registration.borderColor
                        or { r = 0.70, g = 0.55, b = 0.20, a = 1.00 }
    return o
end

function _NoticeWindow:createChildren()
    PhobosLib.makeWindowResizable(self, 400, 300)
    ISCollapsableWindow.createChildren(self)

    local barH    = self:titleBarHeight()
    local x       = BORDER
    local y       = barH + BORDER
    local btnRowH = BTN_HGT + BORDER * 2
    local innerW  = self.width  - x * 2
    local innerH  = self.height - y - btnRowH

    -- Scrollable rich-text body
    self.richText = ISRichTextPanel:new(x, y, innerW, innerH)
    self.richText:initialise()
    self.richText:instantiate()
    self.richText:noBackground()
    self.richText.autosetheight = false
    self.richText.clip          = true
    self.richText:addScrollBars()
    self.richText.backgroundColor = { r = 0, g = 0, b = 0, a = 0.30 }
    self.richText.borderColor     = { r = 1, g = 1, b = 1, a = 0.07 }
    self.richText:setAnchorRight(true)
    self.richText:setAnchorBottom(true)
    self:addChild(self.richText)

    -- Build content via callback
    local contentOk, content = pcall(self._registration.buildContent)
    if not contentOk then
        content = "<TEXT> <RGB:1,0.3,0.3> " .. safeGetText("IGUI_PhobosLib_ErrorBuildNotice")
                  .. tostring(content) .. " <LINE> "
    end
    self.richText.text = content or ""
    self.richText:paginate()

    -- "Got it!" button (centered)
    local btnY = self.height - BTN_HGT - BORDER
    local btnX = math.floor((self.width - BTN_W_CLOSE) / 2)

    self.btnClose = ISButton:new(btnX, btnY, BTN_W_CLOSE, BTN_HGT,
        safeGetText("IGUI_PhobosLib_GotIt"), self, _NoticeWindow.onGotIt)
    self.btnClose:initialise()
    self.btnClose:instantiate()
    self.btnClose.borderColor     = CLR_CLOSE_NOTICE.border
    self.btnClose.backgroundColor = CLR_CLOSE_NOTICE.bg
    self.btnClose:setAnchorBottom(true)
    self.btnClose:setAnchorLeft(false)
    self.btnClose:setAnchorRight(false)
    self:addChild(self.btnClose)

    -- "Open Guide" button (only if a guide is registered for same modId)
    local modId = self._registration.modId
    if PhobosLib._guideRegistry[modId] then
        local tutX = self.width - BTN_W_GUIDE - BORDER
        self.btnGuide = ISButton:new(tutX, btnY, BTN_W_GUIDE, BTN_HGT,
            safeGetText("IGUI_PhobosLib_OpenGuide"),
            self, _NoticeWindow.onOpenGuide)
        self.btnGuide:initialise()
        self.btnGuide:instantiate()
        self.btnGuide.borderColor     = CLR_GUIDE_BTN.border
        self.btnGuide.backgroundColor = CLR_GUIDE_BTN.bg
        self.btnGuide:setAnchorBottom(true)
        self.btnGuide:setAnchorLeft(false)
        self.btnGuide:setAnchorRight(false)
        self:addChild(self.btnGuide)
    end
end

function _NoticeWindow:onGotIt()
    self:close()
end

function _NoticeWindow:onOpenGuide()
    local modId = self._registration.modId
    local guideReg = PhobosLib._guideRegistry[modId]
    if not guideReg then return end

    -- Clear guide dismissed flag
    local player = getPlayer()
    if player then
        player:getModData()[guideKey(modId)] = nil
        pcall(function() player:transmitModData() end)
    end

    -- Close notice (stamps guard)
    self:close()

    -- Show guide on next tick (one-frame delay for clean transition)
    local function showGuide()
        PhobosLib._showGuidePopup(guideReg)
        Events.OnTick.Remove(showGuide)
    end
    Events.OnTick.Add(showGuide)
end

function _NoticeWindow:close()
    -- Stamp notice guard in player modData
    local player = getPlayer()
    if player then
        local key = noticeKey(self._registration.modId, self._registration._noticeId)
        player:getModData()[key] = true
        pcall(function() player:transmitModData() end)
    end
    self:setVisible(false)
    self:removeFromUIManager()
    PhobosLib._showNextPopup()
end

---------------------------------------------------------------
-- _SeriesWindow — consolidated popup for series mod groups
--
-- Supports three modes: "guide", "changelog", "notice".
-- When multiple mods are in the group, a toggle bar appears
-- at the top allowing sections to be expanded/collapsed.
-- When only one mod is in the group, the toggle bar is hidden
-- and the popup behaves identically to the standalone version.
---------------------------------------------------------------

local _SeriesWindow = ISCollapsableWindow:derive("PhobosLib_SeriesWindow")

function _SeriesWindow:new(x, y, w, h, mode, seriesId, modRegs)
    local o = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.resizable   = false
    o.pin         = (mode == "guide")
    o._mode       = mode
    o._seriesId   = seriesId
    o._modRegs    = modRegs
    o._toggleBtns = {}

    -- Title from series display name + mode suffix
    local suffixKey = "IGUI_PhobosLib_SeriesChangelogTitle"
    if mode == "guide" then
        suffixKey = "IGUI_PhobosLib_SeriesGuideTitle"
    elseif mode == "notice" then
        suffixKey = "IGUI_PhobosLib_SeriesNoticeTitle"
    end
    o.title = seriesWindowTitle(seriesId, suffixKey)

    -- Theming by mode
    if mode == "guide" then
        o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.92 }
        o.borderColor     = { r = 0.45, g = 0.45, b = 0.45, a = 1 }
    elseif mode == "notice" then
        o.backgroundColor = { r = 0.04, g = 0.04, b = 0.06, a = 0.95 }
        o.borderColor     = { r = 0.70, g = 0.55, b = 0.20, a = 1.00 }
    else -- changelog
        o.backgroundColor = { r = 0.04, g = 0.04, b = 0.06, a = 0.95 }
        o.borderColor     = { r = 0.40, g = 0.55, b = 0.80, a = 1.00 }
    end

    -- All mods start expanded
    for _, reg in ipairs(modRegs) do
        reg._expanded = true
    end

    return o
end

function _SeriesWindow:createChildren()
    PhobosLib.makeWindowResizable(self, 480, 350)
    ISCollapsableWindow.createChildren(self)

    local barH       = self:titleBarHeight()
    local x          = BORDER
    local y          = barH + BORDER
    local btnRowH    = BTN_HGT + BORDER * 2
    local showToggle = #self._modRegs > 1
    local toggleRowH = showToggle and (TOGGLE_HGT + BORDER) or 0

    -- ── Toggle bar (only for multi-mod series) ──
    if showToggle then
        local tx = x
        for i, reg in ipairs(self._modRegs) do
            local label = reg.seriesLabel or reg.modId
            if self._mode == "changelog" and reg.currentVersion then
                label = label .. " v" .. (getMajorMinor(reg.currentVersion) or "?")
            end
            local btnLabel = (reg._expanded and "\226\150\188 " or "\226\150\182 ") .. label
            local btnW = math.max(100, getTextManager():MeasureStringX(UIFont.Small, btnLabel) + 24)
            local btn = ISButton:new(tx, y, btnW, TOGGLE_HGT,
                btnLabel, self, _SeriesWindow.onToggle)
            btn:initialise()
            btn:instantiate()
            btn._regIndex = i
            if reg._expanded then
                btn.borderColor     = { r = 0.40, g = 0.70, b = 1.00, a = 0.9 }
                btn.backgroundColor = { r = 0.10, g = 0.18, b = 0.30, a = 0.85 }
            else
                btn.borderColor     = { r = 0.30, g = 0.30, b = 0.30, a = 0.6 }
                btn.backgroundColor = { r = 0.06, g = 0.06, b = 0.08, a = 0.70 }
            end
            self:addChild(btn)
            self._toggleBtns[i] = btn
            tx = tx + btnW + 6
        end
        y = y + toggleRowH
    end

    -- ── Rich-text body ──
    local innerW = self.width - x * 2

    -- Bottom reserve: button row + tick box (guide mode only)
    local bottomReserve = btnRowH
    if self._mode == "guide" then
        bottomReserve = bottomReserve + TICK_HGT + BORDER
    end

    local innerH = self.height - y - bottomReserve
    self.richText = ISRichTextPanel:new(x, y, innerW, innerH)
    self.richText:initialise()
    self.richText:instantiate()
    self.richText:noBackground()
    self.richText.autosetheight = false
    self.richText.clip          = true
    self.richText:addScrollBars()
    self.richText.backgroundColor = { r = 0, g = 0, b = 0, a = 0.25 }
    self.richText.borderColor     = { r = 1, g = 1, b = 1, a = 0.07 }
    self.richText:setAnchorRight(true)
    self.richText:setAnchorBottom(true)
    self:addChild(self.richText)

    -- Build initial content
    self:rebuildContent()

    -- ── Bottom bar ──
    local btnY = self.height - BTN_HGT - BORDER

    if self._mode == "guide" then
        -- "Don't show again" checkbox
        local tickY = btnY - TICK_HGT - BORDER
        self.tickBox = ISTickBox:new(x + 1, tickY,
            self.width - x * 2, TICK_HGT, "", self, self.onTickChanged)
        self.tickBox:initialise()
        self.tickBox:addOption(safeGetText("IGUI_PhobosLib_DontShowAgain"))
        self.tickBox:setAnchorTop(false)
        self.tickBox:setAnchorBottom(true)
        self:addChild(self.tickBox)
    else
        -- "Got it!" button (centered)
        local closeBtnX = math.floor((self.width - BTN_W_CLOSE) / 2)
        self.btnClose = ISButton:new(closeBtnX, btnY, BTN_W_CLOSE, BTN_HGT,
            safeGetText("IGUI_PhobosLib_GotIt"), self, _SeriesWindow.onGotIt)
        self.btnClose:initialise()
        self.btnClose:instantiate()
        local closeClr = (self._mode == "notice") and CLR_CLOSE_NOTICE or CLR_CLOSE_CHANGELOG
        self.btnClose.borderColor     = closeClr.border
        self.btnClose.backgroundColor = closeClr.bg
        self.btnClose:setAnchorBottom(true)
        self.btnClose:setAnchorLeft(false)
        self.btnClose:setAnchorRight(false)
        self:addChild(self.btnClose)

        -- "Open Guide" button (if any guide registered in this series)
        if seriesHasGuide(self._seriesId) then
            local tutX = self.width - BTN_W_GUIDE - BORDER
            self.btnGuide = ISButton:new(tutX, btnY, BTN_W_GUIDE, BTN_HGT,
                safeGetText("IGUI_PhobosLib_OpenGuide"),
                self, _SeriesWindow.onOpenGuide)
            self.btnGuide:initialise()
            self.btnGuide:instantiate()
            self.btnGuide.borderColor     = CLR_GUIDE_BTN.border
            self.btnGuide.backgroundColor = CLR_GUIDE_BTN.bg
            self.btnGuide:setAnchorBottom(true)
            self.btnGuide:setAnchorLeft(false)
            self.btnGuide:setAnchorRight(false)
            self:addChild(self.btnGuide)
        end
    end
end

--- Rebuild rich-text content from expanded/collapsed mod sections.
function _SeriesWindow:rebuildContent()
    local t = ""
    for i, reg in ipairs(self._modRegs) do
        -- Section divider (between sections only)
        if i > 1 then
            t = t .. "<LINE> <RGB:0.30,0.30,0.35> "
            t = t .. "\226\148\128\226\148\128\226\148\128\226\148\128"
            t = t .. "\226\148\128\226\148\128\226\148\128\226\148\128"
            t = t .. "\226\148\128\226\148\128\226\148\128\226\148\128"
            t = t .. "\226\148\128\226\148\128\226\148\128\226\148\128"
            t = t .. "\226\148\128\226\148\128\226\148\128\226\148\128"
            t = t .. "\226\148\128\226\148\128\226\148\128\226\148\128"
            t = t .. " <LINE> <LINE> "
        end

        if reg._expanded then
            -- Section header (only for multi-mod series)
            if #self._modRegs > 1 then
                t = t .. "<LEFT> <SIZE:medium> <RGB:0.50,0.85,1.00> "
                t = t .. (reg.seriesLabel or reg.modId)
                if self._mode == "changelog" and reg.currentVersion then
                    t = t .. "  v" .. (getMajorMinor(reg.currentVersion) or "?")
                end
                t = t .. " <LINE> <LINE> "
            end

            -- Mod content via callback
            local ok, content
            if self._mode == "changelog" then
                ok, content = pcall(reg.buildContent, reg._lastSeenVersion)
            else
                ok, content = pcall(reg.buildContent)
            end

            if ok and content then
                t = t .. content
            else
                t = t .. "<RGB:1,0.3,0.3> "
                t = t .. safeGetText("IGUI_PhobosLib_ErrorBuildSeries")
                t = t .. tostring(content) .. " <LINE> "
            end
        else
            -- Collapsed placeholder
            t = t .. "<LEFT> <SIZE:small> <RGB:0.40,0.40,0.45> "
            t = t .. "[ " .. (reg.seriesLabel or reg.modId)
            t = t .. " \226\128\148 " .. safeGetText("IGUI_PhobosLib_ExpandToView") .. " ] <LINE> "
        end
    end

    self.richText.text = t
    self.richText:paginate()
end

--- Toggle a mod section expanded/collapsed.
function _SeriesWindow:onToggle()
    -- ISButton passes self as the button; walk up via parent
    -- The button's _regIndex tells us which mod to toggle
    local btn = self
    local win = btn.parent
    if not win or not win._modRegs then return end

    local idx = btn._regIndex
    local reg = win._modRegs[idx]
    if not reg then return end

    reg._expanded = not reg._expanded

    -- Update button styling
    local label = reg.seriesLabel or reg.modId
    if win._mode == "changelog" and reg.currentVersion then
        label = label .. " v" .. (getMajorMinor(reg.currentVersion) or "?")
    end

    if reg._expanded then
        btn:setTitle("\226\150\188 " .. label)
        btn.borderColor     = { r = 0.40, g = 0.70, b = 1.00, a = 0.9 }
        btn.backgroundColor = { r = 0.10, g = 0.18, b = 0.30, a = 0.85 }
    else
        btn:setTitle("\226\150\182 " .. label)
        btn.borderColor     = { r = 0.30, g = 0.30, b = 0.30, a = 0.6 }
        btn.backgroundColor = { r = 0.06, g = 0.06, b = 0.08, a = 0.70 }
    end

    -- Rebuild content
    win:rebuildContent()
end

function _SeriesWindow:onTickChanged(index, selected)
    -- state is read in close()
end

function _SeriesWindow:onGotIt()
    self:close()
end

function _SeriesWindow:onOpenGuide()
    local sr = PhobosLib._seriesRegistry[self._seriesId]
    if not sr then return end

    -- Collect undismissed guide registrations for this series
    local guideRegs = {}
    local player = getPlayer()
    for _, modId in ipairs(sr.modIds) do
        local gReg = PhobosLib._guideRegistry[modId]
        if gReg then
            -- Clear guide dismissed flag so it shows again
            if player then
                player:getModData()[guideKey(modId)] = nil
            end
            table.insert(guideRegs, gReg)
        end
    end

    if player then
        pcall(function() player:transmitModData() end)
    end

    -- Close current window (stamps per-mod)
    self:close()

    if #guideRegs == 0 then return end

    -- Show series guide on next tick (one-frame delay)
    local sid = self._seriesId
    local function showGuide()
        PhobosLib._showSeriesPopup("guide", sid, guideRegs)
        Events.OnTick.Remove(showGuide)
    end
    Events.OnTick.Add(showGuide)
end

function _SeriesWindow:close()
    local player = getPlayer()
    if player then
        local md = player:getModData()

        if self._mode == "guide" then
            -- Stamp guide keys for all shown mods (only if "Don't show again" checked)
            if self.tickBox and self.tickBox:isSelected(1) then
                for _, reg in ipairs(self._modRegs) do
                    md[guideKey(reg.modId)] = true
                end
            end
        elseif self._mode == "changelog" then
            -- Stamp changelog version for ALL mods in group
            for _, reg in ipairs(self._modRegs) do
                local mm = getMajorMinor(reg.currentVersion)
                if mm then
                    md[changelogKey(reg.modId)] = mm
                end
            end
        elseif self._mode == "notice" then
            -- Stamp notice keys for ALL notices in group
            for _, reg in ipairs(self._modRegs) do
                local key = noticeKey(reg.modId, reg._noticeId)
                md[key] = true
            end
        end

        pcall(function() player:transmitModData() end)
    end

    self:setVisible(false)
    self:removeFromUIManager()
    PhobosLib._showNextPopup()
end

---------------------------------------------------------------
-- Queue System
---------------------------------------------------------------

--- Show the next popup in the queue, or do nothing if empty.
function PhobosLib._showNextPopup()
    local queue = PhobosLib._popupQueue
    if #queue == 0 then return end

    local entry = table.remove(queue, 1)

    -- Standalone popup types (backward compat)
    if entry.type == "guide" then
        PhobosLib._showGuidePopup(entry.registration)
    elseif entry.type == "notice" then
        PhobosLib._showNoticePopup(entry.registration)
    elseif entry.type == "changelog" then
        PhobosLib._showChangelogPopup(entry.registration)

    -- Series popup types
    elseif entry.type == "series_changelog" then
        PhobosLib._showSeriesPopup("changelog", entry.seriesId, entry.registrations)
    elseif entry.type == "series_notice" then
        PhobosLib._showSeriesPopup("notice", entry.seriesId, entry.registrations)
    elseif entry.type == "series_guide" then
        PhobosLib._showSeriesPopup("guide", entry.seriesId, entry.registrations)
    end
end

--- Create and display a guide popup.
---@param reg table  Guide registration
function PhobosLib._showGuidePopup(reg)
    local w = reg.width  or 560
    local h = reg.height or 600
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()

    -- Clamp to screen
    w = math.min(w, math.floor(sw * 0.90))
    h = math.min(h, math.floor(sh * 0.85))

    local popup = _GuideWindow:new(0, 0, w, h, reg)
    popup:initialise()
    popup:addToUIManager()
    popup:setVisible(true)
    popup:setX(math.floor((sw - w) / 2))
    popup:setY(math.floor((sh - h) / 2))
end

--- Create and display a changelog popup.
---@param reg table  Changelog registration
function PhobosLib._showChangelogPopup(reg)
    local w = reg.width  or 620
    local h = reg.height or 680
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()

    -- Responsive sizing (clamp to screen)
    w = math.min(w, math.floor(sw * 0.46))
    h = math.min(h, math.floor(sh * 0.75))

    local popup = _ChangelogWindow:new(0, 0, w, h, reg)
    popup:initialise()
    popup:addToUIManager()
    popup:setVisible(true)
    popup:setX(math.floor((sw - w) / 2))
    popup:setY(math.floor((sh - h) / 2))
end

--- Create and display a notice popup.
---@param reg table  Notice registration
function PhobosLib._showNoticePopup(reg)
    local w = reg.width  or 560
    local h = reg.height or 500
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()

    -- Responsive sizing (clamp to screen)
    w = math.min(w, math.floor(sw * 0.46))
    h = math.min(h, math.floor(sh * 0.75))

    local popup = _NoticeWindow:new(0, 0, w, h, reg)
    popup:initialise()
    popup:addToUIManager()
    popup:setVisible(true)
    popup:setX(math.floor((sw - w) / 2))
    popup:setY(math.floor((sh - h) / 2))
end

--- Create and display a consolidated series popup.
---@param mode     string   "guide" | "changelog" | "notice"
---@param seriesId string   Series identifier
---@param modRegs  table    Array of registration tables
function PhobosLib._showSeriesPopup(mode, seriesId, modRegs)
    if not modRegs or #modRegs == 0 then return end

    -- Single-mod series: delegate to standalone popup for identical UX
    if #modRegs == 1 then
        local reg = modRegs[1]
        if mode == "guide" then
            PhobosLib._showGuidePopup(reg)
        elseif mode == "changelog" then
            PhobosLib._showChangelogPopup(reg)
        elseif mode == "notice" then
            PhobosLib._showNoticePopup(reg)
        end
        return
    end

    -- Multi-mod series: use consolidated _SeriesWindow
    -- Compute max dimensions from all member registrations
    local w, h = 640, 700
    for _, reg in ipairs(modRegs) do
        if reg.width  and reg.width  > w then w = reg.width  end
        if reg.height and reg.height > h then h = reg.height end
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()

    -- Responsive sizing (clamp to screen)
    w = math.min(w, math.floor(sw * 0.50))
    h = math.min(h, math.floor(sh * 0.80))

    local popup = _SeriesWindow:new(0, 0, w, h, mode, seriesId, modRegs)
    popup:initialise()
    popup:addToUIManager()
    popup:setVisible(true)
    popup:setX(math.floor((sw - w) / 2))
    popup:setY(math.floor((sh - h) / 2))
end

---------------------------------------------------------------
-- OnGameStart — Evaluate registrations and build queue
---------------------------------------------------------------

local function onGameStart()
    local player = getPlayer()
    if not player then return end

    local md = player:getModData()
    local queue = {}

    -- ── Temporary holding tables for series grouping ──
    local pendingChangelogs = {}    -- { reg, reg, ... }
    local pendingNotices    = {}    -- { reg, reg, ... }
    local pendingGuides     = {}    -- { reg, reg, ... }

    -- ── Evaluate changelog registrations (first — returning players see updates immediately) ──
    for modId, reg in pairs(PhobosLib._changelogRegistry) do
        local stored    = md[changelogKey(modId)]
        local currentMM = getMajorMinor(reg.currentVersion)

        if not currentMM then
            print(_TAG .. " WARNING: invalid currentVersion for "
                  .. modId .. ": " .. tostring(reg.currentVersion))
        elseif stored == nil then
            -- Fresh install: stamp version silently, don't queue changelog
            md[changelogKey(modId)] = currentMM
            pcall(function() player:transmitModData() end)
            print(_TAG .. " changelog skipped (fresh install) for " .. modId)
        elseif stored ~= currentMM then
            -- Returning player with a version bump
            reg._lastSeenVersion = stored
            table.insert(pendingChangelogs, reg)
            print(_TAG .. " changelog pending for " .. modId
                  .. " (" .. tostring(stored) .. " -> " .. currentMM .. ")")
        end
    end

    -- ── Evaluate notice registrations ──
    for modId, notices in pairs(PhobosLib._noticeRegistry) do
        for nId, reg in pairs(notices) do
            local nKey = noticeKey(modId, nId)
            if not md[nKey] then
                local show = true
                if type(reg.shouldShow) == "function" then
                    local ok, result = pcall(reg.shouldShow, player)
                    show = ok and (result == true)
                end
                if show then
                    table.insert(pendingNotices, reg)
                    print(_TAG .. " notice pending: " .. modId .. "/" .. nId)
                end
            end
        end
    end

    -- ── Evaluate guide registrations (last — returning players see changelog first) ──
    for modId, reg in pairs(PhobosLib._guideRegistry) do
        local dismissed = md[guideKey(modId)]
        if not dismissed then
            table.insert(pendingGuides, reg)
            print(_TAG .. " guide pending for " .. modId)
        end
    end

    -- ── Group by series and enqueue ──

    -- Helper: split pending list into series groups + standalone
    local function groupBySeries(pendingList, typeName, seriesTypeName)
        local seriesGroups = {}    -- { [seriesId] = { reg, ... } }
        for _, reg in ipairs(pendingList) do
            if reg.series then
                if not seriesGroups[reg.series] then
                    seriesGroups[reg.series] = {}
                end
                table.insert(seriesGroups[reg.series], reg)
            else
                table.insert(queue, { type = typeName, registration = reg })
                print(_TAG .. " " .. typeName .. " queued (standalone): " .. reg.modId)
            end
        end
        for sid, regs in pairs(seriesGroups) do
            table.insert(queue, {
                type          = seriesTypeName,
                seriesId      = sid,
                registrations = regs,
            })
            local names = {}
            for _, r in ipairs(regs) do table.insert(names, r.modId) end
            print(_TAG .. " " .. seriesTypeName .. " queued for "
                  .. sid .. ": " .. table.concat(names, ", "))
        end
    end

    -- Changelogs first, notices second, guides last
    groupBySeries(pendingChangelogs, "changelog", "series_changelog")
    groupBySeries(pendingNotices,    "notice",    "series_notice")
    groupBySeries(pendingGuides,     "guide",     "series_guide")

    PhobosLib._popupQueue = queue

    -- Show first popup (if any)
    PhobosLib._showNextPopup()
end

Events.OnGameStart.Add(onGameStart)

---------------------------------------------------------------
-- Public API: Registration
---------------------------------------------------------------

--- Register a welcome guide popup for a mod.
---
--- The guide shows on every game start until the player
--- checks "Don't show again". Persists per-character via
--- player modData with MP sync.
---
--- Registration should happen at file load time (before
--- OnGameStart). The buildContent callback is called at
--- display time, so getText() is safe to use inside it.
---
--- Series support: set options.series to group this popup
--- with other mods in the same series into a single window.
---
---@param modId   string   Unique mod identifier (e.g. "PCP")
---@param options table    Registration options
--- options.title              string     Window title (standalone fallback)
--- options.buildContent       function() Returns rich text string
--- options.width              number     Window width  (default 560)
--- options.height             number     Window height (default 600)
--- options.backgroundColor    table      {r,g,b,a} (default dark)
--- options.borderColor        table      {r,g,b,a} (default grey)
--- options.series             string     Series ID (e.g. "PIP"); nil = standalone
--- options.seriesDisplayName  string     Human-readable series name (first wins)
--- options.seriesLabel        string     Short mod label within series (e.g. "Biomass")
function PhobosLib.registerGuidePopup(modId, options)
    if type(modId) ~= "string" or modId == "" then
        print(_TAG .. " registerGuidePopup: invalid modId")
        return
    end
    if type(options) ~= "table" or type(options.buildContent) ~= "function" then
        print(_TAG .. " registerGuidePopup: options.buildContent is required (function)")
        return
    end

    options.modId = modId

    -- Series membership
    if type(options.series) == "string" and options.series ~= "" then
        ensureSeries(options.series, options.seriesDisplayName)
        trackSeriesMod(options.series, modId)
    end

    PhobosLib._guideRegistry[modId] = options
    print(_TAG .. " guide registered for " .. modId
          .. (options.series and (" [series:" .. options.series .. "]") or ""))
end

--- Register a changelog popup for a mod.
---
--- The changelog shows once per major.minor version change.
--- Patch-level bumps (e.g. 0.23.0 -> 0.23.1) are ignored.
--- On fresh installs, the version is silently stamped and
--- no changelog is shown.
---
--- Registration should happen at file load time (before
--- OnGameStart). The buildContent callback is called at
--- display time, so getText() is safe to use inside it.
---
--- Series support: set options.series to group this popup
--- with other mods in the same series into a single window.
---
---@param modId   string   Unique mod identifier (e.g. "PCP")
---@param options table    Registration options
--- options.title              string     Window title (standalone fallback)
--- options.buildContent       function(lastSeenVersion) Returns rich text string
---                            lastSeenVersion is the "major.minor" the player last
---                            saw (e.g. "0.22"), or nil if unknown. Use this to
---                            filter which version blocks to include.
--- options.currentVersion     string     Current mod version (semver, e.g. "0.24.0")
--- options.width              number     Window width  (default 620)
--- options.height             number     Window height (default 680)
--- options.backgroundColor    table      {r,g,b,a} (default dark blue)
--- options.borderColor        table      {r,g,b,a} (default blue accent)
--- options.series             string     Series ID (e.g. "PIP"); nil = standalone
--- options.seriesDisplayName  string     Human-readable series name (first wins)
--- options.seriesLabel        string     Short mod label within series (e.g. "Biomass")
function PhobosLib.registerChangelogPopup(modId, options)
    if type(modId) ~= "string" or modId == "" then
        print(_TAG .. " registerChangelogPopup: invalid modId")
        return
    end
    if type(options) ~= "table" or type(options.buildContent) ~= "function" then
        print(_TAG .. " registerChangelogPopup: options.buildContent is required (function)")
        return
    end
    if type(options.currentVersion) ~= "string" then
        print(_TAG .. " registerChangelogPopup: options.currentVersion is required (string)")
        return
    end

    options.modId = modId

    -- Series membership
    if type(options.series) == "string" and options.series ~= "" then
        ensureSeries(options.series, options.seriesDisplayName)
        trackSeriesMod(options.series, modId)
    end

    PhobosLib._changelogRegistry[modId] = options
    print(_TAG .. " changelog registered for " .. modId
          .. " (v" .. options.currentVersion .. ")"
          .. (options.series and (" [series:" .. options.series .. "]") or ""))
end

--- Register a one-time notice popup for a mod.
---
--- Notice popups show once per character. They are intended for
--- migration announcements, setting changes, or important one-time
--- messages. Dismissed with "Got it!" and never shown again.
---
--- An optional shouldShow(player) callback can gate display based
--- on runtime conditions (e.g. world modData flags, admin checks).
---
--- Registration should happen at file load time (before
--- OnGameStart). The buildContent callback is called at display
--- time, so getText() is safe to use inside it.
---
--- Series support: set options.series to group this popup
--- with other mods in the same series into a single window.
---
---@param modId    string   Unique mod identifier (e.g. "PCP")
---@param noticeId string   Unique notice identifier (e.g. "impurity_enabled")
---@param options  table    Registration options
--- options.title              string              Window title (standalone fallback)
--- options.buildContent       function()           Returns rich text string
--- options.shouldShow         function(player)     Optional condition (default: always show)
--- options.width              number               Window width  (default 560)
--- options.height             number               Window height (default 500)
--- options.backgroundColor    table                {r,g,b,a} (default dark)
--- options.borderColor        table                {r,g,b,a} (default amber)
--- options.series             string               Series ID (e.g. "PIP"); nil = standalone
--- options.seriesDisplayName  string               Human-readable series name (first wins)
--- options.seriesLabel        string               Short mod label within series (e.g. "Biomass")
function PhobosLib.registerNoticePopup(modId, noticeId, options)
    if type(modId) ~= "string" or modId == "" then
        print(_TAG .. " registerNoticePopup: invalid modId")
        return
    end
    if type(noticeId) ~= "string" or noticeId == "" then
        print(_TAG .. " registerNoticePopup: invalid noticeId")
        return
    end
    if type(options) ~= "table" or type(options.buildContent) ~= "function" then
        print(_TAG .. " registerNoticePopup: options.buildContent is required (function)")
        return
    end

    options.modId = modId
    options._noticeId = noticeId

    -- Series membership
    if type(options.series) == "string" and options.series ~= "" then
        ensureSeries(options.series, options.seriesDisplayName)
        trackSeriesMod(options.series, modId)
    end

    if not PhobosLib._noticeRegistry[modId] then
        PhobosLib._noticeRegistry[modId] = {}
    end
    PhobosLib._noticeRegistry[modId][noticeId] = options
    print(_TAG .. " notice registered: " .. modId .. "/" .. noticeId
          .. (options.series and (" [series:" .. options.series .. "]") or ""))
end

---------------------------------------------------------------
-- Window utility
---------------------------------------------------------------

--- Enable native ISCollapsableWindow resizing on a Phobos window.
--- Skips setup if "Resize Any Window" mod is active (it handles all windows globally).
--- Must be called BEFORE ISCollapsableWindow.createChildren(self) so the
--- resize widgets are created during the parent call.
---@param window table  The ISCollapsableWindow instance
---@param minWidth number  Minimum width in pixels (default 300)
---@param minHeight number  Minimum height in pixels (default 200)
function PhobosLib.makeWindowResizable(window, minWidth, minHeight)
    if getActivatedMods():contains("ZResizeAnyWindow") then return end
    window.resizable = true
    window.minimumWidth = minWidth or 300
    window.minimumHeight = minHeight or 200
end

---------------------------------------------------------------

print(_TAG .. " loaded [client]")
