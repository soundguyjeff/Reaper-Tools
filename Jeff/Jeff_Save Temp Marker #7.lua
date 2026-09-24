-- REAPER Lua Script: Save Edit Cursor Position as "Position 7"

-- Save the current edit cursor position
function saveCursorPosition()
    -- Get the current edit cursor position
    local cursorPos = reaper.GetCursorPosition()
    
    -- Save the position in the project’s global state
    reaper.SetExtState("PositionManager", "Position7", tostring(cursorPos), true)
    
end

-- Run the function
saveCursorPosition()

