-- follower
-- follow pitch, quantize, etc...

engine.name = 'Vessel'

VesselWaveform = include 'vessel/lib/waveform'
VesselEngine = include 'vessel/lib/engine'

local musicutil = require 'musicutil'

local Keyboard = include 'lib/grid_keyboard'
local Select = include 'lib/grid_select'
local MultiSelect = include 'lib/grid_multi_select'
local ShiftRegister = include 'lib/shift_register'
local Scale = include 'lib/scale'

local pitch_poll
local pitch_in = 0
local pitch_in_detected = false
local pitch_in_octave = 0
local crow_pitch_in = 0
local scale = Scale.new(12)
local saved_masks = {} -- TODO: save with params... somehow
-- idea: use a 'data file' param, so it can be changed; the hardest part will be naming new files, I think
local mask_dirty = false
local mask_selector = Select.new(1, 3, 4, 4)

local transposition_dirty = false
local saved_transpositions = {}
local transposition_selector = Select.new(1, 3, 4, 4)

local saved_loops = {}
local loop_selector = Select.new(1, 3, 4, 4)

local memory_selector = Select.new(2, 2, 3, 1)
local memory_mask = 1
local memory_transposition = 2
local memory_loop = 3

-- TODO: save/recall mask, loop, and transposition all at once

local shift_register = ShiftRegister.new(32)

local source
local source_names = {
	'grid',
	'pitch track',
	'crow input 2',
	'grid OR pitch',
	'grid OR crow',
	'pitch OR grid'
	-- TODO: random too?
}
local source_grid = 1
local source_pitch = 2
local source_crow = 3
local source_grid_pitch = 4
local source_grid_crow = 5
local source_pitch_grid = 6

-- TODO: add internal clock using beatclock
-- TODO: clock from MIDI notes
local clock_mode
local clock_mode_names = {
	'crow input 1',
	'grid',
	'crow in OR grid'
}
local clock_mode_trig = 1
local clock_mode_grid = 2
local clock_mode_trig_grid = 3

local output_transpose = { 0, 0, 0, 0 }
local output_note = { 0, 0, 0, 0 }
local output_source = { 0, 0, 0, 0 }
local output_source_names = {
	'head 1',
	'head 2',
	'head 3',
	'head 4',
	'audio in',
	'grid'
}
local output_source_head_1 = 1
local output_source_head_2 = 2
local output_source_head_3 = 3
local output_source_head_4 = 4
local output_source_audio_in = 5
local output_source_grid = 6
local output_stream = { false, false, false, false }

local active_heads = { false, false, false, false }
local selected_heads = { false, false, false, false }

local grid_mode_play = 1
local grid_mode_mask = 2
local grid_mode_transpose = 3
local grid_mode_edit = 4
local grid_mode = grid_mode_play

local output_selector = MultiSelect.new(5, 3, 1, 4)

local g = grid.connect()

local grid_shift = false
local grid_ctrl = false
local grid_octave_key_held = false
local input_keyboard = Keyboard.new(6, 1, 11, 8, scale)
local control_keyboard = Keyboard.new(6, 1, 11, 8, scale)
local keyboard = input_keyboard

local screen_note_width = 4
local n_screen_notes = 128 / screen_note_width
local screen_note_center = math.floor((n_screen_notes - 1) / 2)

local blink_slow = false
local blink_fast = false
local dirty = false
local redraw_metro

local function recall_mask()
	if saved_masks[mask_selector.selected] == nil then
		return
	end
	scale:set_mask(saved_masks[mask_selector.selected])
	mask_dirty = false
end

local function save_mask()
	saved_masks[mask_selector.selected] = scale:get_mask()
	mask_dirty = false
end

local function recall_loop()
	if saved_loops[loop_selector.selected] == nil then
		return
	end
	shift_register:set_loop(saved_loops[loop_selector.selected])
	shift_register.dirty = false
end

local function save_loop()
	saved_loops[loop_selector.selected] = shift_register:get_loop()
	shift_register.dirty = false
end

local function recall_transposition()
	local t = transposition_selector.selected
	if saved_transpositions[t] == nil then
		return
	end
	for o = 1, 4 do
		params:set(string.format('output_%d_transpose', o), saved_transpositions[t][o])
	end
	transposition_dirty = false
end

