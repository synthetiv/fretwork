local Memory = include 'lib/memory'

local MaskMemory = setmetatable({}, Memory)
MaskMemory.__index = MaskMemory

MaskMemory.new = function()
	local mem = setmetatable(Memory.new(), MaskMemory)
	tab.print(mem)
	for s = 1, mem.n_slots do
		-- TODO: this is throwing out the existing tables...! evil? ok?
		mem.slots[s] = { 0, 2/12, 4/12, 5/12, 7/12, 9/12, 11/12 } -- C major
	end
	return mem
end

function MaskMemory:set(mask, new_mask)
	for i = 1, #mask do
		mask[i] = nil
	end
	for i, v in ipairs(new_mask) do
		mask[i] = v
	end
end

function MaskMemory:recall(mask)
	scale:mask_from_pitches(mask)
	if quantization_off() then
		update_voices()
	end
end

function MaskMemory:save(mask, s)
	self.slots[s] = scale:mask_to_pitches(scale.next_mask)
end

return MaskMemory
