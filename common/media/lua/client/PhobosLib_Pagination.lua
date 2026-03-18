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
-- PhobosLib_Pagination.lua
-- Reusable pagination helper for PZ ISPanel UIs.
--
-- Renders a slice of items into a parent panel using a caller-
-- provided renderItem callback, then adds Previous/Next nav
-- buttons at the bottom. Stateless — the caller manages the
-- current page number.
---------------------------------------------------------------

require "ISUI/ISButton"
require "ISUI/ISLabel"

PhobosLib_Pagination = {}

--- Default colour palette (CRT green — overridable via config.colours).
local DEFAULT_COLOURS = {
    text    = { r = 0.85, g = 0.90, b = 0.85, a = 1.0 },
    dim     = { r = 0.50, g = 0.55, b = 0.50, a = 1.0 },
    bgDark  = { r = 0.04, g = 0.04, b = 0.04, a = 0.8 },
    bgHover = { r = 0.12, g = 0.12, b = 0.12, a = 0.8 },
    border  = { r = 0.40, g = 0.40, b = 0.40, a = 0.8 },
}

--- Create a paginated view in a parent panel.
---
--- @param parent any ISPanel parent to add children to
--- @param config table Configuration:
---   items       = table   Array of items to paginate
---   pageSize    = number  Items per page (default 5)
---   currentPage = number  1-based page number (default 1)
---   x           = number  X offset for content (default 0)
---   y           = number  Starting Y position (default 0)
---   width       = number  Available width for nav bar
---   renderItem  = function(parent, x, y, w, item, index) -> yAdvance
---                         Renders one item; returns the Y advance used.
---   onPageChange = function(newPage) Called when Prev/Next is clicked
---   maxHeight   = number  Optional: available panel height — if provided,
---                         pageSize is computed dynamically from the available
---                         vertical space (overrides static pageSize).
---                         Accounts for nav bar height.
---   itemHeight  = number  Average item height in pixels (default 28, used
---                         with maxHeight to calculate dynamic pageSize).
---   font        = any     UIFont for nav buttons (default UIFont.Code)
---   colours     = table   Optional colour override { text, dim, bgDark, bgHover, border }
---
--- @return number finalY    Y position after the paginator
--- @return number totalPages Total number of pages
function PhobosLib_Pagination.create(parent, config)
    if not parent or not config then return 0, 0 end

    local items = config.items or {}
    local pageSize = config.pageSize or 5
    local currentPage = config.currentPage or 1

    -- Dynamic page size: if maxHeight is provided, calculate how many items fit
    if config.maxHeight then
        local itemH = config.itemHeight or 28
        local navBarH = 32  -- prev/next buttons + padding
        local availableH = config.maxHeight - (config.y or 0) - navBarH
        local dynamicSize = math.floor(availableH / itemH)
        pageSize = math.max(3, math.min(10, dynamicSize))
    end
    local x = config.x or 0
    local y = config.y or 0
    local width = config.width or (parent:getWidth() - 10)
    local renderItem = config.renderItem
    local onPageChange = config.onPageChange
    local font = config.font or UIFont.Code
    local C = config.colours or DEFAULT_COLOURS

    local totalPages = math.max(1, math.ceil(#items / pageSize))
    currentPage = math.max(1, math.min(currentPage, totalPages))

    -- Render items for current page
    local startIdx = (currentPage - 1) * pageSize + 1
    local endIdx = math.min(startIdx + pageSize - 1, #items)

    if renderItem then
        for i = startIdx, endIdx do
            local yAdvance = renderItem(parent, x, y, width, items[i], i) or 20
            y = y + yAdvance
        end
    end

    -- Only show nav bar if there are multiple pages
    if totalPages <= 1 then
        return y, totalPages
    end

    y = y + 4

    -- Nav bar: [ < Prev ]  Page X/Y  [ Next > ]
    local btnH = 24
    local btnW = math.floor(width * 0.25)
    local pageLabel = "Page " .. currentPage .. "/" .. totalPages

    -- Previous button
    if currentPage > 1 then
        local prevBtn = ISButton:new(x, y, btnW, btnH, "< Prev", nil,
            function()
                if onPageChange then onPageChange(currentPage - 1) end
            end)
        prevBtn.backgroundColor = { r = C.bgDark.r, g = C.bgDark.g, b = C.bgDark.b, a = C.bgDark.a }
        prevBtn.backgroundColorMouseOver = { r = C.bgHover.r, g = C.bgHover.g, b = C.bgHover.b, a = C.bgHover.a }
        prevBtn.borderColor = { r = C.border.r, g = C.border.g, b = C.border.b, a = C.border.a }
        prevBtn.textColor = { r = C.text.r, g = C.text.g, b = C.text.b, a = C.text.a }
        prevBtn.font = font
        prevBtn:initialise()
        prevBtn:instantiate()
        parent:addChild(prevBtn)
    end

    -- Page indicator (centred)
    local labelX = x + math.floor(width * 0.35)
    local pageIndicator = ISLabel:new(labelX, y + 3, 18, pageLabel,
        C.dim.r, C.dim.g, C.dim.b, C.dim.a or 1.0, font, true)
    pageIndicator:initialise()
    pageIndicator:instantiate()
    parent:addChild(pageIndicator)

    -- Next button
    if currentPage < totalPages then
        local nextBtn = ISButton:new(x + width - btnW, y, btnW, btnH, "Next >", nil,
            function()
                if onPageChange then onPageChange(currentPage + 1) end
            end)
        nextBtn.backgroundColor = { r = C.bgDark.r, g = C.bgDark.g, b = C.bgDark.b, a = C.bgDark.a }
        nextBtn.backgroundColorMouseOver = { r = C.bgHover.r, g = C.bgHover.g, b = C.bgHover.b, a = C.bgHover.a }
        nextBtn.borderColor = { r = C.border.r, g = C.border.g, b = C.border.b, a = C.border.a }
        nextBtn.textColor = { r = C.text.r, g = C.text.g, b = C.text.b, a = C.text.a }
        nextBtn.font = font
        nextBtn:initialise()
        nextBtn:instantiate()
        parent:addChild(nextBtn)
    end

    y = y + btnH + 4

    return y, totalPages
end
