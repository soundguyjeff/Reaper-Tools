-- Function to get the nudge amount from REAPER's saved nudge dialog settings
function getSavedNudgeAmount()
    local settingsIndex = 1  -- Settings index for "Saved Nudge Dialog Settings 1"
    local nudgeAmount = reaper.GetExtState("SWS", "Saved Nudge " .. settingsIndex .. " Distance")
    
    if nudgeAmount == "" then
        return 0
    else
        return tonumber(nudgeAmount)
    end
end

-- Nudge the edit cursor left by the saved nudge amount
function nudgeCursorLeft()
    local nudgeAmount = getSavedNudgeAmount()
    
    if nudgeAmount == 0 then
        reaper.ShowMessageBox("Nudge amount not found or is zero.", "Error", 0)
        return
    end
    
    local cursorPos = reaper.GetCursorPosition()
    reaper.SetEditCurPos(cursorPos - nudgeAmount, true, false)
end

-- Run the function
nudgeCursorLeft()

