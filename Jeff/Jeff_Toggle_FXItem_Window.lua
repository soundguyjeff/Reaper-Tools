-- Toggle the FX window for the currently selected item

-- Function to toggle the FX window for a given item
local function toggle_fx_window(item)
    local take = reaper.GetActiveTake(item)
    if not take then return end

    local fx_count = reaper.TakeFX_GetCount(take)
    if fx_count == 0 then return end

    -- Check if any FX window is open
    local any_fx_open = false
    for i = 0, fx_count - 1 do
        local hwnd = reaper.TakeFX_GetOpen(take, i)
        if hwnd then
            any_fx_open = true
            break
        end
    end
    
    -- Toggle FX windows
    for i = 0, fx_count - 1 do
        if any_fx_open then
            -- Close all FX windows if any are open
            reaper.TakeFX_SetOpen(take, i, false)
        else
            -- Open all FX windows if none are open
            reaper.TakeFX_SetOpen(take, i, true)
        end
    end
    
    -- Re-focus the item
    reaper.SetMediaItemSelected(item, true)
    reaper.Main_OnCommand(40289, 0)  -- Set focus back to the selected item (normally action 40289 is "View: Toggle TCP/Track Control Panel")
end

-- Get the currently selected item
local item = reaper.GetSelectedMediaItem(0, 0)
if item then
    toggle_fx_window(item)
end

-- Update the REAPER UI to reflect changes
reaper.UpdateArrange()