local function save_transposition()
	local transposition = {}
	for o = 1, 4 do
		transposition[o] = params:get(string.format('output_%d_transpose', o))
	end
	saved_transpositions[transposition_selector.selected] = transposition
	transposition_dirty = false
end

local function update_output(out)
	local output_source = output_source[out]
	local volts = 0
	if output_source == output_source_audio_in then
		output_note[out] = scale:snap(pitch_in + output_transpose[out])
	elseif output_source == output_source_grid then
		output_note[out] = scale:snap(input_keyboard:get_last_note() + output_transpose[out])
	else
		local output_head = output_source
		output_note[out] = scale:snap(shift_register:read_head(output_head) + output_transpose[out])
	end
	volts = output_note[out] / 12 - 1
	dirty = true
	crow.output[out].volts = volts
end

local function sample_pitch()
	shift_register:shift(1)
	if params:get('write_probability') > math.random(1, 100) then
		if source == source_crow then
			shift_register:write_head(crow_pitch_in)
		elseif input_keyboard.gate and (source == source_grid or source == source_grid_pitch or source == source_grid_crow) then
			shift_register:write_head(input_keyboard:get_last_note())
		elseif pitch_in_detected and (source == source_grid_pitch or source == source_pitch or source == source_pitch_grid) then
			shift_register:write_head(pitch_in)
		elseif source == source_grid_crow then
			shift_register:write_head(crow_pitch_in)
		elseif input_keyboard.gate and source == source_pitch_grid then
			shift_register:write_head(input_keyboard:get_last_note())
		end
	end
	for out = 1, 4 do
		if not output_stream[out] then
			update_output(out)
		end
	end
	dirty = true
end

local function rewind()
	shift_register:shift(-1)
	for out = 1, 4 do
		if not output_stream[out] then
			update_output(out)
		end
	end
	dirty = true
end

local function update_active_heads()
	active_heads = { false, false, false, false }
	selected_heads = { false, false, false, false }
	for o = 1, 4 do
		local source = output_source[o]
		if source ~= nil and source >= output_source_head_1 and source <= output_source_head_4 then
			active_heads[source] = true
			if output_selector:is_selected(o) then
				selected_heads[source] = true
			end
		end
	end
end

local function grid_redraw()

	-- mode buttons
	g:led(1, 1, grid_mode == grid_mode_play and 7 or 2)
	g:led(2, 1, grid_mode == grid_mode_mask and 7 or 2)
	g:led(3, 1, grid_mode == grid_mode_transpose and 7 or 2)
	g:led(4, 1, grid_mode == grid_mode_edit and 7 or 2)

	-- recall mode buttons
	memory_selector:draw(g, 7, 2)

	-- recall buttons
	if memory_selector:is_selected(memory_mask) then
		mask_selector:draw(g, mask_dirty and blink_slow and 8 or 7, 2)
	elseif memory_selector:is_selected(memory_transposition) then
		transposition_selector:draw(g, transposition_dirty and blink_slow and 8 or 7, 2)
	else
		loop_selector:draw(g, shift_register.dirty and blink_slow and 8 or 7, 2)
	end

	-- shift + ctrl
	g:led(1, 7, grid_shift and 15 or 2)
	g:led(1, 8, grid_ctrl and 15 or 2)

	-- output buttons
	output_selector:draw(g, 10, 5)

	-- keyboard octaves
	g:led(3, 8, 2 - math.min(keyboard.octave, 0))
	g:led(4, 8, 2 + math.max(keyboard.octave, 0))

	-- keyboard
	keyboard:draw(g)
	g:refresh()
end

local key_level_callbacks = {}

key_level_callbacks[grid_mode_play] = function(self, x, y, n)
	local level = 0
	-- highlight mask
	if self.scale:contains(n) then
		level = 4
	end
	-- highlight output notes
	for o = 1, 4 do
		if n == output_note[o] then
			if output_selector:is_selected(o) then
				level = 10
			else
				level = math.max(level, 5)
			end
		end
	end
	-- highlight current note
	if self.gate and self:is_key_last(x, y) then
		level = 15
	end
	return level
end

key_level_callbacks[grid_mode_mask] = function(self, x, y, n)
	local level = 0
	-- highlight white keys
	if self:is_white_key(n) then
		level = 2
	end
	-- highlight mask
	if self.scale:contains(n) then
		level = 5
	end
	-- highlight output notes
	for o = 1, 4 do
		if n == output_note[o] then
			if output_selector:is_selected(o) then
				level = 10
			else
				level = math.max(level, 5)
			end
		end
	end
	return level
