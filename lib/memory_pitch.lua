local LoopMemory = include 'lib/memory_loop'

local PitchMemory = setmetatable({}, LoopMemory)
PitchMemory.__index = PitchMemory

PitchMemory.new = function()
	local mem = setmetatable(LoopMemory.new('pitch', pitch_registers[1], -3), PitchMemory)
	mem:initialize()
	return mem
end

local function sine(length)
	local amp = length / 24
	local step = math.pi * 2 / length
	local pattern = {}
	for i = 1, length do
		pattern[i] = math.sin(i * step) * amp
	end
	return pattern
end

function PitchMemory:get_slot_default_values(s)
	return sine(s + 3)
end

return PitchMemory
