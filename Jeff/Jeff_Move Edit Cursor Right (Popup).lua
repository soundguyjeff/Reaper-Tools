-- Define the fixed value to move the cursor by (in seconds)
local move_by_seconds = 10

-- Get the current position of the edit cursor
local current_position = reaper.GetCursorPosition()

-- Calculate the new position by adding the fixed value
local new_position = current_position + move_by_seconds

-- Move the edit cursor to the new position
reaper.SetEditCurPos(new_position, true, false)

-- Update the arrange view to reflect the cursor movement
reaper.UpdateArrange()

