local Memory = include 'lib/memory'

local TranspositionMemory = setmetatable({}, Memory)
TranspositionMemory.__index = TranspositionMemory

TranspositionMemory.new = function()
	local mem = setmetatable(Memory.new(), TranspositionMemory)
	for s = 1, mem.n_slots do
		local transposition = {}
		for v = 1, n_voices do
			transposition[v] = 0.75 - v / 4
		end
		mem.slots[s] = transposition
	end
	return mem
end

function TranspositionMemory:set(transposition, new_transposition)
	for v = 1, n_voices do
		transposition[v] = new_transposition[v]
	end
end

function TranspositionMemory:recall(transposition)
	for v = 1, n_voices do
		params:set(string.format('voice_%d_transpose', v), transposition[v])
	end
	if quantization_off() then
		update_voices()
	end
end

function TranspositionMemory:save(transposition)
	for v = 1, n_voices do
		transposition[v] = voices[v].next_transpose
	end
	transposition_dirty = false
end

return TranspositionMemory