end

key_level_callbacks[grid_mode_transpose] = function(self, x, y, n)
	local level = 0
	-- highlight octaves
	if n % self.scale.length == 0 then
		level = 2
	end
	-- highlight transposition settings
	for i = 1, 4 do
		if n - 36 == params:get('output_' .. i .. '_transpose') then
			if output_selector:is_selected(i) then
				level = 10
			elseif level < 5 then
				level = 5
			end
		end
	end
	return level
end

key_level_callbacks[grid_mode_edit] = function(self, x, y, n)
	local level = 0
	-- highlight mask
	if self.scale:contains(n) then
		level = 3
	end
	-- highlight un-transposed output notes
	for o = 1, 4 do
		if output_source[o] >= output_source_head_1 and output_source[o] <= output_source_head_4 then
			if n == self.scale:snap(shift_register:read_head(output_source[o])) then
				level = 7
			end
		end
	end
	-- highlight snapped version of the note at the cursor
	if n == scale:snap(shift_register:read_cursor()) then
		level = 10
	end
	-- highlight + blink the un-snapped note we're editing
	if n == shift_register:read_cursor() then
		if blink_fast then
			level = 15
		else
			level = 14
		end
	end
	return level
end

local function grid_octave_key(z, d)
	if z == 1 then
		if grid_octave_key_held then
			keyboard.octave = 0
		else
			keyboard.octave = keyboard.octave + d
		end
		if grid_mode == grid_mode_play and keyboard.gate then
			-- change octave of current note
			keyboard_note = keyboard:get_last_note()
		end
		-- update streaming outputs
		for out = 1, 4 do
			if output_source[out] == output_source_grid and output_stream[out] then
				update_output(out)
			end
		end
	end
	grid_octave_key_held = z == 1
end

local function grid_key(x, y, z)
	if keyboard:should_handle_key(x, y) then
		if grid_mode == grid_mode_play and not grid_shift then
			keyboard:note(x, y, z)
			keyboard_note = keyboard:get_last_note()
			if keyboard.gate then
				if clock_mode ~= clock_mode_trig then
					sample_pitch()
				end
				for out = 1, 4 do
					if output_source[out] == output_source_grid and output_stream[out] then
						update_output(out)
					end
				end
			end
		elseif grid_mode == grid_mode_mask or (grid_mode == grid_mode_play and grid_shift) then
			if z == 1 then
				local n = keyboard:get_key_note(x, y)
				scale:toggle_class(n)
				mask_dirty = true
				if grid_ctrl then
					for out = 1, 4 do
						update_output(out)
					end
				end
			end
		elseif grid_mode == grid_mode_transpose then
			keyboard:note(x, y, z)
			if keyboard.gate then
				local transpose = math.min(72, math.max(0, keyboard:get_last_note())) - 36
				for o = 1, 4 do
					if output_selector:is_selected(o) then
						params:set('output_' .. o .. '_transpose', transpose)
					end
				end
			end
		elseif grid_mode == grid_mode_edit then
			keyboard:note(x, y, z)
			if keyboard.gate then
				local note = keyboard:get_last_note()
				shift_register:write_cursor(note)
				-- update outputs immediately, if appropriate
				for h = 1, shift_register.n_read_heads do
					if shift_register.read_heads[h].offset == shift_register.cursor then
						for o = 1, 4 do
							if output_source[o] == h then
								update_output(o)
							end
						end
					end
				end
			end
		end
	elseif output_selector:should_handle_key(x, y) then
		-- TODO: what should these do in modes other than transpose?
		output_selector:key(x, y, z)
		update_active_heads()
		-- in edit mode, jump to the selected output's offset
		-- TODO: make the cursor follow this output until it's explicitly moved?
		if grid_mode == grid_mode_edit and z == 1 then
			local output = output_selector:get_key_option(x, y)
			local source = output_source[output]
			if source >= output_source_head_1 and source <= output_source_head_4 then
				shift_register.cursor = shift_register:clamp_loop_offset(shift_register.read_heads[source].offset)
			end
		end
	elseif x == 3 and y == 8 then
		grid_octave_key(z, -1)
	elseif x == 4 and y == 8 then
		grid_octave_key(z, 1)
	elseif x < 5 and y == 1 and z == 1 then
		-- grid mode buttons
		if x == 1 then
			grid_mode = grid_mode_play
			keyboard = input_keyboard
		elseif x == 2 then
			grid_mode = grid_mode_mask
			keyboard = control_keyboard
		elseif x == 3 then
			grid_mode = grid_mode_transpose
			keyboard = control_keyboard
		elseif x == 4 then
			grid_mode = grid_mode_edit
			keyboard = control_keyboard
		end
		-- set the grid drawing routine based on new mode
		keyboard.get_key_level = key_level_callbacks[grid_mode]
		-- clear held note stack, in order to prevent held notes from getting stuck when switching to a
		-- mode that doesn't call `keyboard:note()`
		keyboard:reset()
	elseif memory_selector:should_handle_key(x, y) then
		memory_selector:key(x, y, z)
	elseif memory_selector:is_selected(memory_mask) and mask_selector:should_handle_key(x, y) then
		mask_selector:key(x, y, z)
		if grid_shift then
			save_mask()
		else
			recall_mask()
			if grid_ctrl then
				for out = 1, 4 do
					update_output(out)
				end
			end
		end
	elseif memory_selector:is_selected(memory_transposition) and transposition_selector:should_handle_key(x, y) then
		transposition_selector:key(x, y, z)
		if grid_shift then
			save_transposition()
		else
			recall_transposition()
		end
	elseif memory_selector:is_selected(memory_loop) and loop_selector:should_handle_key(x, y) then
		loop_selector:key(x, y, z)
		if grid_shift then
			save_loop()
		else
			recall_loop()
			if grid_ctrl then
				for out = 1, 4 do
					if output_source[out] >= output_source_head_1 and output_source[out] <= output_source_head_4 then
						update_output(out)
					end
				end
			end
		end
	elseif x == 1 and y == 7 then
		-- shift key
		grid_shift = z == 1
	elseif x == 1 and y == 8 then
		-- ctrl key
		if x == 1 then
			grid_ctrl = z == 1
		end
	end
	dirty = true
