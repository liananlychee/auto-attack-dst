package.path = './scripts/?.lua;' .. package.path
local Timing = require 'autoattack/timing'
local timing = Timing.new()
for _, legacy_auto in ipairs({true,false}) do
    for n = 0, 6 do
        assert(timing:GuardFrames({buffer_frames = n, auto = legacy_auto}) == n)
    end
end
assert(timing:GuardFrames({buffer_frames = -1}) == 0)
assert(timing:GuardFrames({buffer_frames = 20}) == 6)
assert(timing:GuardFrames({buffer_frames = 2.8}) == 2)
assert(timing:GuardFrames({buffer_frames = 0/0}) == 2)
assert(timing:GuardFrames({}) == 2)
assert(timing:Timeout() == 1)
assert(timing.Sample == nil and timing.ping == nil and timing.variation == nil)
print('manual-only waiting, legacy automatic setting ignored and fixed timeout: passed')
