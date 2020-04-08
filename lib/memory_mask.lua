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
	scale:set_next_mask(scale:pitches_to_mask(mask))
	if quantization_off() then
		update_voices()
	end
end

-- TODO: this is weird as hell
-- maybe copy_mask should take a source and a destination!!
-- ...but even then it would do something pretty similar to this
function MaskMemory:save(mask)
	local new_mask = scale:mask_to_pitches(scale:get_next_mask())
	for i = 1, #mask do
		mask[i] = nil
	end
	for i, v in ipairs(new_mask) do
		mask[i] = v
	end
end

return MaskMemory
