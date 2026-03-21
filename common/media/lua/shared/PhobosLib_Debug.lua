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

--[[
    PhobosLib_Debug.lua — Centralised debug logging for Phobos PZ mods

    Provides a sandbox-gated debug logging system that works independently
    of PZ's -debug launch flag. Each mod has its own EnableDebugLogging
    sandbox boolean. Three log levels:

      INFO:  Always printed (existing unconditional print() calls).
             Not managed by this module — just use print().
      DEBUG: Printed when SandboxVars.<modId>.EnableDebugLogging = true.
             Useful for troubleshooting: config values, feature gates,
             callback entry/exit, calculation parameters.
      TRACE: Printed when sandbox debug is ON *and* PZ's -debug flag is
             active. Very verbose: per-tick, per-item iteration detail.
             Developers only.

    Before OnGameStart, sandbox vars are unavailable. Calls to debug() and
    trace() are buffered and flushed (or discarded) once the sandbox state
    is known.

    API:
      PhobosLib.isDebugEnabled(modId)    — true if sandbox debug ON
      PhobosLib.isTraceEnabled(modId)    — true if debug ON + PZ -debug
      PhobosLib.debug(modId, tag, msg)   — conditional DEBUG print
      PhobosLib.trace(modId, tag, msg)   — conditional TRACE print
      PhobosLib.isStrictMode()           — true if strict mode enabled
      PhobosLib.safecall(fn, ...)        — pcall or direct call based on mode
      PhobosLib.safeMethodCall(obj, m, ..)— method call variant

    Requires: PhobosLib (namespace must already exist)
    Part of PhobosLib >= 1.17.0
]]

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:Debug]"

-- ─── Internal State ──────────────────────────────────────────────────────
local _isReady     = false     -- true after OnGameStart
local _bootBuffer  = {}        -- { { modId, level, tag, msg }, ... }
local _enableCache = {}        -- { [modId] = bool }  (lazy, cleared on game start)
local _pzDebug     = nil       -- cached getDebug() result
local _strictMode  = false     -- cached; set on OnGameStart


-- ─── Public API ──────────────────────────────────────────────────────────

