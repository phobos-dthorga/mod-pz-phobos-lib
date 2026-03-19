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
-- PhobosLib_Notify.lua
-- Unified notification helper that tries PhobosNotifications
-- toast first, then falls back to PhobosLib.say().
--
-- Usage:
--   PhobosLib.notifyOrSay(player, {
--       title   = "Action Complete",
--       message = "Uploaded 3 notes.",
--       icon    = "Base.Notebook",
--       colour  = "success",
--       channel = "MyMod",
--   })
---------------------------------------------------------------

--- Try PhobosNotifications toast first, fall back to PhobosLib.say().
--- @param player any IsoPlayer (required for say fallback)
--- @param opts table Notification options
---   opts.title    (string|nil)  Bold header line (PN toast title)
---   opts.message  (string)      Body text (required)
---   opts.icon     (string|nil)  Item fullType or texture path
---   opts.colour   (string|nil)  PN preset: "info"/"success"/"warning"/"error" (default "info")
---   opts.priority (string|nil)  PN priority: "low"/"normal"/"high"/"critical"
---   opts.channel  (string|nil)  PN channel ID for filtering
---   opts.duration (number|nil)  Seconds to display (PN override)
---   opts.sound    (string|nil)  PZ sound name to play on show
--- @return string|nil Notification ID from PN, or nil if fallback used
function PhobosLib.notifyOrSay(player, opts)
    if not opts or not opts.message then return nil end

    -- Try PhobosNotifications if available
    if PhobosNotifications and PhobosNotifications.toast then
        return PhobosNotifications.toast(opts)
    end

    -- Fallback: overhead speech bubble via PhobosLib.say()
    local fallback = (opts.title and (opts.title .. ": ") or "") .. opts.message
    PhobosLib.say(player, fallback)
    return nil
end
