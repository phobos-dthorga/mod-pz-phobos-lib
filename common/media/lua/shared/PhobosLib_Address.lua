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
-- PhobosLib_Address.lua
-- Street address resolution with three-tier data fallback:
--
-- 1. PhobosLib_StreetData — 1,087 hardcoded Knox County
--    segments (primary; richest coverage of all vanilla towns)
-- 2. streets.xml — parsed from all loaded map directories
--    (catches mod-added map packs like Raven Creek, Greenport)
-- 3. Raw coordinates — returned when no data covers the area
--
-- Spatial grid indexing for fast queries. Deterministic house
-- numbers. Intersection detection.
---------------------------------------------------------------

PhobosLib_Address = {}

---------------------------------------------------------------
-- Internal state
---------------------------------------------------------------

local streets = nil      -- array of { name, segments = { {x1,y1,x2,y2}, ... } }
local gridIndex = nil    -- [cellKey] = { streetIndex, ... }
local loaded = false

local CELL_SIZE = 200    -- spatial grid cell size (tiles)
local MAX_SEARCH_DIST = 50  -- max distance for nearest street query

---------------------------------------------------------------
-- Geometry
---------------------------------------------------------------

--- Squared distance from point to line segment.
--- Avoids sqrt for performance; use for comparisons.
---@param px number Point X
---@param py number Point Y
---@param x1 number Segment start X
---@param y1 number Segment start Y
---@param x2 number Segment end X
---@param y2 number Segment end Y
---@return number Squared distance
local function pointToSegmentDistSq(px, py, x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local lenSq = dx * dx + dy * dy

    if lenSq == 0 then
        local ddx = px - x1
        local ddy = py - y1
        return ddx * ddx + ddy * ddy
    end

    local t = ((px - x1) * dx + (py - y1) * dy) / lenSq
    if t < 0 then t = 0 elseif t > 1 then t = 1 end

    local projX = x1 + t * dx
    local projY = y1 + t * dy
    local ddx = px - projX
    local ddy = py - projY
    return ddx * ddx + ddy * ddy
end

---------------------------------------------------------------
-- Spatial grid
---------------------------------------------------------------

local function cellKey(cx, cy)
    return cx .. "," .. cy
end

local function worldToCell(wx, wy)
    return math.floor(wx / CELL_SIZE), math.floor(wy / CELL_SIZE)
end

local function buildGridIndex()
    gridIndex = {}
    if not streets then return end
    for idx, street in ipairs(streets) do
        local seenCells = {}
        for _, seg in ipairs(street.segments) do
            -- Index both endpoints of each segment
            for _, pt in ipairs({ {seg[1], seg[2]}, {seg[3], seg[4]} }) do
                local cx, cy = worldToCell(pt[1], pt[2])
                local key = cellKey(cx, cy)
                if not seenCells[key] then
                    seenCells[key] = true
                    if not gridIndex[key] then
                        gridIndex[key] = {}
                    end
                    table.insert(gridIndex[key], idx)
                end
            end
        end
    end
end

---------------------------------------------------------------
-- XML parsing
---------------------------------------------------------------

--- Parse a streets.xml file into the streets table.
---@param filePath string Path to streets.xml
local function parseStreetsXML(filePath)
    local reader = getFileReader(filePath, false)
    if not reader then return end

    local currentStreet = nil
    local currentPoints = {}

    local line = reader:readLine()
    while line do
        -- Match <street name="..." ...>
        local name = line:match('<street%s+name="([^"]+)"')
        if name then
            currentStreet = name
            currentPoints = {}
        end

        -- Match <point x="..." y="..."/>
        local px, py = line:match('<point%s+x="([^"]+)"%s+y="([^"]+)"')
        if px and py and currentStreet then
            table.insert(currentPoints, { tonumber(px), tonumber(py) })
        end

        -- Match </street>
        if line:match('</street>') and currentStreet and #currentPoints >= 2 then
            local entry = { name = currentStreet, segments = {} }
            for i = 1, #currentPoints - 1 do
                local p1 = currentPoints[i]
                local p2 = currentPoints[i + 1]
                table.insert(entry.segments, { p1[1], p1[2], p2[1], p2[2] })
            end
            table.insert(streets, entry)
            currentStreet = nil
            currentPoints = {}
        end

        line = reader:readLine()
    end
    reader:close()
end

--- Convert PhobosLib_StreetData format (points array) to internal
--- format (segments array of {x1,y1,x2,y2}).
---@param rawData table Array of { name, points = { {x,y}, ... } }
local function loadHardcodedStreetData(rawData)
    if not rawData then return end
    for _, entry in ipairs(rawData) do
        if entry.name and entry.points and #entry.points >= 2 then
            local street = { name = entry.name, segments = {} }
            for i = 1, #entry.points - 1 do
                local p1 = entry.points[i]
                local p2 = entry.points[i + 1]
                table.insert(street.segments, { p1.x, p1.y, p2.x, p2.y })
            end
            table.insert(streets, street)
        end
    end
end

--- Get the loaded world's coordinate bounds from MetaGrid.
--- Returns nil if the world isn't loaded yet (shouldn't happen
--- since loadStreetData is deferred to first query during gameplay).
---@return table|nil { minX, maxX, minY, maxY } in world tiles
local function getLoadedWorldBounds()
    local worldOk, world = pcall(getWorld)
    if not worldOk or not world then return nil end
    local mg = world:getMetaGrid()
    if not mg then return nil end
    -- MetaGrid coordinates are in cells (300 tiles each)
    return {
        minX = mg:getMinX() * 300,
        maxX = (mg:getMaxX() + 1) * 300,
        minY = mg:getMinY() * 300,
        maxY = (mg:getMaxY() + 1) * 300,
    }
