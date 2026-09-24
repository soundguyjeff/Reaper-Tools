-- REAPER Lua Script: Recall Saved Position 5 and Unselect Items

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
function recallCursorPosition5()
    -- Retrieve the saved position from the global state
    local position5 = reaper.GetExtState("PositionManager", "Position5")
    
    -- Check if the position was saved
    if position5 == "" then
        reaper.ShowMessageBox("Position 5 not found. Please save Position 5 first.", "Error", 0)
        return
    end
    
    -- Unselect all items
    unselectAllItems()
    
    -- Convert the position from string to number and move the edit cursor
    local cursorPos = tonumber(position5)
    if cursorPos then
        reaper.SetEditCurPos(cursorPos, true, true)  -- Set the edit cursor position
    end
end

-- Run the function
recallCursorPosition5()

