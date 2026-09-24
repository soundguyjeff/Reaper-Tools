-- Initialize variables
local num_selected_items = reaper.CountSelectedMediaItems(0)
local last_item = nil
local item_end_position = 0

-- Iterate through all selected items to find the end of the last item
for i = 0, num_selected_items - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local item_position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_position + item_length

    -- Update the last item and end position
    if item_end > item_end_position then
        last_item = item
        item_end_position = item_end
    end
end

-- Move the edit cursor to the end of the last item
if last_item then
    reaper.SetEditCurPos(item_end_position, true, false)
end

-- Update the arrange view to reflect the cursor movement
reaper.UpdateArrange()

