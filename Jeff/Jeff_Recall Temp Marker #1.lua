-- REAPER Lua Script: Recall Saved Position 1 and Unselect Items

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
function recallCursorPosition1()
    -- Retrieve the saved position from the global state
    local position2 = reaper.GetExtState("PositionManager", "Position1")
    
    -- Check if the position was saved
    if position2 == "" then
        reaper.ShowMessageBox("Position 1 not found. Please save Position 1 first.", "Error", 0)
        return
    end
    
    -- Unselect all items
    unselectAllItems()
    
    -- Convert the position from string to number and move the edit cursor
    local cursorPos = tonumber(position2)
    if cursorPos then
        reaper.SetEditCurPos(cursorPos, true, true)  -- Set the edit cursor position
    end
end

-- Run the function
recallCursorPosition1()

