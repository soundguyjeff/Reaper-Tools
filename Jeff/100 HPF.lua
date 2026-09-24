-- Add Pro-Q and load a preset to all selected items

-- Define the name of the preset to recall
local preset_name = "Jeff - 100 HPF"

-- Get the number of selected items
local num_selected_items = reaper.CountSelectedMediaItems(0)

-- Iterate through all selected items
for i = 0, num_selected_items - 1 do
    -- Get the selected item
    local item = reaper.GetSelectedMediaItem(0, i)
    if item then
        -- Get the active take of the item
        local take = reaper.GetActiveTake(item)
        if take then
      
        
            -- Add Pro-Q to the take's FX chain
            local fx_index = reaper.TakeFX_AddByName(take, "ReaEQ", 1)
            if fx_index >= 0 then
                -- Recall the preset
                reaper.TakeFX_SetPreset(take, fx_index, preset_name)
            end
        end
    end
end