end

local function update_freq(value)
	pitch_in_detected = value > 0
	if pitch_in_detected then
		-- TODO: accommodate non-12TET scales
		pitch_in = musicutil.freq_to_note_num(value) + (pitch_in_octave - 2) * scale.length
		for out = 1, 4 do
			if output_source[out] == output_source_audio_in and output_stream[out] then
				update_output(out)
			end
		end
		dirty = true
	end
end

local function crow_setup()
	crow.clear()
	-- input modes will be set by params
	crow.input[1].change = function()
		if clock_mode ~= clock_mode_grid then
			sample_pitch()
		end
	end
	crow.input[2].stream = function(value)
		-- TODO: accommodate non-12TET scales
		crow_pitch_in = math.floor(value * scale.length + 0.5)
		print(string.format('crow input 2: %fV = %d', value, crow_pitch_in))
	end
	params:bang()
end

local function add_params()
	-- TODO: read from crow input 2
	-- TODO: and/or add a grid control
	params:add{
		type = 'option',
		id = 'shift_source',
		name = 'sr source',
		options = source_names,
		default = source_grid_pitch,
		action = function(value)
			source = value
			if source == source_crow then
				crow.input[2].mode('stream', 1/32) -- TODO: is this too fast? not fast enough? what about querying?
			else
				crow.input[2].mode('none')
			end
		end
	}
	params:add{
		type = 'control',
		id = 'write_probability',
		name = 'write probability',
		controlspec = controlspec.new(1, 101, 'exp', 1, 1),
		formatter = function(param)
			return string.format('%1.f%%', param:get() - 1)
		end
	}
	params:add{
		type = 'option',
		id = 'shift_clock',
		name = 'sr/s+h clock',
		options = clock_mode_names,
		default = clock_mode_trig,
		action = function(value)
			clock_mode = value
			if clock_mode ~= clock_mode_grid then
				crow.input[1].mode('change', 2.0, 0.25, 'rising')
			else
				crow.input[1].mode('none')
			end
		end
	}
	params:add{
		type = 'number',
		id = 'pitch_in_octave',
		name = 'pitch in octave',
		min = -2,
		max = 2,
		default = 0,
		action = function(value)
			pitch_in_octave = value
		end
	}
	
	params:add_separator()
	
	for i = 1, shift_register.n_read_heads do
		local head = shift_register.read_heads[i]
		params:add{
			type = 'number',
			id = 'head_' .. i .. '_offset',
			name = 'head ' .. i .. ' offset',
			min = -15,
			max = 16,
			default = i * -3,
			action = function(value)
				head.offset_base = value
				head:update(true)
				for o = 1, 4 do
					if output_source[o] == i then
						update_output(o)
					end
				end
				dirty = true
			end
		}
		params:add{
			type = 'number',
			id = 'head_' .. i .. '_offset_random',
			name = 'head ' .. i .. ' offset random',
			min = 0,
			max = 31,
			default = 0,
			action = function(value)
				head.randomness = value
				dirty = true
			end
		}
	end
	
	params:add{
		type = 'number',
		id = 'loop_length',
		name = 'loop length',
		min = 2,
		max = 32,
		default = 16,
		action = function(value)
			shift_register:set_length(value)
			for o = 1, 4 do
				-- TODO: this nil comparison is only necessary because of the order of params; should they
				-- be reordered anyway?
				if output_source[o] ~= nil and output_source[o] < 5 then
					update_output(o)
				end
			end
			dirty = true
		end
	}
	
	params:add_separator()
	
	for out = 1, 4 do
		params:add{
			type = 'option',
			id = 'output_' .. out .. '_source',
			name = 'out ' .. out .. ' source',
			options = output_source_names,
			default = out,
			action = function(value)
				output_source[out] = value
				update_active_heads()
				update_output(out)
			end
		}
		params:add{
			type = 'option',
			id = 'output_' .. out .. '_rate',
			name = 'out ' .. out .. ' rate',
			options = { 's+h', 'stream' },
			default = 1,
			action = function(value)
				output_stream[out] = value == 2
			end
		}
		params:add{
			type = 'control',
			id = 'output_' .. out .. '_slew',
			name = 'out ' .. out .. ' slew',
			controlspec = controlspec.new(1, 1000, 'exp', 1, 1, 'ms'),
			action = function(value)
				crow.output[out].slew = value / 1000
			end
		}
		params:add{
			type = 'number',
			id = 'output_' .. out .. '_transpose',
			name = 'out ' .. out .. ' transpose',
			min = -36,
			max = 36,
			default = 0,
			formatter = function(param)
				local value = param:get()
				if value > 0 then
					return string.format('+%d st', value)
				end
				return string.format('%d st', value)
			end,
			action = function(value)
				output_transpose[out] = value
				update_output(out)
				transposition_dirty = true
			end
		}
	end
