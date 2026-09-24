-- Move edit cursor to mouse position without selecting the item under the mouse

function main()
  -- Get mouse cursor position in arrange view
  local window, segment, details = reaper.BR_GetMouseCursorContext()
  if segment == "arrange" then
    -- Get the mouse cursor position in time
    local mouse_pos = reaper.BR_GetMouseCursorContext_Position()
    -- Store current item selection
    local selected_items = {}
    local num_selected_items = reaper.CountSelectedMediaItems(0)
    for i = 0, num_selected_items - 1 do
      selected_items[#selected_items + 1] = reaper.GetSelectedMediaItem(0, i)
    end
    -- Prevent item selection
    reaper.Main_OnCommand(40289, 0) -- Unselect all items
    -- Set the edit cursor position to the mouse cursor position
    reaper.SetEditCurPos(mouse_pos, true, false)
    -- Restore item selection
    for _, item in ipairs(selected_items) do
      reaper.SetMediaItemSelected(item, true)
    end
  end
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Move edit cursor to mouse position", -1)

