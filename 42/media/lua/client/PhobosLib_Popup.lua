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
-- Provides two popup types:
--   1. Guide  — first-time tutorial/introduction with
--               "Don't show again" checkbox
--   2. Changelog — version-based "What's New" popup
--               that fires on major/minor version bumps
--
-- Mods register popups at file load time via:
--   PhobosLib.registerGuidePopup(modId, options)
--   PhobosLib.registerChangelogPopup(modId, options)
--
-- An OnGameStart hook evaluates all registrations, builds
-- a display queue (guides first, then changelogs), and shows
-- one popup at a time.
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

local FONT_HGT = getTextManager():getFontHeight(UIFont.Small)
local BORDER   = 12
local TICK_HGT = FONT_HGT + 6
local BTN_HGT  = math.max(24, FONT_HGT + 8)

---------------------------------------------------------------
-- Registries
---------------------------------------------------------------

PhobosLib._guideRegistry     = PhobosLib._guideRegistry     or {}
PhobosLib._changelogRegistry = PhobosLib._changelogRegistry or {}
PhobosLib._popupQueue        = PhobosLib._popupQueue        or {}

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

--- Get the translated text for a key, falling back to raw key.
---@param key string
---@return string
local function safeGetText(key)
    local ok, result = pcall(getText, key)
    if ok and result then return result end
    return key
end

---------------------------------------------------------------
-- ModData Keys
---------------------------------------------------------------

local function guideKey(modId)
    return "PhobosLib_guide_" .. modId
end

local function changelogKey(modId)
    return "PhobosLib_changelog_" .. modId
end

---------------------------------------------------------------
-- _GuideWindow — ISCollapsableWindow subclass
---------------------------------------------------------------

local _GuideWindow = ISCollapsableWindow:derive("PhobosLib_GuideWindow")

function _GuideWindow:new(x, y, w, h, registration)
    local o = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.title           = registration.title or "Quick Guide"
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
    self:addChild(self.richText)

    -- Build content via callback (safe for getText at display time)
    local contentOk, content = pcall(self._registration.buildContent)
    if not contentOk then
        content = "<TEXT> <RGB:1,0.3,0.3> Error building guide content: "
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
    o.title           = registration.title or "What's New"
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
    self:addChild(self.richText)

    -- Build content via callback (pass lastSeenVersion so mod can filter)
    local contentOk, content = pcall(
        self._registration.buildContent,
        self._registration._lastSeenVersion
    )
    if not contentOk then
        content = "<TEXT> <RGB:1,0.3,0.3> Error building changelog content: "
                  .. tostring(content) .. " <LINE> "
    end
    self.richText.text = content or ""
    self.richText:paginate()

    -- "Got it!" button (centered)
    local btnW = 120
    local btnY = self.height - BTN_HGT - BORDER
    local btnX = math.floor((self.width - btnW) / 2)

    self.btnClose = ISButton:new(btnX, btnY, btnW, BTN_HGT,
        safeGetText("IGUI_PhobosLib_GotIt"), self, _ChangelogWindow.onGotIt)
    self.btnClose:initialise()
    self.btnClose:instantiate()
    self.btnClose.borderColor     = { r = 0.40, g = 0.55, b = 0.80, a = 1.0 }
    self.btnClose.backgroundColor = { r = 0.10, g = 0.15, b = 0.25, a = 0.85 }
    self.btnClose:setAnchorBottom(true)
    self.btnClose:setAnchorLeft(false)
    self.btnClose:setAnchorRight(false)
    self:addChild(self.btnClose)

    -- "Open Guide" button (only if a guide is registered for same modId)
    local modId = self._registration.modId
    if PhobosLib._guideRegistry[modId] then
        local tutW = 140
        local tutX = self.width - tutW - BORDER
        self.btnGuide = ISButton:new(tutX, btnY, tutW, BTN_HGT,
            safeGetText("IGUI_PhobosLib_OpenGuide"),
            self, _ChangelogWindow.onOpenGuide)
        self.btnGuide:initialise()
        self.btnGuide:instantiate()
        self.btnGuide.borderColor     = { r = 0.40, g = 0.40, b = 0.40, a = 0.7 }
        self.btnGuide.backgroundColor = { r = 0.08, g = 0.08, b = 0.10, a = 0.80 }
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
-- Queue System
---------------------------------------------------------------

