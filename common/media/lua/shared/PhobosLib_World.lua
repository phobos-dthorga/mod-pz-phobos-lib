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
-- PhobosLib_World.lua
-- World-scanning utilities: square iteration, object detection,
-- vehicle/generator finders for Project Zomboid Build 42.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}


--- Safely get the IsoGridSquare a player is standing on.
---@param player any
---@return any|nil  IsoGridSquare or nil
function PhobosLib.getSquareFromPlayer(player)
    if not player or not player.getSquare then return nil end
    local ok, sq = pcall(function() return player:getSquare() end)
    if ok then return sq end
    return nil
end


--- Iterate all grid squares within a radius of an origin square.
--- Calls callback(square) for each valid square found.
--- The callback can return true to stop iteration early.
---@param originSquare any      IsoGridSquare to search around
---@param radius number         Search radius in tiles
---@param callback function     function(square) -> boolean|nil
---@return boolean              true if callback ever returned true
function PhobosLib.scanNearbySquares(originSquare, radius, callback)
    if not originSquare or not callback then return false end
    local ok, cx = pcall(function() return originSquare:getX() end)
    local ok2, cy = pcall(function() return originSquare:getY() end)
    local ok3, cz = pcall(function() return originSquare:getZ() end)
    if not (ok and ok2 and ok3) then return false end

    local cell = getCell()
    if not cell then return false end

    for dx = -radius, radius do
        for dy = -radius, radius do
            local nsq = cell:getGridSquare(cx + dx, cy + dy, cz)
            if nsq then
                local stop = callback(nsq)
                if stop == true then return true end
            end
        end
    end
    return false
end


--- Find the first IsoObject on nearby squares whose name or sprite
--- matches one of the given keywords (case-insensitive substring).
---@param originSquare any
---@param radius number
---@param keywords table    List of keyword strings
---@return any|nil          The matching IsoObject, or nil
function PhobosLib.findNearbyObjectByKeywords(originSquare, radius, keywords)
    if not keywords or #keywords == 0 then return nil end
    local found = nil

    PhobosLib.scanNearbySquares(originSquare, radius, function(sq)
        local objs = sq:getObjects()
        if not objs then return false end
        for i = 0, objs:size() - 1 do
            local obj = objs:get(i)
            if obj then
                local spriteName = ""
                local objName = ""
                pcall(function()
                    local sprite = obj:getSprite()
                    if sprite and sprite.getName then spriteName = sprite:getName() or "" end
                end)
                pcall(function()
                    if obj.getName then objName = obj:getName() or "" end
                end)
                local s = PhobosLib.lower(spriteName)
                local n = PhobosLib.lower(objName)
                for _, kw in ipairs(keywords) do
                    local k = PhobosLib.lower(kw)
                    if k ~= "" and (string.find(s, k, 1, true) or string.find(n, k, 1, true)) then
                        found = obj
                        return true  -- stop scanning
                    end
                end
            end
        end
        return false
    end)

    return found
end


--- Find ALL IsoObjects on nearby squares matching keywords.
---@param originSquare any
---@param radius number
---@param keywords table
---@return table
function PhobosLib.findAllNearbyObjectsByKeywords(originSquare, radius, keywords)
    local results = {}
    if not keywords or #keywords == 0 then return results end

    PhobosLib.scanNearbySquares(originSquare, radius, function(sq)
        local objs = sq:getObjects()
        if not objs then return false end
        for i = 0, objs:size() - 1 do
            local obj = objs:get(i)
            if obj then
                local spriteName = ""
                local objName = ""
                pcall(function()
                    local sprite = obj:getSprite()
                    if sprite and sprite.getName then spriteName = sprite:getName() or "" end
                end)
                pcall(function()
                    if obj.getName then objName = obj:getName() or "" end
                end)
                local s = PhobosLib.lower(spriteName)
                local n = PhobosLib.lower(objName)
                for _, kw in ipairs(keywords) do
                    local k = PhobosLib.lower(kw)
                    if k ~= "" and (string.find(s, k, 1, true) or string.find(n, k, 1, true)) then
                        table.insert(results, obj)
                        break  -- don't add same object twice
                    end
                end
            end
        end
        return false
    end)

    return results
end


--- Boolean convenience: is the player within radius of an object matching keywords?
---@param player any
---@param radius number
---@param keywords table
---@return boolean
function PhobosLib.isNearObjectType(player, radius, keywords)
    local sq = PhobosLib.getSquareFromPlayer(player)
    if not sq then return false end
    return PhobosLib.findNearbyObjectByKeywords(sq, radius, keywords) ~= nil
