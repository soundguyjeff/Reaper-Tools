-- Get the current grid line spacing in seconds
function getGridLineSpacing()
    return reaper.Snap_GetGrid(0) -- Get the grid size in seconds
end

-- Nudge the edit cursor left by 1 grid line spacing
function nudgeCursorLeftByGridLine()
    local gridSpacing = getGridLineSpacing()
    if gridSpacing <= 0 then
        reaper.ShowMessageBox("Grid spacing is zero or negative, unable to nudge cursor.", "Error", 0)
        return
    end
    local cursorPos = reaper.GetCursorPosition()
    reaper.SetEditCurPos(cursorPos - gridSpacing, true, false)
end

-- Run the function
nudgeCursorLeftByGridLine()