--- Show the next popup in the queue, or do nothing if empty.
function PhobosLib._showNextPopup()
    local queue = PhobosLib._popupQueue
    if #queue == 0 then return end

    local entry = table.remove(queue, 1)
    if entry.type == "guide" then
        PhobosLib._showGuidePopup(entry.registration)
    elseif entry.type == "changelog" then
        PhobosLib._showChangelogPopup(entry.registration)
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

---------------------------------------------------------------
-- OnGameStart — Evaluate registrations and build queue
---------------------------------------------------------------

local function onGameStart()
    local player = getPlayer()
    if not player then return end

    local md = player:getModData()
    local queue = {}

    -- ── Evaluate guide registrations ──
    for modId, reg in pairs(PhobosLib._guideRegistry) do
        local dismissed = md[guideKey(modId)]
        if not dismissed then
            table.insert(queue, { type = "guide", registration = reg })
            print(_TAG .. " guide queued for " .. modId)
        end
    end

    -- ── Evaluate changelog registrations ──
    for modId, reg in pairs(PhobosLib._changelogRegistry) do
        local stored    = md[changelogKey(modId)]
        local currentMM = getMajorMinor(reg.currentVersion)

        if not currentMM then
            print(_TAG .. " WARNING: invalid currentVersion for "
                  .. modId .. ": " .. tostring(reg.currentVersion))
        elseif stored == nil then
            -- Fresh install: stamp current version, skip changelog
            md[changelogKey(modId)] = currentMM
            pcall(function() player:transmitModData() end)
            print(_TAG .. " changelog stamped " .. currentMM
                  .. " for " .. modId .. " (fresh install)")
        elseif stored ~= currentMM then
            -- Version bump: show changelog (pass last-seen version for filtering)
            reg._lastSeenVersion = stored
            table.insert(queue, { type = "changelog", registration = reg })
            print(_TAG .. " changelog queued for " .. modId
                  .. " (" .. stored .. " -> " .. currentMM .. ")")
        end
    end

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
---@param modId   string   Unique mod identifier (e.g. "PCP")
---@param options table    Registration options
--- options.title           string     Window title
--- options.buildContent    function() Returns rich text string
--- options.width           number     Window width  (default 560)
--- options.height          number     Window height (default 600)
--- options.backgroundColor table      {r,g,b,a} (default dark)
--- options.borderColor     table      {r,g,b,a} (default grey)
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
    PhobosLib._guideRegistry[modId] = options
    print(_TAG .. " guide registered for " .. modId)
end

--- Register a changelog popup for a mod.
---
--- The changelog shows once per major.minor version change.
--- Patch-level bumps (e.g. 0.23.0 -> 0.23.1) are ignored.
--- On fresh installs, the current version is stamped without
--- showing the changelog.
---
--- Registration should happen at file load time (before
--- OnGameStart). The buildContent callback is called at
--- display time, so getText() is safe to use inside it.
---
---@param modId   string   Unique mod identifier (e.g. "PCP")
---@param options table    Registration options
--- options.title           string     Window title
--- options.buildContent    function(lastSeenVersion) Returns rich text string
---                         lastSeenVersion is the "major.minor" the player last
---                         saw (e.g. "0.22"), or nil if unknown. Use this to
---                         filter which version blocks to include.
--- options.currentVersion  string     Current mod version (semver, e.g. "0.24.0")
--- options.width           number     Window width  (default 620)
--- options.height          number     Window height (default 680)
--- options.backgroundColor table      {r,g,b,a} (default dark blue)
--- options.borderColor     table      {r,g,b,a} (default blue accent)
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
    PhobosLib._changelogRegistry[modId] = options
    print(_TAG .. " changelog registered for " .. modId
          .. " (v" .. options.currentVersion .. ")")
end

---------------------------------------------------------------

print(_TAG .. " loaded [client]")