--- Check if debug logging is enabled for a given mod.
--- Reads SandboxVars.<modId>.EnableDebugLogging via PhobosLib.getSandboxVar().
--- Results are cached after first read (sandbox vars don't change mid-session).
---@param modId string  Mod namespace (e.g. "PhobosLib", "PCP")
---@return boolean
function PhobosLib.isDebugEnabled(modId)
    if not _isReady then return false end
    if _enableCache[modId] ~= nil then return _enableCache[modId] end
    local enabled = PhobosLib.getSandboxVar(modId, "EnableDebugLogging", false) == true
    _enableCache[modId] = enabled
    return enabled
end

--- Check if TRACE level is active for a given mod.
--- Requires both the sandbox debug toggle AND PZ's -debug flag.
---@param modId string
---@return boolean
function PhobosLib.isTraceEnabled(modId)
    if not PhobosLib.isDebugEnabled(modId) then return false end
    if _pzDebug == nil then
        local ok, val = pcall(getDebug)
        _pzDebug = (ok and val == true) or false
    end
    return _pzDebug
end

--- Log a DEBUG-level message.
--- Only prints when EnableDebugLogging is ON for this mod.
--- Before OnGameStart, messages are buffered and flushed/discarded later.
---@param modId string   Mod namespace (e.g. "PhobosLib", "PCP")
---@param tag   string   Module tag   (e.g. "[PhobosLib:Power]")
---@param msg   string   Log message
function PhobosLib.debug(modId, tag, msg)
    if not _isReady then
        table.insert(_bootBuffer, { modId = modId, level = "DEBUG", tag = tag, msg = msg })
        return
    end
    if PhobosLib.isDebugEnabled(modId) then
        print(tag .. " [DEBUG] " .. msg)
    end
end

--- Log a TRACE-level message.
--- Only prints when sandbox debug is ON *and* PZ's -debug flag is active.
--- Before OnGameStart, messages are buffered and flushed/discarded later.
---@param modId string
---@param tag   string
---@param msg   string
function PhobosLib.trace(modId, tag, msg)
    if not _isReady then
        table.insert(_bootBuffer, { modId = modId, level = "TRACE", tag = tag, msg = msg })
        return
    end
    if PhobosLib.isTraceEnabled(modId) then
        print(tag .. " [TRACE] " .. msg)
    end
end


-- ─── Strict Mode ───────────────────────────────────────────────────────
-- Strict mode bypasses DEFENSIVE pcalls so errors propagate with full
-- stack traces. NECESSARY pcalls (API probing) are never affected.
-- Controlled by sandbox option PhobosLib.EnableStrictMode.

--- Check if strict mode is enabled (defensive pcalls bypassed).
---@return boolean
function PhobosLib.isStrictMode()
    return _strictMode
end

--- Strict-mode-aware pcall replacement for DEFENSIVE wrapping.
--- Normal mode: behaves exactly like pcall(fn, ...).
--- Strict mode: calls fn(...) directly — errors propagate with full
--- stack traces. Returns true + results to match pcall's return signature.
---
--- Use this for defensive pcalls. Keep raw pcall() for API probing.
---@param fn function  Function to call
---@return boolean ok, any ...
function PhobosLib.safecall(fn, ...)
    if _strictMode then
        return true, fn(...)
    end
    return pcall(fn, ...)
end

--- Strict-mode-aware method call for DEFENSIVE wrapping.
--- Like pcallMethod but bypassed in strict mode. Keep pcallMethod for
--- API probing (probeMethod/probeMethodAny).
---@param obj any           Object to call the method on
---@param methodName string Method name
---@return boolean ok, any result
function PhobosLib.safeMethodCall(obj, methodName, ...)
    if not obj or not obj[methodName] then return false, nil end
    local method = obj[methodName]
    if _strictMode then
        return true, method(obj, ...)
    end
    local args = {...}
    return pcall(function()
        return method(obj, unpack(args))
    end)
end


-- ─── Boot Buffer Flush ──────────────────────────────────────────────────

--- OnGameStart handler: flush or discard the boot buffer, then log state.
local function _onGameStartDebug()
    _isReady     = true
    _enableCache = {}     -- force fresh read from sandbox
    _pzDebug     = nil

    -- Strict mode: bypass defensive pcalls for better stack traces
    _strictMode = PhobosLib.getSandboxVar("PhobosLib", "EnableStrictMode", false) == true
    if _strictMode then
        print(_TAG .. " *** STRICT MODE ENABLED — defensive pcalls BYPASSED ***")
        print(_TAG .. " *** Errors will propagate with full stack traces ***")
    end

    -- Flush buffered messages
    for _, entry in ipairs(_bootBuffer) do
        local shouldPrint = false
        if entry.level == "DEBUG" then
            shouldPrint = PhobosLib.isDebugEnabled(entry.modId)
        elseif entry.level == "TRACE" then
            shouldPrint = PhobosLib.isTraceEnabled(entry.modId)
        end
        if shouldPrint then
            print(entry.tag .. " [" .. entry.level .. "] (boot) " .. entry.msg)
        end
    end
    _bootBuffer = {}

    -- Self-report: log which mods have debug enabled
    for modId, enabled in pairs(_enableCache) do
        if enabled then
            print(_TAG .. " Debug logging ENABLED for " .. modId)
            if PhobosLib.isTraceEnabled(modId) then
                print(_TAG .. " TRACE logging ENABLED for " .. modId .. " (PZ -debug flag detected)")
            end
        end
    end
end

Events.OnGameStart.Add(_onGameStartDebug)

print(_TAG .. " Debug logging module loaded")
