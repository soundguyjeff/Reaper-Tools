-- @description Duplicate markers in time selection and razor edit areas and paste them at the end of the time selection
-- @version 1.7
-- @author ChatGPT
-- @metapackage
-- @provides
--   [main] . > DuplicateMarkersInTimeSelectionAndRazorEditAreasAtEnd.lua
-- @about
--   This script duplicates all markers within the current time selection and razor edit areas and pastes them at the end of the time selection. If no time selection is set and there are no razor edit areas, marker duplication is ignored.

-- Get the current time selection
local t_start, t_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

-- Function to get razor edit areas
local function GetRazorEditAreas()
    local razor_edit_areas = {}
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local ret, area = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
        if ret and area ~= "" then
            for area_start, area_end in area:gmatch("(%S+) (%S+) %S+") do
                local start_pos = tonumber(area_start)
                local end_pos = tonumber(area_end)
                table.insert(razor_edit_areas, {start = start_pos, end_ = end_pos})
            end
        end
    end
    return razor_edit_areas
end

-- Get razor edit areas
local razor_edit_areas = GetRazorEditAreas()

-- Calculate the end position for duplication
local duplicate_end = t_end
if #razor_edit_areas > 0 then
    -- Find the maximum end position of all razor edit areas
    for _, area in ipairs(razor_edit_areas) do
        if area.end_ > duplicate_end then
            duplicate_end = area.end_
        end
    end
end

-- Function to check if a position is within any razor edit area
local function IsWithinRazorEdit(pos, razor_edit_areas)
    for _, area in ipairs(razor_edit_areas) do
        if pos >= area.start and pos <= area.end_ then
            return true
        end
    end
    return false
end

-- Check if the time selection is valid or there are razor edit areas
if t_start ~= t_end or #razor_edit_areas > 0 then
    -- Get the number of markers
    local num_markers = reaper.CountProjectMarkers(0)
    
    -- Iterate through all markers
    for i = 0, num_markers - 1 do
        local retval, isrgn, pos, rgnend, name, markeridx, color = reaper.EnumProjectMarkers(i)
        
        -- Skip regions
        if not isrgn then
            -- Check if the marker is within the time selection
            local within_time_selection = pos >= t_start and pos <= t_end
            
            -- Check if the marker is within any razor edit area
            local within_razor_edit = IsWithinRazorEdit(pos, razor_edit_areas)
            
            -- Duplicate the marker if it is within the time selection or any razor edit area
            if within_time_selection or within_razor_edit then
                -- Calculate the new position for the marker
                local new_pos
                if within_razor_edit and t_start == t_end then
                    -- Use razor edit area start for position calculation
                    for _, area in ipairs(razor_edit_areas) do
                        if pos >= area.start and pos <= area.end_ then
                            new_pos = duplicate_end + (pos - area.start)
                            break
                        end
                    end
                else
                    new_pos = duplicate_end + (pos - t_start)
                end
                
                -- Add the duplicated marker at the new position
                reaper.AddProjectMarker(0, false, new_pos, 0, name, -1)
            end
        end
    end
    
    -- Update the arrange view to reflect the new markers
    reaper.UpdateArrange()
else
    -- Optional: Show a message box if no time selection is set and there are no razor edit areas (can be removed if not needed)
    -- reaper.ShowMessageBox("No time selection or razor edit areas set. Marker duplication ignored.", "Info", 0)
end

