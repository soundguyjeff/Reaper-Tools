--[[
  ReaScript Name: Toggle Solo Exclusive Selected Tracks
  Instructions: Run to toggle the solo state of selected tracks. Run again to reverse the action.
  Author: X-Raym
  Author URI: https://www.extremraym.com
  Repository: GitHub > X-Raym > REAPER-ReaScripts
  Repository URI: https://github.com/X-Raym/REAPER-ReaScripts
  Licence: GPL v3
  Forum Thread:
  Forum Thread URI:
  REAPER: 5 pre 21
  Version: 2
--]]

-- Function to toggle solo state
function toggle_solo()
  local any_soloed = false
  local selected_tracks = {}

  -- Collect selected tracks
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    table.insert(selected_tracks, reaper.GetSelectedTrack(0, i))
  end

  -- Check if any selected track is soloed
  for i = 1, #selected_tracks do
    if reaper.GetMediaTrackInfo_Value(selected_tracks[i], "I_SOLO") == 1 then
      any_soloed = true
      break
    end
  end

  if any_soloed then
    -- Unsilo all tracks if any selected track is soloed
    for i = 0, reaper.CountTracks(0) - 1 do
      local track = reaper.GetTrack(0, i)
      if reaper.IsTrackSelected(track) == 0 then
        reaper.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
      end
    end
  else
    -- Solo all selected tracks if none are soloed
    for i = 1, #selected_tracks do
      reaper.SetMediaTrackInfo_Value(selected_tracks[i], "I_SOLO", 1)
    end

    -- Unsilo all non-selected tracks
    for i = 0, reaper.CountTracks(0) - 1 do
      local track = reaper.GetTrack(0, i)
      if reaper.IsTrackSelected(track) == 0 then
        reaper.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
      end
    end
  end
end

-- Main script execution
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
toggle_solo()
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Toggle Solo Exclusive Selected Tracks", -1)