end

function init()

	VesselEngine.add_params()
	params:add_separator()
	add_params()

	crow.add = crow_setup -- when crow is connected
	crow_setup() -- calls params:bang()
	
	-- initialize grid controls
	grid_mode = grid_mode_play
	keyboard.get_key_level = key_level_callbacks[grid_mode]
	output_selector:reset(true)

	redraw_metro = metro.init()
	redraw_metro.event = function(tick)
		-- TODO: stop blinking after n seconds of inactivity?
		if not blink_slow and tick % 8 > 3 then
			blink_slow = true
			dirty = true
		elseif blink_slow and tick % 8 <= 3 then
			blink_slow = false
			dirty = true
		end
		if not blink_fast and tick % 4 > 1 then
			blink_fast = true
			dirty = true
		elseif blink_fast and tick % 4 <= 1 then
			blink_fast = false
			dirty = true
		end
		if dirty then
			grid_redraw()
			redraw()
			dirty = false
		end
	end
	redraw_metro:start(1 / 15)
	
	engine.pitchAmpThreshold(util.dbamp(-80))
	engine.pitchConfidenceThreshold(0.8)
	pitch_poll = poll.set('vessel_pitch', update_freq)
	pitch_poll.time = 1 / 10 -- was 8, is 10 OK?
	
	for m = 1, 16 do
		saved_masks[m] = {}
		for i = 1, 12 do
			saved_masks[m][i] = false
		end
	end
	for pitch = 1, 12 do
		-- C maj pentatonic
		scale:set_class(pitch, pitch == 2 or pitch == 4 or pitch == 7 or pitch == 9 or pitch == 12)
	end
	mask_selector.selected = 1
	save_mask()

	for l = 1, 16 do
		saved_loops[l] = {}
		for i = 1, 16 do
			saved_loops[l][i] = 24
		end
	end
	for i = 1, 16 do
		saved_loops[1][i] = 24 + i * 3
	end
	loop_selector.selected = 1
	recall_loop()

	for t = 1, 16 do
		saved_transpositions[t] = {}
		for o = 1, 4 do
			saved_transpositions[t][o] = 0
		end
	end
	transposition_selector.selected = 1
	save_transposition() -- read & save defaults from params
	-- TODO: since we're no longer calling params:bang() at the bottom, outputs need to be updated
	-- (...should I just call params:bang() again?)
	
	memory_selector.selected = memory_loop

	pitch_poll:start()
	g.key = grid_key
	
	dirty = true
