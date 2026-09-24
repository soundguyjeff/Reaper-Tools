-- Get the number of selected items
local num_selected_items = reaper.CountSelectedMediaItems(0)

-- Check if there are selected items
if num_selected_items > 0 then
    -- Initialize variables
    local first_item_start_pos = nil
    local found_item = false

    -- Iterate through selected items to find the first audio or video item
    for i = 0, num_selected_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local item_start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_source = reaper.GetMediaItemInfo_Value(item, "P_SOURCE")
        
        if item_source then -- Check if the item has a source (could be audio or video)
            first_item_start_pos = item_start_pos
            found_item = true
            break
        end
    end

    if found_item then
        -- Insert a marker at the start position of the first selected item
        reaper.AddProjectMarker(0, false, first_item_start_pos, 0, "Start", -1)
        -- Update the arrange view to reflect the new marker
        reaper.UpdateArrange()
    else
        -- Show a message box if no valid items are found
        reaper.ShowMessageBox("No audio or video items selected. Please select an item to add the marker.", "Error", 0)
    end
else
    -- Show a message box if no items are selected
    reaper.ShowMessageBox("No items selected. Please select an item to add the marker.", "Error", 0)
end

