local Memory = include 'lib/memory'

local TranspositionMemory = setmetatable({}, Memory)
TranspositionMemory.__index = TranspositionMemory

TranspositionMemory.new = function()
	local mem = setmetatable(Memory.new(), TranspositionMemory)
	mem:initialize()
	return mem
end

function TranspositionMemory:get_slot_default(s)
	local transposition = {}
	local interval = (self.n_slots - s + 1) / 12
	local middle_voice = math.floor(n_voices / 2) + 1
	for v = 1, n_voices do
		transposition[v] = (middle_voice - v) * interval
	end
	return transposition
end

function TranspositionMemory:set(transposition, new_transposition)
	for v = 1, n_voices do
		transposition[v] = new_transposition[v]
	end
end

function TranspositionMemory:recall(transposition)
	for v = 1, n_voices do
		params:set(string.format('voice_%d_transpose', v), transposition[v] * 12)
	end
end

function TranspositionMemory:save(transposition)
	for v = 1, n_voices do
		transposition[v] = voices[v].pitch_tap.next_bias
	end
end

return TranspositionMemory
