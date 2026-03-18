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
-- PhobosLib_TextUtils.lua
-- Text measurement and truncation utilities for PZ UI rendering.
--
-- Provides pixel-aware text truncation with ellipsis and
-- character width measurement. Used by POSnet terminal,
-- PCP tooltips, and any Phobos mod rendering text in ISPanel.
---------------------------------------------------------------

local DEFAULT_ELLIPSIS = "..."
local DEFAULT_CHAR_WIDTH = 8

--- Truncate text to fit within a maximum pixel width, appending
--- an ellipsis if the text is too long.
---
--- Uses PZ's TextManager to measure actual rendered width.
--- If the text fits, returns it unchanged. If it overflows,
--- progressively trims from the end until it fits with ellipsis.
---
--- @param text string The text to potentially truncate
--- @param font UIFont The font used for rendering
--- @param maxPixelWidth number Maximum allowed width in pixels
--- @param ellipsis string|nil Ellipsis string (default "...")
--- @return string The original text or truncated text with ellipsis
function PhobosLib.truncateText(text, font, maxPixelWidth, ellipsis)
    if not text or text == "" then return "" end
    if not font or not maxPixelWidth or maxPixelWidth <= 0 then return text end

    ellipsis = ellipsis or DEFAULT_ELLIPSIS

    local tm = getTextManager and getTextManager()
    if not tm then return text end

    local fullWidth = tm:MeasureStringX(font, text)
    if fullWidth <= maxPixelWidth then return text end

    local ellipsisWidth = tm:MeasureStringX(font, ellipsis)
    local targetWidth = maxPixelWidth - ellipsisWidth

    if targetWidth <= 0 then return ellipsis end

    -- Progressive trim from end (fast for typical label lengths)
    for i = #text, 1, -1 do
        local sub = string.sub(text, 1, i)
        if tm:MeasureStringX(font, sub) <= targetWidth then
            return sub .. ellipsis
        end
    end

    return ellipsis
end

--- Measure the approximate width of a single character in a given font.
---
--- Uses the uppercase "M" as the reference character (widest common glyph).
--- Useful for converting pixel-based widths to character counts.
---
--- @param font UIFont The font to measure
--- @return number Width of "M" in pixels, or 8 as fallback
function PhobosLib.measureCharWidth(font)
    local tm = getTextManager and getTextManager()
    if not tm or not font then return DEFAULT_CHAR_WIDTH end
    local w = tm:MeasureStringX(font, "M")
    return (w and w > 0) and w or DEFAULT_CHAR_WIDTH
end

--- Calculate the maximum number of characters that fit in a pixel width.
---
--- @param font UIFont The font to measure
--- @param pixelWidth number Available pixel width
--- @param padding number|nil Pixel padding to subtract (default 0)
--- @return number Maximum character count
function PhobosLib.maxCharsForWidth(font, pixelWidth, padding)
    local charW = PhobosLib.measureCharWidth(font)
    local available = (pixelWidth or 0) - (padding or 0)
    return math.max(1, math.floor(available / charW))
end