end

--- Check if a street has at least one segment endpoint within bounds.
---@param street table { name, segments = { {x1,y1,x2,y2}, ... } }
---@param bounds table { minX, maxX, minY, maxY }
---@return boolean
local function isStreetInBounds(street, bounds)
    for _, seg in ipairs(street.segments) do
        -- Check either endpoint
        if (seg[1] >= bounds.minX and seg[1] <= bounds.maxX
                and seg[2] >= bounds.minY and seg[2] <= bounds.maxY)
            or (seg[3] >= bounds.minX and seg[3] <= bounds.maxX
                and seg[4] >= bounds.minY and seg[4] <= bounds.maxY) then
            return true
        end
    end
    return false
end

--- Filter hardcoded streets to only those within the loaded world.
--- Prevents phantom street names on custom maps that don't include
--- vanilla Knox County areas.
---@param bounds table|nil World bounds; nil = no filtering (keep all)
---@return number Number of streets removed
local function filterByWorldBounds(bounds)
    if not bounds or not streets then return 0 end
    local kept = {}
    local removed = 0
    for _, street in ipairs(streets) do
        if isStreetInBounds(street, bounds) then
            kept[#kept + 1] = street
        else
            removed = removed + 1
        end
    end
    streets = kept
    return removed
end

--- Load street data using three-tier fallback:
--- 1. PhobosLib_StreetData (hardcoded Knox County, ~1087 segments)
---    → filtered by loaded world bounds (prevents phantom streets)
--- 2. streets.xml from all loaded map directories
--- 3. (raw coordinates — handled at query time, no loading needed)
local function loadStreetData()
    if loaded then return end
    loaded = true
    streets = {}

    -- Tier 1: Hardcoded Knox County street network
    local hardcodedCount = 0
    local ok, rawData = pcall(require, "PhobosLib_StreetData")
    if ok and type(rawData) == "table" then
        loadHardcodedStreetData(rawData)
        hardcodedCount = #streets
    end

    -- Filter hardcoded streets by loaded world bounds
    -- (prevents returning Knox County street names on custom-only maps)
    local filteredOut = 0
    if hardcodedCount > 0 then
        local bounds = getLoadedWorldBounds()
        if bounds then
            filteredOut = filterByWorldBounds(bounds)
        end
    end

    -- Tier 2: streets.xml from map directories (mod-added maps)
    local xmlCount = 0
    local dirsOk, dirs = pcall(getLotDirectories)
    if dirsOk and dirs then
        local preCount = #streets
        for i = 0, dirs:size() - 1 do
            local dir = dirs:get(i)
            local path = "media/maps/" .. dir .. "/streets.xml"
            if fileExists(path) then
                parseStreetsXML(path)
            end
        end
        xmlCount = #streets - preCount
    end

    buildGridIndex()

    if PhobosLib and PhobosLib.debug then
        local filterMsg = ""
        if filteredOut > 0 then
            filterMsg = ", " .. filteredOut .. " filtered out-of-bounds"
        end
        PhobosLib.debug("PhobosLib", "[Address]",
            "Loaded " .. #streets .. " streets ("
            .. (hardcodedCount - filteredOut) .. " hardcoded + "
            .. xmlCount .. " from streets.xml"
            .. filterMsg .. ")")
    end
end

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------

--- Find the nearest street to a world position.
---@param x number World X
---@param y number World Y
---@param maxDist number|nil Maximum search distance (default 50)
---@return string|nil streetName
---@return number|nil distance
function PhobosLib_Address.getNearestStreet(x, y, maxDist)
    loadStreetData()
    if not streets or #streets == 0 then return nil, nil end

    maxDist = maxDist or MAX_SEARCH_DIST
    local maxDistSq = maxDist * maxDist
    local bestName = nil
    local bestDistSq = maxDistSq

    -- Gather candidate street indices from nearby grid cells
    local cx, cy = worldToCell(x, y)
    local candidates = {}
    local seen = {}
    for dx = -1, 1 do
        for dy = -1, 1 do
            local key = cellKey(cx + dx, cy + dy)
            local cell = gridIndex and gridIndex[key]
            if cell then
                for _, idx in ipairs(cell) do
                    if not seen[idx] then
                        seen[idx] = true
                        table.insert(candidates, idx)
                    end
                end
            end
        end
    end

    -- Search candidate streets
    for _, idx in ipairs(candidates) do
        local street = streets[idx]
        for _, seg in ipairs(street.segments) do
            local dSq = pointToSegmentDistSq(x, y, seg[1], seg[2], seg[3], seg[4])
            if dSq < bestDistSq then
                bestDistSq = dSq
                bestName = street.name
            end
        end
    end

    if bestName then
        return bestName, math.sqrt(bestDistSq)
    end
    return nil, nil
end

--- Generate a deterministic house number from world coordinates.
--- Range: 100–999 (always 3 digits).
---@param x number World X
---@param y number World Y
---@return string House number
function PhobosLib_Address.generateHouseNumber(x, y)
    local val = math.floor((x * 3 + y * 7) % 900 + 100)
    return tostring(val)
end

--- Resolve a full address for a world position.
--- Returns street name, house number, and nearest intersection.
---@param x number World X
---@param y number World Y
---@return table { street, houseNumber, intersection } (fields may be nil)
function PhobosLib_Address.resolveAddress(x, y)
    loadStreetData()

    local result = {
        street = nil,
        houseNumber = nil,
        intersection = nil,
    }

    local streetName, dist = PhobosLib_Address.getNearestStreet(x, y, MAX_SEARCH_DIST)
    if streetName then
        result.street = streetName
        result.houseNumber = PhobosLib_Address.generateHouseNumber(x, y)
    end

    -- Find intersection (2 nearest different streets within 25 tiles)
    if streets and #streets > 0 then
        local cx, cy = worldToCell(x, y)
        local found = {}
        local maxISq = 25 * 25

        local candidates = {}
        local seen = {}
        for dx = -1, 1 do
            for dy = -1, 1 do
                local key = cellKey(cx + dx, cy + dy)
                local cell = gridIndex and gridIndex[key]
                if cell then
                    for _, idx in ipairs(cell) do
                        if not seen[idx] then
                            seen[idx] = true
                            table.insert(candidates, idx)
                        end
                    end
                end
            end
        end

        for _, idx in ipairs(candidates) do
            local street = streets[idx]
            for _, seg in ipairs(street.segments) do
                local dSq = pointToSegmentDistSq(x, y, seg[1], seg[2], seg[3], seg[4])
                if dSq < maxISq then
                    if not found[street.name] or dSq < found[street.name] then
                        found[street.name] = dSq
                    end
                    break
                end
            end
        end

        local sorted = {}
        for name, dSq in pairs(found) do
            table.insert(sorted, { name = name, distSq = dSq })
        end
        table.sort(sorted, function(a, b) return a.distSq < b.distSq end)

        if #sorted >= 2 then
            result.intersection = sorted[1].name .. " & " .. sorted[2].name
        end
    end

    -- Return nil when no address data was resolved (avoids returning a
    -- table with all-nil named fields — see §25.6 Empty-Data Return Convention)
    if not result.street and not result.intersection then
        return nil
    end

    return result
end

--- Format a resolved address into a human-readable string.
---@param resolved table From resolveAddress()
---@return string Formatted address
function PhobosLib_Address.formatAddress(resolved)
    if not resolved then return "Unknown Location" end
    if resolved.houseNumber and resolved.street then
        return resolved.houseNumber .. " " .. resolved.street
    end
    if resolved.street then
        return resolved.street
    end
    if resolved.intersection then
        return resolved.intersection
    end
    return "Unknown Location"
end
