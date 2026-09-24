-- Get the start position of the time selection
local time_sel_start, time_sel_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

-- Check if there is a valid time selection
if time_sel_start ~= time_sel_end then
    -- Move the edit cursor to the start of the time selection
    reaper.SetEditCurPos(time_sel_start, true, false)
    
    -- Update the arrange view to reflect the cursor movement
    reaper.UpdateArrange()
end