end

local function key_shift_clock(n)
	if n == 2 then
		rewind()
	elseif n == 3 then
		sample_pitch()
	end
end

local function key_shift_register_insert(n)
	if n == 2 then
		shift_register:delete()
	elseif n == 3 then
		shift_register:insert()
	end
	params:set('loop_length', shift_register.length) -- keep param value up to date
end

local function key_move_cursor(n)
	if n == 2 then
		shift_register:move_cursor(-1)
	elseif n == 3 then
		shift_register:move_cursor(1)
	end
end

function key(n, z)
	if n == 1 then
		key_shift = z == 1
	elseif z == 1 then
		if grid_mode == grid_mode_play then
			key_shift_clock(n)
		elseif grid_mode == grid_mode_mask then
			key_shift_clock(n)
		elseif grid_mode == grid_mode_transpose then
			key_shift_clock(n)
		elseif grid_mode == grid_mode_edit then
			if key_shift then
				key_shift_register_insert(n)
			else
				key_move_cursor(n)
			end
		end
	end
	dirty = true
end

local function params_multi_delta(param_format, selected, d)
	-- note: this assumes number params with identical range!
	local min_value = math.huge
	local max_value = -math.huge
	local selected_params = {}
	for n, is_selected in ipairs(selected) do
		if is_selected then
			local param_name = string.format(param_format, n)
			local param = params:lookup_param(param_name)
			local value = param.value
			table.insert(selected_params, param)
			min_value = math.min(min_value, value)
			max_value = math.max(max_value, value)
		end
	end
	-- TODO: getting errors that seem to suggest this is happening -- why??
	if selected_params[1] == nil then
		print('params_multi_delta fail: %s (selected follows)', param_format)
		tab.print(selected)
		return
	end
	if d > 0 then
		d = math.min(d,	(selected_params[1].max - max_value))
	elseif d < 0 then
		d = math.max(d, (selected_params[1].min - min_value))
	end
	for i, param in ipairs(selected_params) do
		param:delta(d)
	end
end

function enc(n, d)
	if n == 1 then
		if key_shift then
			params:delta('loop_length', d)
		else
			params:delta('write_probability', d)
		end
	elseif n == 2 then
		if grid_mode == grid_mode_edit then
			-- move cursor
			shift_register:move_cursor(d)
		else
			-- move head(s)
			params_multi_delta('head_%d_offset', selected_heads, d)
		end
	elseif n == 3 then
		if grid_mode == grid_mode_edit then
			-- change note at cursor
			shift_register:write_cursor(shift_register:read_cursor() + d)
			for out = 1, 4 do
				if output_source[out] >= output_source_head_1 and output_source[out] <= output_source_head_4 then
					if shift_register.read_heads[output_source[out]].offset == shift_register.cursor then
						update_output(out)
					end
				end
			end
		elseif key_shift then
			-- change head randomness
			params_multi_delta('head_%d_offset_random', selected_heads, d)
		else
			-- transpose head(s)
			params_multi_delta('output_%d_transpose', output_selector.selected, d);
		end
	end
	dirty = true
end

local function get_screen_offset_x(offset)
	return screen_note_width * (screen_note_center + offset)
end

local function get_screen_note_y(note)
	return 71 + keyboard.octave * scale.length - note
end

local function draw_head_brackets(h, level)
	local head = shift_register.read_heads[h]
	local x_low = get_screen_offset_x(head.offset_base + head:get_min_offset_offset()) + 1
	local x_high = get_screen_offset_x(head.offset_base + head:get_max_offset_offset()) + 3
	screen.level(0)
	screen.rect(x_low - 2, 0, 3, 3)
	screen.rect(x_high - 2, 0, 3, 3)
	screen.fill()
	screen.rect(x_low - 2, 61, 3, 3)
	screen.rect(x_high - 2, 61, 3, 3)
	screen.fill()
	screen.move(x_high, 2)
	screen.line(x_high, 1)
	screen.line(x_low, 1)
	screen.line(x_low, 2)
	screen.level(level)
	screen.stroke()
	screen.move(x_high, 62)
	screen.line(x_high, 64)
	screen.line(x_low, 64)
	screen.line(x_low, 62)
	screen.level(level)
	screen.stroke()
