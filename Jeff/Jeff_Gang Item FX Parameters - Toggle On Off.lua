-- User-defined parameters
local fx_index = 0 -- FX index in the chain (0-based)
local param_index = 0 -- Parameter index to synchronize (0-based)

-- Function to get the FX parameter value from the first selected item
function GetParamValue()
  local first_item = reaper.GetSelectedMediaItem(0, 0)
  local take = reaper.GetActiveTake(first_item)
  local track = reaper.GetMediaItemTake_Track(take)
  return reaper.TrackFX_GetParam(track, fx_index, param_index)
end

-- Function to set the FX parameter value on all selected items
function SetParamValue(value)
  local item_count = reaper.CountSelectedMediaItems(0)
  for i = 0, item_count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    local track = reaper.GetMediaItemTake_Track(take)
    reaper.TrackFX_SetParam(track, fx_index, param_index, value)
  end
end

-- Main loop
function Main()
  reaper.Undo_BeginBlock() -- Begin the undo block
  local param_value = GetParamValue()
  SetParamValue(param_value)
  reaper.Undo_EndBlock("Gang FX Parameter", -1) -- End the undo block
end

-- Continuously execute the main function
function Run()
  while true do
    Main()
    reaper.defer(Run) -- Defer to the next cycle
  end
end

-- Start the script
Run()

