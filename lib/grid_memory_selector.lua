local Control = include 'lib/grid_control'
local Select = include 'lib/grid_select'

local MemorySelector = setmetatable({}, Control)
MemorySelector.__index = MemorySelector

local sine_sequence = include 'lib/sine_sequence'
local pentatonic = { 0, 2, 4, 7, 9 }
local euclidean_sequence = include 'lib/euclidean_sequence'

MemorySelector.new = function(x, y, width, height)
	local selector = setmetatable(Control.new(x, y, width, height), MemorySelector)

	local memory = {
		rate = {},
		pitch = {
			register = {},
			offset = {},
			mask = {},
			transpose = {}
		},
		mod = {
			register = {},
			offset = {}
		}
	}

	-- pre-fill memory banks
	for m = 1, height do

		-- rate: increasing spread + jitter
		local rates = {}
		for v = 1, n_voices do
			local voice = {}
			voice.rate = 4 + math.ceil((((v + m) % 2) * 2 - 1) * (v - 1) * (m - 1) / height)
			voice.jitter = math.pow(m / height, 2) / 4
			rates[v] = voice
		end
		memory.rate[m] = rates

		-- pitch offsets: increasing spread + scramble
		local pitch_offsets = {}
		for v = 1, n_voices do
			local voice = {}
			voice.offset = (v - 1) * m
			voice.scramble = math.pow(m / height, 2)
			pitch_offsets[v] = voice
		end
		memory.pitch.offset[m] = pitch_offsets

		-- pitch registers: sine waves
		local pitch_registers = {
			voices = {},
			loops = {}
		}
		for v = 1, n_voices do
			local voice = {}
			voice.register = math.floor(m * v / 6) % n_registers + 1
			voice.retrograde = math.floor(m * v / 10) % 2
			voice.inversion = math.floor(m * v / 12) % 2
			pitch_registers.voices[v] = voice
		end
		for r = 1, n_registers do
			pitch_registers.loops[r] = sine_sequence(m + r + 3, r / 3 + 1)
		end
		memory.pitch.register[m] = pitch_registers

		-- masks: pentatonic scales
		local pitches = {}
		for n = 1, 5 do
			pitches[n] = ((pentatonic[n] + m * 7) % 12) / 12
		end
		memory.pitch.mask[m] = pitches

		-- transpositions: decreasing spread + increasing noise
		local transpositions = {}
		local interval = (height - m + 1)
		local middle_voice = math.floor(n_voices / 2) + 1
		for v = 1, n_voices do
			local voice = {}
			voice.transpose = (middle_voice - v) * interval
			voice.noise = math.pow(m / height, 2)
			transpositions[v] = voice
		end
		memory.pitch.transpose[m] = transpositions

		-- mod offsets: increasing spread + scramble
		local mod_offsets = {}
		for v = 1, n_voices do
			local voice = {}
			voice.offset = (v - 1) * m
			voice.scramble = math.pow(m / height, 2)
			mod_offsets[v] = voice
		end
		memory.mod.offset[m] = mod_offsets

		-- mod registers: TODO
		local mod_registers = {
			voices = {},
			loops = {}
		}
		for v = 1, n_voices do
			local voice = {}
			voice.register = math.floor(m * v / 6) % n_registers + 1
			voice.retrograde = math.floor(m * v / 10) % 2
			voice.inversion = math.floor(m * v / 12) % 2
			mod_registers.voices[v] = voice
		end
		for r = 1, n_registers do
			mod_registers.loops[r] = euclidean_sequence(height - m + r, height + r)
		end
		memory.mod.register[m] = mod_registers

	end

	local selectors = {}

	selectors[grid_view_rate] = Select.new(3, 1, 1, height)
	selectors[grid_view_rate].on_select = function(m)
		if held_keys.shift then
			memory.rate[m] = rate_selector:get_state()
		else
			rate_selector:set_state(memory.rate[m])
		end
	end

	selectors[grid_view_pitch_offset] = Select.new(5, 1, 1, height)
	selectors[grid_view_pitch_offset].on_select = function(m)
		if held_keys.shift then
			memory.pitch.offset[m] = pitch_offset_roll:get_state()
		else
			pitch_offset_roll:set_state(memory.pitch.offset[m])
		end
	end

	selectors[grid_view_pitch_register] = Select.new(6, 1, 1, height)
	selectors[grid_view_pitch_register].on_select = function(m)
		if held_keys.shift then
			memory.pitch.register[m] = pitch_register_selector:get_state()
		else
			pitch_register_selector:set_state(memory.pitch.register[m])
		end
	end

	selectors[grid_view_mask] = Select.new(8, 1, 1, height)
	selectors[grid_view_mask].on_select = function(m)
		if held_keys.shift then
			-- TODO: globals...!
			memory.pitch.mask[m] = scale:get_mask_pitches(scale.next_mask)
		else
			scale:set_mask_to_pitches(memory.pitch.mask[m])
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

	selectors[grid_view_transpose] = Select.new(9, 1, 1, height)
	selectors[grid_view_transpose].on_select = function(m)
		local transpositions = memory.pitch.transpose[m]
		if held_keys.shift then
			for v = 1, n_voices do
				transpositions[v].transpose = voices[v].params.pitch.transpose
				transpositions[v].noise = voices[v].params.pitch.noise
			end
		else
			for v = 1, n_voices do
				voices[v].params.pitch.transpose = transpositions[v].transpose
				voices[v].params.pitch.noise = transpositions[v].noise
			end
		end
	end

	selectors[grid_view_mod_offset] = Select.new(11, 1, 1, height)
	selectors[grid_view_mod_offset].on_select = function(m)
		if held_keys.shift then
			memory.mod.offset[m] = mod_offset_roll:get_state()
		else
			mod_offset_roll:set_state(memory.mod.offset[m])
		end
	end

	selectors[grid_view_mod_register] = Select.new(12, 1, 1, height)
	selectors[grid_view_mod_register].on_select = function(m)
		if held_keys.shift then
			memory.mod.register[m] = mod_register_selector:get_state()
		else
			mod_register_selector:set_state(memory.mod.register[m])
		end
	end

	selector.memory = memory
	selector.selectors = selectors

	return selector
end

function MemorySelector:draw(g)
	for v = 1, n_grid_views do
		local selector = self.selectors[v]
		local view_selected = grid_view_selector:is_selected(v)
		if selector ~= nil then
			if view_selected then
				selector:draw(g, 12, 5)
			else
				selector:draw(g, 7, 2)
			end
		end
	end
end

function MemorySelector:key(x, y, z)
	for v = 1, n_grid_views do
		local selector = self.selectors[v]
		if selector ~= nil and selector:should_handle_key(x, y) then
			selector:key(x, y, z)
			return
		end
	end
end

function MemorySelector:reset()
end

return MemorySelector
