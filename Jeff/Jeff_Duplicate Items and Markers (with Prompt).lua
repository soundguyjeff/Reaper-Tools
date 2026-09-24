-- REAPER Lua Script: Duplicate Items and Markers within Time Selection

-- Function to duplicate items
function duplicateItems(numDuplicates, timeBetweenDuplicates)
    local retval, timeSelStart, timeSelEnd, _ = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    
    -- Check if time selection is valid
    if not retval or timeSelStart == 0 and timeSelEnd == 0 then
        reaper.ShowMessageBox("No time selection found!", "Error", 0)
        return
    end
    
    local items = {}
    local itemCount = reaper.CountMediaItems(0)
    
    -- Collect items within time selection
    for i = 0, itemCount - 1 do
        local item = reaper.GetMediaItem(0, i)
        local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local itemEnd = itemStart + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        
        if (itemStart >= timeSelStart and itemStart < timeSelEnd) or (itemEnd > timeSelStart and itemEnd <= timeSelEnd) then
            table.insert(items, item)
        end
    end
    
    -- Duplicate items
    for _, item in ipairs(items) do
        local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        
        for i = 1, numDuplicates do
            local newItemStart = itemStart + i * timeBetweenDuplicates
            reaper.Main_OnCommand(40317, 0)  -- Command ID to duplicate items (ensure this ID is correct for your version)
            local newItem = reaper.GetSelectedMediaItem(0, 0) -- Get the new duplicated item
            if newItem then
                reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", newItemStart)
                reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", itemLength)
            end
        end
    end
end

-- Function to duplicate markers
function duplicateMarkers(numDuplicates, timeBetweenDuplicates)
    local retval, timeSelStart, timeSelEnd, _ = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    
    -- Check if time selection is valid
    if not retval or timeSelStart == 0 and timeSelEnd == 0 then
        reaper.ShowMessageBox("No time selection found!", "Error", 0)
        return
    end
    
    local markerCount = reaper.CountProjectMarkers(0) -- Correct function to count markers
    
    -- Duplicate markers
    for i = 0, markerCount - 1 do
        local _, markerPos, markerName, markerColor = reaper.EnumProjectMarkers3(0, i)
        
        if markerPos >= timeSelStart and markerPos <= timeSelEnd then
            for j = 1, numDuplicates do
                local newMarkerPos = markerPos + j * timeBetweenDuplicates
                reaper.AddProjectMarker(0, false, newMarkerPos, 0, markerName, markerColor)
            end
        end
    end
end

-- Prompt user for number of duplicates and time between duplicates
local retval, userInput = reaper.GetUserInputs("Duplicate Items and Markers", 2, "Number of Duplicates:,Time Between Duplicates (seconds):", "2,1")
if retval then
    local numDuplicates, timeBetweenDuplicates = userInput:match("([^,]+),([^,]+)")
    numDuplicates = tonumber(numDuplicates)
    timeBetweenDuplicates = tonumber(timeBetweenDuplicates)
    
    if numDuplicates and timeBetweenDuplicates and numDuplicates > 0 and timeBetweenDuplicates >= 0 then
        reaper.Undo_BeginBlock()
        duplicateItems(numDuplicates, timeBetweenDuplicates)
        duplicateMarkers(numDuplicates, timeBetweenDuplicates)
        reaper.Undo_EndBlock("Duplicate Items and Markers", -1)
    else
        reaper.ShowMessageBox("Invalid input. Please enter positive numbers for number of duplicates and non-negative numbers for time between duplicates.", "Error", 0)
    end
end