end

function redraw()
	screen.clear()
	screen.stroke()
	screen.line_width(1)

	-- draw loop region
	local loop_start_x = get_screen_offset_x(shift_register.start_offset)
	local loop_end_x = get_screen_offset_x(shift_register.end_offset) + 2
	for x = loop_start_x, loop_end_x do
		if x == loop_start_x or x == loop_end_x then
			screen.pixel(x, 1)
			screen.pixel(x, 3)
			screen.pixel(x, 5)
			-- screen.pixel(x, 7)
			-- screen.pixel(x, 56)
			screen.pixel(x, 58)
			screen.pixel(x, 60)
			screen.pixel(x, 62)
		elseif x % 2 == 1 then
			screen.pixel(x, 0)
			screen.pixel(x, 63)
		end
	end
	screen.level(1)
	screen.fill()

	local screen_notes = {}
	
	-- build table of all visible notes and draw them
	for n = 1, n_screen_notes do
		local note = {}
		note.offset = n - screen_note_center - 1
		note.x = (n - 1) * screen_note_width
		note.y = get_screen_note_y(scale:snap(shift_register:read_loop_offset(note.offset)))
		screen_notes[n] = note
		if n > 1 then
			local previous_note = screen_notes[n - 1]
			local diff = note.y - previous_note.y
			if diff > 0 then
				screen.move(note.x, previous_note.y - 1)
				screen.line_rel(0, diff + 1)
			else
				screen.move(note.x, previous_note.y)
				screen.line_rel(0, diff - 1)
			end
			if note.offset > shift_register.start_offset and note.offset <= shift_register.end_offset then
				screen.level(2)
			else
				screen.level(1)
			end
			screen.stroke()
		end
		if note.offset >= shift_register.start_offset and note.offset <= shift_register.end_offset then
			-- highlight content between loop points (center of screen)
			screen.level(2)
		else
			screen.level(1)
		end
		screen.move(note.x, note.y)
		screen.line_rel(3, 0)
		screen.stroke()
	end

	-- draw incoming grid pitch
	-- TODO
	-- for o = 1, 4 do
		-- local y = -1
		-- if output_source[o] == output_source_grid then
			-- y = get_screen_note_y(scale:snap(keyboard:get_last_note()))
		-- elseif pitch_in_detected and (output_source[o] == output_source_audio_in) then
			-- y = get_screen_note_y(scale:snap(pitch_in))
		-- end
		-- if y > -1 then
			-- screen.pixel(127, y - 1)
			-- screen.level(2)
			-- screen.fill()
		-- end
	-- end

	-- draw output states
	for o = 1, 4 do
		local y_transposed = get_screen_note_y(output_note[o])
		local level = 12
		-- in transpose mode, blink selected output(s)
		if grid_mode == grid_mode_transpose and output_selector:is_selected(o) then
			if blink_fast then
				level = 15
			else
				level = 7
			end
		end
		if output_source[o] >= output_source_head_1 and output_source[o] <= output_source_head_4 then
			local head_index = output_source[o]
			-- TODO: you could have a table of outputs and store a reference to each output's head in that table.......
			local head = shift_register.read_heads[head_index]
			local note = screen_notes[screen_note_center + head.offset + 1]
			-- TODO: we have to check this because random head offset might point to a note that's not on
			-- the screen. any good way to deal with that...?
			if note ~= nil then
				note.y_transposed = y_transposed
				-- clear outline
				screen.rect(note.x - 2, y_transposed - 2, 7, 3)
				screen.level(0)
				screen.fill()
				-- draw note
				screen.move(note.x - 1, y_transposed)
				screen.line_rel(5, 0)
				screen.level(level)
				screen.stroke()
				-- connect transposed output with original note
				-- TODO: draw highest (+/-) transpositions first, then lower, so they look OK if they stack
				local transpose_distance = y_transposed - note.y
				if transpose_distance < -1 or transpose_distance > 1 then
					local transpose_line_length = math.abs(transpose_distance) - 2
					local transpose_line_top = math.min(y_transposed + 1, note.y)
					screen.move(note.x + 2, transpose_line_top)
					screen.line_rel(0, transpose_line_length)
					screen.level(1)
					screen.stroke()
					if transpose_line_length > 2 then
						local transpose_cap_y = transpose_distance < 0 and y_transposed + 2 or y_transposed - 2
						-- clear outline
						screen.rect(note.x - 1, transpose_cap_y - 2, 6, 3)
						screen.level(0)
						screen.fill()
						-- draw cap
						screen.move(note.x, transpose_cap_y)
						screen.line_rel(3, 0)
						screen.level(2)
						screen.stroke()
					end
				end
			end
		elseif output_source[o] == output_source_audio_in or output_source[o] == output_source_grid then
			-- draw output pitch
			screen.pixel(62, y_transposed - 2)
			screen.pixel(63, y_transposed - 2)
			screen.pixel(64, y_transposed - 2)
			screen.pixel(64, y_transposed - 1)
			screen.pixel(64, y_transposed)
			screen.pixel(63, y_transposed)
			screen.pixel(62, y_transposed)
			screen.pixel(62, y_transposed - 1)
			screen.level(level)
			screen.fill()
		end
	end

	-- draw head indicator
	local head_note = screen_notes[17]
	screen.move(head_note.x, head_note.y)
	screen.line_rel(3, 0)
	screen.level(0)
	screen.stroke()
	screen.pixel(head_note.x + 1, head_note.y - 1)
	screen.level(15)
	screen.fill()

	-- draw cursor
	if grid_mode == grid_mode_edit then
		local note = screen_notes[screen_note_center + shift_register.cursor + 1]
		local x = note.x
		local y1 = math.min(note.y, note.y_transposed and note.y_transposed or note.y) - 5
		local y2 = math.max(note.y, note.y_transposed and note.y_transposed or note.y) + 5
		-- clear background around caps
		screen.rect(x - 2, y1 - 2, 7, 3)
		screen.rect(x - 2, y2 - 2, 7, 3)
		screen.level(0)
		screen.fill()
		-- set level
		screen.level(blink_fast and 15 or 7)
		-- top left cap
		screen.move(x - 1, y1)
		screen.line_rel(2, 0)
		screen.stroke()
		-- top right cap
		screen.move(x + 2, y1)
		screen.line_rel(2, 0)
		screen.stroke()
		-- top stem
		screen.move(x + 2, y1)
		screen.line_rel(0, 3)
		screen.stroke()
		-- bottom stem
		screen.move(x + 2, y2 - 4)
		screen.line_rel(0, 3)
		screen.stroke()
		-- bottom left cap
		screen.move(x - 1, y2)
		screen.line_rel(2, 0)
		screen.stroke()
		-- bottom right cap
		screen.move(x + 2, y2)
		screen.line_rel(2, 0)
		screen.stroke()
	end

	for i = 1, 4 do
		if active_heads[i] and not selected_heads[i] then
			draw_head_brackets(i, 1)
		end
	end
	for i = 1, 4 do
		if selected_heads[i] then
			draw_head_brackets(i, 3)
		end
	end

	local write_probability = params:get('write_probability') - 1
	local probability_level = math.ceil(write_probability / 10)
	if probability_level > 0 then
		screen.move(12, 10)
		screen.level(probability_level)
		screen.text_right(util.round(write_probability))
		screen.text('%')
	end

	-- DEBUG: draw minibuffer, loop region, head
	--[[
	screen.move(0, 1)
	screen.line_rel(shift_register.buffer_size, 0)
	screen.level(1)
	screen.stroke()
	for offset = shift_register.start_offset, shift_register.end_offset do
		screen.pixel(shift_register:get_loop_pos(offset) - 1, 0)
		if grid_mode == grid_mode_edit and offset == shift_register.cursor then
			screen.level(blink_fast and 15 or 7)
		elseif offset == shift_register.start_offset or offset == shift_register.end_offset or offset == 0 then
			screen.level(15)
		else
			screen.level(7)
		end
		screen.fill()
	end
	]]

	screen.update()
end

function cleanup()
	if pitch_poll ~= nil then
		pitch_poll:stop()
	end
	if redraw_metro ~= nil then
		redraw_metro:stop()
	end
end
