-- Get the frame length in seconds
function getFrameLength()
    local frameRate = reaper.TimeMap_curFrameRate(0)
    if frameRate == 0 then
        frameRate = 30 -- default to 30 fps if frame rate is not available
    end
    return 1 / frameRate
end

-- Check if "Move envelope points with media items" is enabled
function isMoveEnvelopePointsWithItemsEnabled()
    return reaper.GetToggleCommandState(0, reaper.NamedCommandLookup("_SWS_MOVEENVPNTWITHITEMS")) == 1
end

-- Move entire selection left by 1 frame
function nudgeLeftBy1Frame()
    local frameLength = getFrameLength()
    local nudgeAmount = frameLength -- Nudge by 1 frame
    local timeSelStart, timeSelEnd = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    
    -- Adjust the time selection
    if timeSelStart ~= timeSelEnd then
        reaper.GetSet_LoopTimeRange(true, false, timeSelStart - nudgeAmount, timeSelEnd - nudgeAmount, false)
    end
    
    -- Check if "Move envelope points with media items" is enabled
    local moveEnvelopeWithItems = isMoveEnvelopePointsWithItemsEnabled()
    
    -- Adjust selected items
    local numSelectedItems = reaper.CountSelectedMediaItems(0)
    for i = 0, numSelectedItems - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", itemStart - nudgeAmount)
            
            if moveEnvelopeWithItems then
                -- Adjust envelopes within the time selection
                local itemTrack = reaper.GetMediaItem_Track(item)
                local numEnvelopes = reaper.CountTrackEnvelopes(itemTrack)
                for j = 0, numEnvelopes - 1 do
                    local envelope = reaper.GetTrackEnvelope(itemTrack, j)
                    local numPoints = reaper.CountEnvelopePoints(envelope)
                    for k = 0, numPoints - 1 do
                        local _, time, value = reaper.GetEnvelopePoint(envelope, k)
                        if time >= timeSelStart and time <= timeSelEnd then
                            reaper.SetEnvelopePoint(envelope, k, time - nudgeAmount, value, 0, 0, true)
                        end
                    end
                    reaper.Envelope_SortPoints(envelope)
                end
            end
        end
    end
    
    -- Adjust envelopes within the time selection if the setting is not enabled
    if not moveEnvelopeWithItems then
        local numTracks = reaper.CountTracks(0)
        for i = 0, numTracks - 1 do
            local track = reaper.GetTrack(0, i)
            local numEnvelopes = reaper.CountTrackEnvelopes(track)
            for j = 0, numEnvelopes - 1 do
                local envelope = reaper.GetTrackEnvelope(track, j)
                local numPoints = reaper.CountEnvelopePoints(envelope)
                for k = 0, numPoints - 1 do
                    local _, time, value = reaper.GetEnvelopePoint(envelope, k)
                    if time >= timeSelStart and time <= timeSelEnd then
                        reaper.SetEnvelopePoint(envelope, k, time - nudgeAmount, value, 0, 0, true)
                    end
                end
                reaper.Envelope_SortPoints(envelope)
            end
        end
    end

    -- Move the edit cursor left by 1 frame if no item is selected
    local cursorPos = reaper.GetCursorPosition()
    if numSelectedItems == 0 then
        reaper.SetEditCurPos(cursorPos - nudgeAmount, true, false)
    end
end

-- Run the function
nudgeLeftBy1Frame()

