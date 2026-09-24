-- Get the current play state
local playState = reaper.GetPlayState()

if playState == 0 then -- If stopped
    -- Get the count of selected items
    local itemCount = reaper.CountSelectedMediaItems(0)

    if itemCount > 0 then
        -- Get the first selected item
        local firstItem = reaper.GetSelectedMediaItem(0, 0)
        if firstItem then
            -- Get the start position of the item
            local itemStart = reaper.GetMediaItemInfo_Value(firstItem, "D_POSITION")
            
            -- Set the edit cursor to the start of the item
            reaper.SetEditCurPos(itemStart, true, false)
        end
    else
        -- If no items are selected, just play from the current edit cursor position
    end

    -- Start playback
    reaper.OnPlayButton()
else
    -- Stop playback
    reaper.OnStopButton()
end

