-- REAPER Lua Script: Custom Nudge Right by 6 Frames Moving Entire Selection

-- Get the frame length in seconds
function getFrameLength()
    local frameRate = reaper.TimeMap_curFrameRate(0)
    if frameRate == 0 then
        frameRate = 30 -- default to 30 fps if frame rate is not available
    end
    return 1 / frameRate
end

-- Move entire selection right by 6 frames
function nudgeRightBy6Frames()
    local frameLength = getFrameLength()
    local nudgeAmount = frameLength * 6 -- Nudge by 6 frames
    local timeSelStart, timeSelEnd = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    
    -- Adjust the time selection
    if timeSelStart ~= timeSelEnd then
        reaper.GetSet_LoopTimeRange(true, false, timeSelStart + nudgeAmount, timeSelEnd + nudgeAmount, false)
    end
    
    -- Adjust selected items
    local numSelectedItems = reaper.CountSelectedMediaItems(0)
    for i = 0, numSelectedItems - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", itemStart + nudgeAmount)
        end
    end
    
    -- Move the edit cursor right by 6 frames if no item is selected
    local cursorPos = reaper.GetCursorPosition()
    reaper.SetEditCurPos(cursorPos + nudgeAmount, true, false)
end

-- Run the function
nudgeRightBy6Frames()