end


--- Find an active IsoGenerator near a square.
--- "Active" means fuel > 0 and activated (running).
---@param square any        IsoGridSquare to search around
---@param radius number     Search radius in tiles
---@return any|nil          The IsoGenerator object, or nil
function PhobosLib.findNearbyGenerator(square, radius)
    if not square then return nil end
    local found = nil

    PhobosLib.scanNearbySquares(square, radius, function(sq)
        local gen = nil
        pcall(function() gen = sq:getGenerator() end)
        if gen then
            local activated = false
            local hasFuel = false
            pcall(function() activated = gen:isActivated() end)
            pcall(function() hasFuel = (gen:getFuel() > 0) end)
            if activated and hasFuel then
                found = gen
                return true  -- stop scanning
            end
        end
        return false
    end)

    return found
end


--- Find any IsoGenerator near a square (regardless of whether it's running).
---@param square any
---@param radius number
---@return any|nil
function PhobosLib.findAnyNearbyGenerator(square, radius)
    if not square then return nil end
    local found = nil

    PhobosLib.scanNearbySquares(square, radius, function(sq)
        local gen = nil
        pcall(function() gen = sq:getGenerator() end)
        if gen then
            found = gen
            return true
        end
        return false
    end)

    return found
end


--- Find the nearest vehicle within radius tiles of a player.
--- Uses the getCell():getVehicles() approach.
---@param player any
---@param radius number
---@return any|nil  The BaseVehicle, or nil
function PhobosLib.findNearbyVehicle(player, radius)
    if not player then return nil end
    local sq = PhobosLib.getSquareFromPlayer(player)
    if not sq then return nil end

    local ok, px = pcall(function() return sq:getX() end)
    local ok2, py = pcall(function() return sq:getY() end)
    if not (ok and ok2) then return nil end

    -- Try to get vehicles from the cell
    local cell = getCell()
    if not cell then return nil end

    local vehicles = nil
    pcall(function() vehicles = cell:getVehicles() end)
    if not vehicles then return nil end

    local bestDist = radius * radius + 1
    local bestVehicle = nil

    for i = 0, vehicles:size() - 1 do
        local v = vehicles:get(i)
        if v then
            local vok, vx = pcall(function() return v:getX() end)
            local vok2, vy = pcall(function() return v:getY() end)
            if vok and vok2 then
                local dx = vx - px
                local dy = vy - py
                local distSq = dx * dx + dy * dy
                if distSq < bestDist then
                    bestDist = distSq
                    bestVehicle = v
                end
            end
        end
    end

    if bestDist <= radius * radius then
        return bestVehicle
    end
    return nil
end


--- Safely retrieve the IsoGridSquare at absolute world coordinates.
--- Handles nil cell gracefully.
---@param x number  World X coordinate
---@param y number  World Y coordinate
---@param z number  World Z coordinate (floor level)
---@return any|nil  IsoGridSquare or nil if cell or chunk is not loaded
function PhobosLib.getGridSquareAt(x, y, z)
    if not x or not y or not z then return nil end
    local cell = getCell()
    if not cell then return nil end
    local ok, sq = pcall(function() return cell:getGridSquare(x, y, z) end)
    if ok then return sq end
    return nil
end


--- Find ALL vehicles within radius tiles of a player.
--- Returns a list of {vehicle, distSq} sorted by distance (nearest first).
--- Unlike findNearbyVehicle(), returns all matches for filtering.
---@param player any
---@param radius number
---@return table  Array of {vehicle=BaseVehicle, distSq=number}, may be empty
function PhobosLib.findNearbyVehicles(player, radius)
    local results = {}
    if not player then return results end
    local sq = PhobosLib.getSquareFromPlayer(player)
    if not sq then return results end

    local ok, px = pcall(function() return sq:getX() end)
    local ok2, py = pcall(function() return sq:getY() end)
    if not (ok and ok2) then return results end

    local cell = getCell()
    if not cell then return results end

    local vehicles = nil
    pcall(function() vehicles = cell:getVehicles() end)
    if not vehicles then return results end

    local maxDistSq = radius * radius

    for i = 0, vehicles:size() - 1 do
        local v = vehicles:get(i)
        if v then
            local vok, vx = pcall(function() return v:getX() end)
            local vok2, vy = pcall(function() return v:getY() end)
            if vok and vok2 then
                local dx = vx - px
                local dy = vy - py
                local distSq = dx * dx + dy * dy
                if distSq <= maxDistSq then
                    table.insert(results, { vehicle = v, distSq = distSq })
                end
            end
        end
    end

    table.sort(results, function(a, b) return a.distSq < b.distSq end)
    return results
end


--- Safe check whether a vehicle's engine is currently running.
--- Probes multiple possible method names.
---@param vehicle any
---@return boolean
function PhobosLib.isVehicleRunning(vehicle)
    if not vehicle then return false end

    -- Try direct boolean methods
    local probes = {"isEngineRunning", "getEngineRunning", "isRunning"}
    for _, m in ipairs(probes) do
        local ok, v = PhobosLib.pcallMethod(vehicle, m)
        if ok and v == true then return true end
    end

    -- Try engine speed > 0 as a fallback heuristic
    local ok, speed = PhobosLib.pcallMethod(vehicle, "getEngineSpeed")
    if ok and type(speed) == "number" and speed > 0 then return true end

    return false
end


--- Check whether the area around the player is safe (no nearby zombies).
--- Mirrors vanilla's sleep safety check: visible, chasing, and very-close
--- zombie counts must all be zero.
--- Lightweight — reads pre-computed player stats, no grid scanning.
---@param player any  IsoPlayer or IsoGameCharacter
---@return boolean    true if no zombies detected nearby
function PhobosLib.isAreaSafe(player)
    if not player then return false end
    local ok, stats = pcall(function() return player:getStats() end)
    if not ok or not stats then return false end
    local visible = 0
    local chasing = 0
    local veryClose = 0
    pcall(function()
        visible   = stats:getNumVisibleZombies()  or 0
        chasing   = stats:getNumChasingZombies()   or 0
        veryClose = stats:getNumVeryCloseZombies() or 0
    end)
    return visible == 0 and chasing == 0 and veryClose == 0
end


--- Calculate Euclidean (straight-line) distance between two world points.
---@param x1 number First point X
---@param y1 number First point Y
---@param x2 number Second point X
---@param y2 number Second point Y
---@return number Distance in tiles
function PhobosLib.euclideanDistance(x1, y1, x2, y2)
    local dx = (x2 or 0) - (x1 or 0)
    local dy = (y2 or 0) - (y1 or 0)
    return math.sqrt(dx * dx + dy * dy)
end


--- Find ALL IsoObjects on nearby squares whose sprite name matches any
--- of the given exact sprite names. More precise than keyword matching.
--- Uses scanNearbySquares() internally.
---@param centerX number     World X coordinate to search around
---@param centerY number     World Y coordinate to search around
---@param radius number      Search radius in tiles
---@param spriteNames table  Array of exact sprite name strings to match
---@return table             Array of { object, x, y, z } tables
function PhobosLib.findWorldObjectsBySprite(centerX, centerY, radius, spriteNames)
    local results = {}
    if not spriteNames or #spriteNames == 0 then return results end

    -- Build lookup set for O(1) matching
    local spriteSet = {}
    for _, name in ipairs(spriteNames) do
        spriteSet[name] = true
    end

    local cell = getCell()
    if not cell then return results end

    local z = 0  -- ground level for outdoor objects
    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = cell:getGridSquare(centerX + dx, centerY + dy, z)
            if sq then
                local objs = sq:getObjects()
                if objs then
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        if obj then
                            local spriteName = nil
                            pcall(function()
                                local sprite = obj:getSprite()
                                if sprite and sprite.getName then
                                    spriteName = sprite:getName()
                                end
                            end)
                            if spriteName and spriteSet[spriteName] then
                                table.insert(results, {
                                    object = obj,
                                    x = centerX + dx,
                                    y = centerY + dy,
                                    z = z,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    return results
end


--- Find BuildingDef objects near a world position that contain rooms
--- matching the given room name filter.
---
--- Uses IsoCell:getGridSquare() + getBuilding() to probe grid squares
--- within the search area, deduplicating by building ID.
---
---@param centerX number World X coordinate
---@param centerY number World Y coordinate
---@param radius number Search radius in tiles
---@param roomFilter table Array of room name strings to match (e.g. {"pharmacy", "medical"})
---@return table Array of { buildingDef, x, y, matchingRooms = {name, ...} }
function PhobosLib.findNearbyBuildings(centerX, centerY, radius, roomFilter)
    local results = {}
    if not roomFilter or #roomFilter == 0 then return results end

    local cell = getCell()
    if not cell then return results end

    -- Build lookup set for room names
    local filterSet = {}
    for _, name in ipairs(roomFilter) do
        filterSet[name] = true
    end

    -- Track seen building IDs to avoid duplicates
    local seen = {}

    -- Sample grid squares at intervals (buildings span multiple tiles,
    -- so we don't need to check every single tile)
    local step = 5  -- check every 5th tile
    for dx = -radius, radius, step do
        for dy = -radius, radius, step do
            local sq = cell:getGridSquare(centerX + dx, centerY + dy, 0)
            if sq then
                local building = nil
                pcall(function() building = sq:getBuilding() end)
                if building then
                    local bDef = nil
                    pcall(function() bDef = building:getDef() end)
                    if bDef then
                        local bId = nil
                        pcall(function() bId = bDef:getIDString() end)
                        if bId and not seen[bId] then
                            seen[bId] = true

                            -- Check rooms against filter
                            local matchingRooms = {}
                            pcall(function()
                                local rooms = bDef:getRooms()
                                if rooms then
                                    for i = 0, rooms:size() - 1 do
                                        local room = rooms:get(i)
                                        if room then
                                            local rName = room:getName()
                                            if rName and filterSet[rName] then
                                                table.insert(matchingRooms, rName)
                                            end
                                        end
                                    end
                                end
                            end)

                            if #matchingRooms > 0 then
                                local bx, by = centerX + dx, centerY + dy
                                pcall(function()
                                    bx = bDef:getX()
                                    by = bDef:getY()
                                end)
                                table.insert(results, {
                                    buildingDef = bDef,
                                    x = bx,
                                    y = by,
                                    matchingRooms = matchingRooms,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    return results
end


--- Get the RoomDef name of the room the player is currently standing in.
--- Returns nil if the player is outdoors or not in a defined room.
--- Full pcall safety chain for robust error handling.
---@param player any IsoPlayer
---@return string|nil Room name (e.g. "pharmacy", "kitchen") or nil
function PhobosLib.getPlayerRoomName(player)
    if not player then return nil end
    local sq = nil
    pcall(function() sq = player:getCurrentSquare() end)
    if not sq then return nil end

    local room = nil
    pcall(function() room = sq:getRoom() end)
    if not room then return nil end

    local roomDef = nil
    pcall(function() roomDef = room:getRoomDef() end)
    if not roomDef then return nil end

    local name = nil
    pcall(function() name = roomDef:getName() end)
    return name
end


--- Place a named marker on the PZ world map.
--- Uses the WorldMarkers API to create a grid-square marker.
---@param id string Unique marker identifier (for later removal)
---@param x number World X coordinate
---@param y number World Y coordinate
---@param r number Red (0-1)
---@param g number Green (0-1)
---@param b number Blue (0-1)
---@param a number|nil Alpha (0-1, default 1)
---@return boolean True if marker was placed
function PhobosLib.addWorldMapMarker(id, x, y, r, g, b, a)
    if not id or not x or not y then return false end
    local ok = false
    pcall(function()
        local markers = getWorldMarkers()
        if markers then
            markers:addGridSquareMarker(id, nil,
                math.floor(x), math.floor(y),
                10, r or 1, g or 1, b or 1, a or 1)
            ok = true
        end
    end)
    return ok
end

--- Remove a named marker from the PZ world map.
---@param id string Marker identifier used when placing
---@return boolean True if removal was attempted
function PhobosLib.removeWorldMapMarker(id)
    if not id then return false end
    local ok = false
    pcall(function()
        local markers = getWorldMarkers()
        if markers and markers.removeGridSquareMarker then
            markers:removeGridSquareMarker(id)
            ok = true
        end
    end)
    return ok
end


--- Roll random condition damage on an item.
--- If the chance roll succeeds, lose ZombRand(minLoss, maxLoss+1) condition.
--- If the item's condition reaches 0, it is destroyed (vanilla behaviour).
---@param item any InventoryItem
---@param minLoss number Minimum condition to lose
---@param maxLoss number Maximum condition to lose
---@param chancePct number Percentage chance (0-100) of damage occurring
---@return boolean True if damage was applied
function PhobosLib.damageItemCondition(item, minLoss, maxLoss, chancePct)
    if not item then return false end
    chancePct = chancePct or 100
    if ZombRand(100) >= chancePct then return false end

    local loss = ZombRand(minLoss or 1, (maxLoss or minLoss or 1) + 1)
    local cond = item:getCondition()
    if cond then
        item:setCondition(math.max(0, cond - loss))
        return true
    end
    return false
end
