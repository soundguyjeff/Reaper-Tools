-- REAPER Lua Script: Recall Saved Position 4 and Unselect Items

-- Unselect all items
function unselectAllItems()
    local numSelectedItems = reaper.CountSelectedMediaItems(0)
    for i = 0, numSelectedItems - 1 do
        local item = reaper.GetSelectedMediaItem(0, 0) -- Always get the first selected item
        if item then
            reaper.SetMediaItemSelected(item, false)
        end
    end
end

-- Recall the saved cursor position
function recallCursorPosition4()
    -- Retrieve the saved position from the global state
    local position4 = reaper.GetExtState("PositionManager", "Position4")
    
    -- Check if the position was saved
    if position4 == "" then
        reaper.ShowMessageBox("Position 4 not found. Please save Position 4 first.", "Error", 0)
        return
    end
    
    -- Unselect all items
    unselectAllItems()
    
    -- Convert the position from string to number and move the edit cursor
    local cursorPos = tonumber(position4)
    if cursorPos then
        reaper.SetEditCurPos(cursorPos, true, true)  -- Set the edit cursor position
    end
end

-- Run the function
recallCursorPosition4()

