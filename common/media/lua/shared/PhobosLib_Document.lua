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
-- PhobosLib_Document.lua
-- Readable document utilities using PZ's Literature API.
--
-- Wraps the Literature class methods (setBookName, setNumberOfPages,
-- addPage, seePage) for easy creation of readable in-game documents.
-- Used by POSnet (market notes, field reports, tape transcripts),
-- PCP (dynamic recipe information), PIP (specimen data sheets).
---------------------------------------------------------------

--- Create a readable document from an inventory item.
---
--- Sets the book name, page count, and page contents using PZ's
--- Literature API. The item should be a Literature-type item or
--- support the addPage/setNumberOfPages methods.
---
--- @param item any InventoryItem (Literature type)
--- @param title string|nil Book/document title
--- @param pages table Array of page text strings
--- @return boolean True if at least the title or pages were set
function PhobosLib.createReadableDocument(item, title, pages)
    if not item then return false end
    local success = false

    if title then
        local ok = pcall(function() item:setBookName(title) end)
        if ok then success = true end
    end

    if pages and type(pages) == "table" and #pages > 0 then
        pcall(function() item:setNumberOfPages(#pages) end)
        for i, pageText in ipairs(pages) do
            local ok = pcall(function() item:addPage(i - 1, tostring(pageText)) end)
            if ok then success = true end
        end
    end

    return success
end

--- Read a specific page from a readable document.
---
--- @param item any InventoryItem (Literature type)
--- @param pageIndex number 0-based page index
--- @return string|nil Page text or nil
function PhobosLib.readDocumentPage(item, pageIndex)
    if not item or not pageIndex then return nil end
    local ok, text = pcall(function() return item:seePage(pageIndex) end)
    if ok then return text end
    return nil
end

--- Get the total number of pages in a readable document.
---
--- @param item any InventoryItem (Literature type)
--- @return number Page count (0 if not a literature item)
function PhobosLib.getDocumentPageCount(item)
    if not item then return 0 end
    local ok, count = pcall(function() return item:getNumberOfPages() end)
    if ok and count then return count end
    return 0
end
