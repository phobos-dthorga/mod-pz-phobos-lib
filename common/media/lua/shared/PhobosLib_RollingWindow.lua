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
-- PhobosLib_RollingWindow.lua
-- Generic rolling window and array trimming utilities.
--
-- Provides capped array management for any table of records
-- with count-based or age-based trimming. Used by POSnet
-- (observations, rolling closes, events, alerts), PCP
-- (fermentation tracking), and PIP (specimen history).
---------------------------------------------------------------

--- Trim an array to at most maxCount entries by removing oldest (index 1).
---
--- @param arr table Array to trim (modified in-place)
--- @param maxCount number Maximum number of entries to retain
--- @return number Count of entries removed
function PhobosLib.trimArray(arr, maxCount)
    if not arr or type(arr) ~= "table" then return 0 end
    -- Count using pairs() for ModData compat (# crashes on Java tables)
    local count = 0
    local maxIdx = 0
    for k, _ in pairs(arr) do
        if type(k) == "number" then
            count = count + 1
            if k > maxIdx then maxIdx = k end
        end
    end
    if count <= maxCount then return 0 end
    -- Rebuild: keep only the last maxCount entries (by highest indices)
    local sorted = {}
    for k, v in pairs(arr) do
        if type(k) == "number" and type(v) == "table" then
            sorted[#sorted + 1] = { idx = k, val = v }
        end
    end
    table.sort(sorted, function(a, b) return a.idx < b.idx end)
    -- Remove oldest entries
    local toRemove = count - maxCount
    local removed = 0
    for i = 1, toRemove do
        if sorted[i] then
            arr[sorted[i].idx] = nil
            removed = removed + 1
        end
    end
    -- Reindex to sequential keys (1..N)
    local reindexed = {}
    local newIdx = 1
    for i = toRemove + 1, #sorted do
        if sorted[i] then
            reindexed[newIdx] = sorted[i].val
            newIdx = newIdx + 1
        end
    end
    -- Clear and rewrite
    for k, _ in pairs(arr) do
        if type(k) == "number" then arr[k] = nil end
    end
    for k, v in pairs(reindexed) do arr[k] = v end
    return removed
end

--- Append a value to an array and trim to maxCount entries.
---
--- Oldest entries (index 1) are removed first when the cap is exceeded.
--- This is the standard pattern for capped rolling windows:
--- observations, price closes, event logs, player alerts, etc.
---
--- @param arr table Array to append to (modified in-place)
--- @param value any Value to append
--- @param maxCount number Maximum number of entries to retain after append
--- @return number Count of entries removed by trimming
function PhobosLib.pushRolling(arr, value, maxCount)
    if not arr or type(arr) ~= "table" then return 0 end
    -- Append using pairs() count for ModData compat (# crashes on Java tables)
    local maxIdx = 0
    for k, _ in pairs(arr) do
        if type(k) == "number" and k > maxIdx then maxIdx = k end
    end
    arr[maxIdx + 1] = value
    return PhobosLib.trimArray(arr, maxCount)
end

--- Remove entries from an array where the age exceeds maxAgeDays.
---
--- Age is calculated as: currentDay - entry[dayField].
--- Entries without the dayField or with non-numeric values are removed.
---
--- @param arr table Array to trim (modified in-place)
--- @param dayField string Key name on each entry containing the day number
--- @param maxAgeDays number Maximum age in days before an entry is removed
--- @param currentDay number The current game day for age calculation
--- @return number Count of entries removed
function PhobosLib.trimByAge(arr, dayField, maxAgeDays, currentDay)
    if not arr or type(arr) ~= "table" then return 0 end
    if not dayField or not currentDay then return 0 end

    local removed = 0
    local i = 1
    while i <= #arr do
        local entry = arr[i]
        local entryDay = entry and entry[dayField]
        if type(entryDay) ~= "number" or (currentDay - entryDay) > maxAgeDays then
            table.remove(arr, i)
            removed = removed + 1
        else
            i = i + 1
        end
    end
    return removed
end
