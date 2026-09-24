--[[
Description: Hide all take envelopes for all items in the session
Version: 1.00
Author: Adapted by ChatGPT from Lokasenna's script
--]]

-- Licensed under the GNU GPL v3

local function Msg(str)
    reaper.ShowConsoleMsg(tostring(str) .. "\n")
end

local function hide_env_visibility(take, fx, param)
    local env = reaper.TakeFX_GetEnvelope(take, fx, param, false)
    if not env then return end

    local env = reaper.BR_EnvAlloc(env, false)
    local props = {reaper.BR_EnvGetProperties(env)}

    if props[2] == true then
        reaper.BR_EnvSetProperties(env, props[1], false, props[3], props[4], props[5], props[6], props[11])
    end

    reaper.BR_EnvFree(env, true)
end

local function iterate_FX_params(take, fx)
    local num_params = reaper.TakeFX_GetNumParams(take, fx)
    for i = 0, num_params - 1 do
        hide_env_visibility(take, fx, i)
    end    
end

local function iterate_take_FX(take)
    local num_FX = reaper.TakeFX_GetCount(take)
    if num_FX == 0 then return end
    for i = 0, num_FX - 1 do
        iterate_FX_params(take, i)
    end    
end

local function iterate_items()
    local num_items = reaper.CountMediaItems(0)
    if num_items == 0 then return end
    for i = 0, num_items - 1 do
        local item = reaper.GetMediaItem(0, i)
        local take_count = reaper.CountTakes(item)
        for j = 0, take_count - 1 do
            local take = reaper.GetTake(item, j)
            iterate_take_FX(take)
        end
    end        
end

local function Main()
    if not reaper.BR_EnvAlloc then
        reaper.MB("This script requires the SWS extension for Reaper.", "Whoops!", 0)
        return
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    iterate_items()

    reaper.PreventUIRefresh(-1)
    reaper.UpdateTimeline()
    reaper.Undo_EndBlock("Hide all take envelopes for all items", -1)
end

Main()

