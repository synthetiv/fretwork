local Control = include 'lib/grid_control'
local Select = include 'lib/grid_select'

local MemorySelector = setmetatable({}, Control)
MemorySelector.__index = MemorySelector

MemorySelector.new = function(x, y, width, height)
	local selector = setmetatable(Control.new(x, y, width, height), MemorySelector)
	local memory = {
		mask = {}
	}
	-- pre-fill with pentatonic scales
	local pentatonic = { 0, 2, 4, 7, 9 }
	for m = 1, height do
		local pitches = {}
		for n = 1, 5 do
			pitches[n] = ((pentatonic[n] + m * 7) % 12) / 12
		end
		memory.mask[m] = pitches
	end
	local mask_selector = Select.new(7, 1, 1, 7)
	mask_selector.on_select = function(m)
		if held_keys.shift then
			-- TODO: globals...!
			memory.mask[m] = scale:mask_to_pitches(scale.next_mask)
		else
			scale:mask_from_pitches(memory.mask[m])
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
	end
	selector.mask_selector = mask_selector
	return selector
end

function MemorySelector:draw(g)
	self.mask_selector:draw(g, 7, grid_view_selector:is_selected(5) and 4 or 2)
end

function MemorySelector:key(x, y, z)
	self.mask_selector:key(x, y, z)
end

function MemorySelector:reset()
end

return MemorySelector
