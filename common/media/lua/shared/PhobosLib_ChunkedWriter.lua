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
-- PhobosLib_ChunkedWriter.lua
-- Generic chunked file writer that spreads large file writes
-- across multiple EveryOneMinute ticks to avoid single-frame
-- I/O spikes.
--
-- Usage:
--   local writer = PhobosLib.createChunkedWriter({
--       filePath    = "MYMOD/data.dat",
--       chunkSize   = 4,
--       onSerialize = function(key, data) return { "line1", "line2" } end,
--       onComplete  = function() myDirtyFlag = false end,
--   })
--
--   -- On save trigger:
--   PhobosLib.startChunkedWrite(writer, myDataTable)
--
--   -- Each EveryOneMinute tick:
--   PhobosLib.tickChunkedWrite(writer)
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:ChunkedWriter]"

local DEFAULT_CHUNK_SIZE = 4

---------------------------------------------------------------
-- Factory
---------------------------------------------------------------

--- Create a new chunked writer instance.
---@param opts table Configuration:
---   filePath:    string             Target file path for getFileWriter()
---   chunkSize:   number|nil         Items to process per tick (default 4)
---   onSerialize: fun(key, data): string[]  Returns lines for one item
---   onComplete:  fun()|nil          Optional callback after flush
---@return table ChunkedWriter instance
function PhobosLib.createChunkedWriter(opts)
    return {
        _opts   = opts,
        _queue  = nil,
        _source = nil,
        _buffer = nil,
        _active = false,
    }
end

---------------------------------------------------------------
-- Start / tick / query
---------------------------------------------------------------

--- Queue all items from source for chunked writing.
--- Captures keys from the source table at call time.
---@param writer table  ChunkedWriter from createChunkedWriter
---@param source table  { [key] = data } — the data to serialise
---@return boolean true if started, false if already active or empty
function PhobosLib.startChunkedWrite(writer, source)
    if writer._active then return false end

    local queue = {}
    for key in pairs(source) do
        queue[#queue + 1] = key
    end
    if #queue == 0 then return false end

    writer._queue  = queue
    writer._source = source
    writer._buffer = {}
    writer._active = true

    PhobosLib.debug("PhobosLib", _TAG,
        "Chunked write started: " .. #queue .. " items, chunk="
        .. (writer._opts.chunkSize or DEFAULT_CHUNK_SIZE))
    return true
end

--- Process the next chunk. Call once per EveryOneMinute tick.
---@param writer table ChunkedWriter
---@return boolean true if the write is now complete
function PhobosLib.tickChunkedWrite(writer)
    if not writer._active then return false end

    local opts      = writer._opts
    local chunkSize = opts.chunkSize or DEFAULT_CHUNK_SIZE
    local processed = 0

    while #writer._queue > 0 and processed < chunkSize do
        local key = table.remove(writer._queue, 1)
        local data = writer._source[key]
        if data and opts.onSerialize then
            local lines = opts.onSerialize(key, data)
            if lines then
                for _, line in ipairs(lines) do
                    writer._buffer[#writer._buffer + 1] = line
                end
            end
        end
        processed = processed + 1
    end

    -- Queue drained — flush buffer to disk
    if #writer._queue == 0 then
        local writer_ = getFileWriter(opts.filePath, false, false)
        if writer_ then
            for _, line in ipairs(writer._buffer) do
                writer_:writeln(line)
            end
            writer_:close()
            PhobosLib.debug("PhobosLib", _TAG,
                "Chunked write complete: " .. #writer._buffer .. " lines -> " .. opts.filePath)
        else
            PhobosLib.debug("PhobosLib", _TAG,
                "Chunked write FAILED: could not open " .. opts.filePath)
        end

        -- Cleanup and callback
        writer._queue  = nil
        writer._source = nil
        writer._buffer = nil
        writer._active = false

        if opts.onComplete then
            PhobosLib.safecall(opts.onComplete)
        end
        return true
    end

    PhobosLib.debug("PhobosLib", _TAG,
        "Chunked write tick: " .. processed .. " items, "
        .. #writer._queue .. " remaining")
    return false
end

--- Whether a chunked write is currently in progress.
---@param writer table ChunkedWriter
---@return boolean
function PhobosLib.isChunkedWriteActive(writer)
    return writer._active == true
end
