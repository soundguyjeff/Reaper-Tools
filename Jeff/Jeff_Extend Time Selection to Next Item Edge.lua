-- REAPER Lua Script: Extend Time Selection to Next Item Edge on Selected Tracks and Select Items Under Time Selection

function extendTimeSelectionToNextItemEdgeOnSelectedTracks()
    -- Get the current project and time selection
    local project = 0
    local timeSelStart, timeSelEnd = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    
    -- If there is no time selection, use the edit cursor position as the start and end
    if timeSelStart == timeSelEnd then
        timeSelStart = reaper.GetCursorPosition()
        timeSelEnd = timeSelStart
    end

    -- Get the number of selected tracks
    local numSelectedTracks = reaper.CountSelectedTracks(project)
    
    -- Initialize variable to store the nearest item edge position
    local nearestItemEdge = nil
    
    -- Iterate over all selected tracks
    for i = 0, numSelectedTracks - 1 do
        local track = reaper.GetSelectedTrack(project, i)
        local numItems = reaper.CountTrackMediaItems(track)
        
        -- Iterate over all media items on the selected track
        for j = 0, numItems - 1 do
            local item = reaper.GetTrackMediaItem(track, j)
            local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local itemEnd = itemStart + itemLength
            
            -- Check if the item start or end is after the current time selection end
            if itemStart and itemEnd and timeSelEnd then
                if itemStart > timeSelEnd and (nearestItemEdge == nil or itemStart < nearestItemEdge) then
                    nearestItemEdge = itemStart
                end
                if itemEnd > timeSelEnd and (nearestItemEdge == nil or itemEnd < nearestItemEdge) then
                    nearestItemEdge = itemEnd
                end
            end
        end
    end
    
    -- If a nearest item edge is found, extend the time selection to it
    if nearestItemEdge then
        reaper.GetSet_LoopTimeRange(true, false, timeSelStart, nearestItemEdge, false)
    end
    
    -- Select items under the new time selection
    for i = 0, numSelectedTracks - 1 do
        local track = reaper.GetSelectedTrack(project, i)
        local numItems = reaper.CountTrackMediaItems(track)
        
        for j = 0, numItems - 1 do
            local item = reaper.GetTrackMediaItem(track, j)
            local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local itemEnd = itemStart + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            
            -- Check if item is within the time selection
            if itemStart and itemEnd and timeSelStart and nearestItemEdge then
                if itemStart < nearestItemEdge and itemEnd > timeSelStart then
                    reaper.SetMediaItemSelected(item, true)
                else
                    reaper.SetMediaItemSelected(item, false)
                end
            end
        end
    end
end

-- Run the function
extendTimeSelectionToNextItemEdgeOnSelectedTracks()

