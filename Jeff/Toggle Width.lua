-- Script: Toggle Track Width Envelope Visibility
-- Author: ChatGPT

-- Function to check if the "Width" envelope exists on the track
function GetWidthEnvelope(track)
    local envelopeCount = reaper.CountTrackEnvelopes(track)
    
    for i = 0, envelopeCount - 1 do
        local envelope = reaper.GetTrackEnvelope(track, i)
        local retval, envelopeName = reaper.GetEnvelopeName(envelope, "")
        
        if envelopeName == "Width" then
            return envelope
        end
    end
    
    return nil
end

-- Function to create the "Width" envelope on the track
function CreateWidthEnvelope(track)
    local widthEnvelope = GetWidthEnvelope(track)
    
    if widthEnvelope == nil then
        -- Create a new envelope and set its name
        widthEnvelope = reaper.CreateTrackEnvelope(track)
        reaper.GetSetEnvelopeName(widthEnvelope, "Width", true)
    end
    
    return widthEnvelope
end

-- Function to toggle track width envelope visibility
function ToggleTrackWidthEnvelopeVisibility()
    -- Get the currently selected track
    local track = reaper.GetSelectedTrack(0, 0) -- Gets the first selected track
    
    if track ~= nil then
        -- Check if the "Width" envelope exists, create it if necessary
        local widthEnvelope = CreateWidthEnvelope(track)
        
        -- Toggle visibility
        local _, visible = reaper.GetEnvelopeStateChunk(widthEnvelope, "", false)
        local newVisibility = visible == "VIS 1" and "VIS 0" or "VIS 1"
        reaper.SetEnvelopeStateChunk(widthEnvelope, newVisibility, false)
    else
        reaper.ShowMessageBox("No track selected.", "Error", 0)
    end
end

-- Run the function to toggle track width envelope visibility
ToggleTrackWidthEnvelopeVisibility()

