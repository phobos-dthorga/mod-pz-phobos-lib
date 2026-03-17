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
-- PhobosLib_WorldContainer.lua
-- World container iteration utilities for scanning items in
-- all loaded cells (world objects + vehicles).
-- Used by save migration systems that need to convert items
-- stored in fridges, crates, shelves, vehicle gloveboxes, etc.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:WorldContainer]"

---------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------

--- Iterate items in a single container and call fn(item, container, source).
---@param container any ItemContainer
---@param fn function callback(item, container, source)
---@param source string "world" or "vehicle"
---@return number count  number of items visited
local function iterateContainer(container, fn, source)
    local count = 0
    local ok, items = pcall(function() return container:getItems() end)
    if not ok or not items then return 0 end

    local ok2, size = pcall(function() return items:size() end)
    if not ok2 or not size or size == 0 then return 0 end

    for i = 0, size - 1 do
        local itemOk, item = pcall(function() return items:get(i) end)
        if itemOk and item then
            pcall(function() fn(item, container, source) end)
            count = count + 1
        end
    end
    return count
end

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------

--- Iterate ALL items in world containers across all loaded cells.
--- Scans every IsoObject with a container on every loaded grid square,
--- plus all vehicle part containers in loaded cells.
---
--- The callback receives (item, container, source) where source is
--- "world" for objects on grid squares or "vehicle" for vehicle parts.
---
--- NOTE: Only loaded cells/chunks are scanned.  Items in unvisited
--- far-away chunks are unreachable and remain untouched.
---
---@param fn function  callback(item, container, source)
---@return number totalItems  total items visited across all containers
function PhobosLib.iterateWorldContainers(fn)
    if not fn then return 0 end

    local cell = getCell()
    if not cell then
        print(_TAG .. " no cell loaded, skipping world container scan")
        return 0
    end

    local totalItems = 0
    local containersScanned = 0

    -- Phase 1: Grid square objects (loaded chunks)
    local minX, maxX, minY, maxY
    pcall(function()
        minX = cell:getMinX()
        maxX = cell:getMaxX()
        minY = cell:getMinY()
        maxY = cell:getMaxY()
    end)

    if minX and maxX and minY and maxY then
        -- IsoCell min/max are in world-coordinate squares (not chunk coords)
        -- Iterate every square across 8 floors (0-7)
        for x = minX, maxX do
            for y = minY, maxY do
                for z = 0, 7 do
                    local sqOk, sq = pcall(function()
                        return cell:getGridSquare(x, y, z)
                    end)
                    if sqOk and sq then
                        local objOk, objects = pcall(function()
                            return sq:getObjects()
                        end)
                        if objOk and objects then
                            local sizeOk, objSize = pcall(function()
                                return objects:size()
                            end)
                            if sizeOk and objSize and objSize > 0 then
                                for i = 0, objSize - 1 do
                                    local getOk, obj = pcall(function()
                                        return objects:get(i)
                                    end)
                                    if getOk and obj then
                                        local contOk, container = pcall(function()
                                            return obj:getContainer()
                                        end)
                                        if contOk and container then
                                            containersScanned = containersScanned + 1
                                            totalItems = totalItems
                                                + iterateContainer(container, fn, "world")
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Phase 2: Vehicle containers
    local vehOk, vehicles = pcall(function() return cell:getVehicles() end)
    if vehOk and vehicles then
        local vehSizeOk, vehSize = pcall(function() return vehicles:size() end)
        if vehSizeOk and vehSize and vehSize > 0 then
            for v = 0, vehSize - 1 do
                local getVehOk, vehicle = pcall(function()
                    return vehicles:get(v)
                end)
                if getVehOk and vehicle then
                    local partCountOk, partCount = pcall(function()
                        return vehicle:getPartCount()
                    end)
                    if partCountOk and partCount and partCount > 0 then
                        for p = 0, partCount - 1 do
                            local partOk, part = pcall(function()
                                return vehicle:getPartByIndex(p)
                            end)
                            if partOk and part then
                                local pContOk, pContainer = pcall(function()
                                    return part:getItemContainer()
                                end)
                                if pContOk and pContainer then
                                    containersScanned = containersScanned + 1
                                    totalItems = totalItems
                                        + iterateContainer(pContainer, fn, "vehicle")
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    print(_TAG .. " scanned " .. containersScanned .. " containers, "
        .. totalItems .. " items visited")
    return totalItems
end
