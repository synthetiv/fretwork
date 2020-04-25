local Memory = include 'lib/memory'

local MaskMemory = setmetatable({}, Memory)
MaskMemory.__index = MaskMemory

MaskMemory.new = function()
	local mem = setmetatable(Memory.new(), MaskMemory)
	mem:initialize()
	return mem
end

local pentatonic = { 0, 2, 4, 7, 9 }

function MaskMemory:get_slot_default(s)
	local pitches = {}
	for n = 1, 5 do
		pitches[n] = ((pentatonic[n] + s - 1) % 12) / 12
	end
	return pitches
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
		scale:apply_edits()
		-- force pitch values + paths to update
		for v = 1, n_voices do
			local voice = voices[v]
			voice.pitch_tap.dirty = true
			voice:update()
		end
	end
end

function MaskMemory:save(mask, s)
	self.slots[s] = scale:mask_to_pitches(scale.next_mask)
end

return MaskMemory
