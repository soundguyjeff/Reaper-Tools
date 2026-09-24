--[[
   * ReaScript Name: Copy take pan envelope from selected item to other selected items below
   * Lua script for Cockos REAPER
   * Author: Your Name
   * Licence: GPL v3
   * Version: 1.5
  ]]

function msg(m)
  reaper.ShowConsoleMsg(tostring(m) .. "\n")
end

-- Function to get and show take envelope
function get_and_show_take_envelope(take, envelope_name)
  local env = reaper.GetTakeEnvelopeByName(take, envelope_name)
  if env == nil then
    local item = reaper.GetMediaItemTake_Item(take)
    local sel = reaper.IsMediaItemSelected(item)
    if not sel then
      reaper.SetMediaItemSelected(item, true)
    end
    if envelope_name == "Volume" then reaper.Main_OnCommand(reaper.NamedCommandLookup("_S&M_TAKEENV1"), 0) -- show take volume envelope
    elseif envelope_name == "Pan" then reaper.Main_OnCommand(reaper.NamedCommandLookup("_S&M_TAKEENV2"), 0)    -- show take pan envelope
    elseif envelope_name == "Mute" then reaper.Main_OnCommand(reaper.NamedCommandLookup("_S&M_TAKEENV3"), 0)   -- show take mute envelope
    elseif envelope_name == "Pitch" then reaper.Main_OnCommand(reaper.NamedCommandLookup("_S&M_TAKEENV10"), 0) -- show take pitch envelope
    end
    if sel then
      reaper.SetMediaItemSelected(item, true)
    end
    env = reaper.GetTakeEnvelopeByName(take, envelope_name)
  end
  return env
end

-- Function to apply envelope points to the target envelope at correct positions
function apply_envelope_points(env, points, itemStartOffset)
  -- Insert envelope points into the envelope
  for _, point in ipairs(points) do
    reaper.InsertEnvelopePoint(env, point.time + itemStartOffset, point.value, 0, 0, true)
  end
  -- Sort the points
  reaper.Envelope_SortPoints(env)
end

-- Function to copy take pan envelope from the top selected item to other selected items below
function copy_take_pan_env_to_other_items_below()
  local numSelectedItems = reaper.CountSelectedMediaItems(0)
  
  if numSelectedItems < 2 then
    msg("Please select at least two items.")
    return
  end

  reaper.Undo_BeginBlock()
  
  -- Get the top selected item
  local topItem = reaper.GetSelectedMediaItem(0, 0)
  local topTake = reaper.GetActiveTake(topItem)
  
  if not topTake then
    msg("No active take found in the top selected item.")
    return
  end
  
  -- Get the pan envelope of the top selected item
  local sourceEnv = get_and_show_take_envelope(topTake, "Pan")
  if not sourceEnv then
    msg("No pan envelope found in the top selected item.")
    return
  end
  
  -- Retrieve the envelope points from the source envelope
  local envelopePoints = {}
  local numPoints = reaper.CountEnvelopePoints(sourceEnv)
  for i = 0, numPoints - 1 do
    local _, time, value = reaper.GetEnvelopePoint(sourceEnv, i)
    table.insert(envelopePoints, {time = time, value = value})
  end
  
  -- Iterate over other selected items below the top item
  for i = 1, numSelectedItems - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    
    if take then
      local env = get_and_show_take_envelope(take, "Pan")
      if env then
        -- Clear existing points in the target envelope
        local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local sourceItemStart = reaper.GetMediaItemInfo_Value(topItem, "D_POSITION")
        local offset = itemStart - sourceItemStart
        
        -- Apply envelope points with the correct time offset
        apply_envelope_points(env, envelopePoints, offset)
      end
    end
  end
  
  reaper.Undo_EndBlock("Copy take pan envelope to other selected items below", -1)
end

-- Run the function
copy_take_pan_env_to_other_items_below()

