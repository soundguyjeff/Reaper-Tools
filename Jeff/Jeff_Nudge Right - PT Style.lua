-- REAPER Lua Script: Custom Nudge Script

-- Get the frame length in seconds
function getFrameLength()
    local frameRate = reaper.TimeMap_curFrameRate(0)
    if frameRate == 0 then
        frameRate = 30 -- default to 30 fps if frame rate is not available
    end
    return 1 / frameRate
end

-- Move selected item right by 1 frame and move edit cursor to the start of the item
function nudgeItemRight()
    local frameLength = getFrameLength()
    local numSelectedItems = reaper.CountSelectedMediaItems(0)
    
    if numSelectedItems > 0 then
        for i = 0, numSelectedItems - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            if item then
                local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                reaper.SetMediaItemInfo_Value(item, "D_POSITION", itemStart + frameLength)
                reaper.SetEditCurPos(itemStart + frameLength, true, true)
            end
        end
    else
        -- Move the edit cursor right by 1 frame if no item is selected
        local cursorPos = reaper.GetCursorPosition()
        reaper.SetEditCurPos(cursorPos + frameLength, true, false)
    end
end

-- Run the function
nudgeItemRight()

