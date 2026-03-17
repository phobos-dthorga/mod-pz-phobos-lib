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
-- PhobosLib_NPCNames.lua
-- Procedural NPC name generation for Phobos PZ mods.
-- Produces display names (e.g. "J. Morrison") and BBS-style
-- handles (e.g. "jmorrison_42"). Useful for any mod needing
-- procedurally generated NPC identities.
-- Part of PhobosLib — shared by all Phobos PZ mods.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:NPCNames]"

--- Pool of first names (diverse, gender-neutral mix).
local FIRST_NAMES = {
    "Aaron",   "Alex",    "Blake",   "Carmen",  "Carlos",
    "Casey",   "Dana",    "Diana",   "Eli",     "Elena",
    "Frank",   "Grace",   "Hana",    "Ivan",    "Jade",
    "Jordan",  "Kai",     "Lena",    "Marcus",  "Morgan",
    "Nadia",   "Omar",    "Pat",     "Quinn",   "Ray",
    "Reese",   "Sam",     "Sandra",  "Tao",     "Tyler",
    "Uma",     "Val",     "Victor",  "Wren",    "Xander",
    "Yara",    "Zane",    "Avery",   "Devon",   "Harper",
    "Kit",     "Logan",   "Mika",    "Noel",    "Robin",
}

--- Pool of last names (diverse ethnic backgrounds).
local LAST_NAMES = {
    "Morrison", "Chen",     "Kowalski", "Reeves",   "Santos",
    "Kim",      "O'Brien",  "Weber",    "Novak",    "Torres",
    "Petrov",   "Larsson",  "Nakamura", "Graves",   "Walsh",
    "Duarte",   "Hartmann", "Cho",      "Russo",    "Lindgren",
    "Abbas",    "Patel",    "Okafor",   "Bergman",  "Salazar",
    "Kovacs",   "Freeman",  "Tanaka",   "Moreau",   "Eriksson",
    "Vance",    "Ortega",   "Singh",    "Ngo",      "Holden",
    "Bassi",    "Kruger",   "Mendez",   "Tran",     "Volkov",
    "Kapoor",   "Jensen",   "Costa",    "Watts",    "Yamazaki",
}

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------

--- Generate a random NPC name with display name and handle.
---@return table { displayName, handle, firstName, lastName }
function PhobosLib.generateNPCName()
    local first = FIRST_NAMES[ZombRand(#FIRST_NAMES) + 1]
    local last  = LAST_NAMES[ZombRand(#LAST_NAMES) + 1]

    local initial = string.sub(first, 1, 1)
    local displayName = initial .. ". " .. last

    -- BBS handle: lowercase initial + cleaned surname + random digits
    local cleanLast = string.gsub(string.lower(last), "[^%a]", "")
    local handle = string.lower(initial) .. cleanLast .. "_" .. ZombRand(100)

    return {
        displayName = displayName,
        handle      = handle,
        firstName   = first,
        lastName    = last,
    }
end

---------------------------------------------------------------

print(_TAG .. " loaded [shared]")
