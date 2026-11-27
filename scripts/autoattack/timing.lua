local Timing = {}
Timing.__index = Timing

function Timing.new()
    return setmetatable({}, Timing)
end

function Timing:GuardFrames(settings)
    local frames = settings.buffer_frames
    if type(frames) ~= "number" or frames ~= frames then frames = 2 end
    return math.max(0, math.min(6, math.floor(frames)))
end

function Timing:Timeout()
    return 1
end

return Timing
