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
local ShiftRegisterVoice = include 'lib/shift_register_voice'
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

-- TODO: save/recall offsets too... if they could be set by grid then they could be stored with transpositions
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

local voices = {}
local n_voices = 4
local voice_draw_order = { 4, 3, 2, 1 }
local top_voice_index = 1
local top_voice = {}

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
local screen_note_center = math.floor((n_screen_notes - 1) / 2 + 0.5)
local screen_notes = { {}, {}, {}, {} }
local cursor = 0

local key_shift = false
local info_visible = false
local blink_slow = false
local blink_fast = false
local dirty = false
local info_metro
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
	shift_register:set_loop(cursor, saved_loops[loop_selector.selected])
	shift_register.dirty = false
end

local function save_loop()
	saved_loops[loop_selector.selected] = shift_register:get_loop(cursor)
	shift_register.dirty = false
end

local function recall_transposition()
	local t = transposition_selector.selected
	if saved_transpositions[t] == nil then
		return
	end
	for o = 1, 4 do
		params:set(string.format('voice_%d_transpose', o), saved_transpositions[t][o])
	end
	transposition_dirty = false
end

local function save_transposition()
	local transposition = {}
	for v = 1, n_voices do
		transposition[v] = voices[v].transpose
	end
	saved_transpositions[transposition_selector.selected] = transposition
	transposition_dirty = false
end

local function update_voice(v)
	local voice = voices[v]
	voice.note_snapped = scale:snap(voice.note)
	crow.output[v].volts = voice.note_snapped / 12 - 1
end

local function update_voices()
	for v = 1, n_voices do
		update_voice(v)
	end
end

local function sample_pitch()
	shift_register:shift(1)
	for v = 1, n_voices do
		voices[v]:clock()
	end
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
	update_voices()
	dirty = true
end

local function rewind()
	shift_register:shift(-1)
	-- TODO: fix this, MAYBE by disabling rewind
	for v = 1, n_voices do
		voices[v]:clock()
	end
	update_voices()
	dirty = true
end

local function update_active_heads(last_output)
	if last_output then
		local new_draw_order = {}
		for i, o in ipairs(voice_draw_order) do
			if o ~= last_output then
				table.insert(new_draw_order, o)
			end
		end
		table.insert(new_draw_order, last_output)
		top_voice_index = new_draw_order[n_voices]
		top_voice = voices[top_voice_index]
		voice_draw_order = new_draw_order
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

local function get_cursor_offset()
	return top_voice:get_offset(cursor)
end

local key_level_callbacks = {}

key_level_callbacks[grid_mode_play] = function(self, x, y, n)
	local level = 0
	-- highlight mask
	if self.scale:contains(n) then
		level = 4
	end
	-- highlight output notes
	for v = 1, n_voices do
		local voice = voices[v]
		if n == voice.note_snapped then
			if output_selector:is_selected(v) then
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
	for v = 1, n_voices do
		if n == voices[v].note_snapped then
			if output_selector:is_selected(v) then
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
	for v = 1, n_voices do
		if n - 36 == voices[v].transpose then
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
	for v = 1, n_voices do
		-- TODO: there's gotta be a better way to do this
		--[[
		if n == self.scale:snap(shift_register:read_head(output_source[o])) then
			level = 7
		end
		--]]
	end
	-- highlight snapped version of the note at the cursor
	if n == scale:snap(shift_register:read_loop_offset(get_cursor_offset())) then
		level = 10
	end
	-- highlight + blink the un-snapped note we're editing
	if n == shift_register:read_loop_offset(get_cursor_offset()) then
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
			end
		elseif grid_mode == grid_mode_mask or (grid_mode == grid_mode_play and grid_shift) then
			if z == 1 then
				local n = keyboard:get_key_note(x, y)
				scale:toggle_class(n)
				mask_dirty = true
				if grid_ctrl then
					update_voices()
				end
			end
		elseif grid_mode == grid_mode_transpose then
			keyboard:note(x, y, z)
			if keyboard.gate then
				local transpose = math.min(72, math.max(0, keyboard:get_last_note())) - 36
				for o = 1, 4 do
					if output_selector:is_selected(o) then
						params:set('voice_' .. o .. '_transpose', transpose)
					end
				end
			end
		elseif grid_mode == grid_mode_edit then
			keyboard:note(x, y, z)
			if keyboard.gate then
				local note = keyboard:get_last_note()
				shift_register:write_loop_offset(get_cursor_offset(), note)
				-- update outputs immediately, if appropriate
				for v = 1, n_voices do
					if shift_register:get_loop_pos(voice:get_offset(0)) == shift_register:get_loop_pos(voice:get_offset(cursor)) then
						update_voice(v)
					end
				end
			end
		end
	elseif output_selector:should_handle_key(x, y) then
		-- TODO: what should these do in modes other than transpose?
		local output = output_selector:get_key_option(x, y)
		output_selector:key(x, y, z)
		update_active_heads(z == 1 and output)
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
				update_voices()
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
				update_voices()
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
		dirty = true
	end
end

local function show_info()
	info_visible = true
	dirty = true
	if not key_shift then
		if info_metro ~= nil then
			info_metro:stop()
			info_metro:start(0.75)
		end
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
		end,
		action = function(value)
			show_info()
		end
	}
	params:add{
		type = 'option',
		id = 'shift_clock',
		name = 'sr/s+h clock',
		options = clock_mode_names,
		default = clock_mode_trig_grid,
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
	params:add{
		type = 'option',
		id = 'pitch_post',
		name = 'pitch post-verb',
		options = { 'no', 'yes' },
		default = 1,
		action = function(value)
			engine.pitchPost(value - 1)
		end
	}
	
	params:add_separator()
	
	params:add{
		type = 'number',
		id = 'loop_length',
		name = 'loop length',
		min = 2,
		max = 32,
		default = 16,
		-- TODO: decreasing loop length when some/all voices' offsets are near loop length causes... let's say unintuitive behavior
		action = function(value)
			shift_register.length = value
			update_voices()
			dirty = true
			show_info()
		end
	}
	
	params:add_separator()
	
	for v = 1, n_voices do
		local voice = voices[v]
		-- TODO: maybe some of these things really shouldn't be params?
		params:add{
			type = 'control',
			id = string.format('voice_%d_offset', v),
			name = string.format('voice %d offset', v),
			-- min + max are outside loop length range; param action wraps value to [0, loop length]
			-- total range is 100 to avoid rounding oddness caused by params:delta()
			-- TODO: this may (will) behave weirdly under MIDI control. any way to improve?
			-- TODO: values jump when sweeping offset across min/max with scramble > 0
			controlspec = controlspec.new(-1, 98, 'lin', 1, shift_register.length - v * 3),
			action = function(value)
				local wrapped = value % shift_register.length
				if value ~= wrapped then
					params:set(string.format('voice_%d_offset', v), wrapped)
					return
				end
				voice.offset = value
				update_voice(v)
				dirty = true
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_scramble', v),
			name = string.format('voice %d scramble', v),
			controlspec = controlspec.new(0, 16, 'lin', 0.2, 0),
			action = function(value)
				voice.scramble = value
				dirty = true
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_slew', v),
			name = string.format('voice %d slew', v),
			controlspec = controlspec.new(1, 1000, 'exp', 1, 4, 'ms'),
			action = function(value)
				crow.output[v].slew = value / 1000
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_transpose', v),
			name = string.format('voice %d transpose', v),
			controlspec = controlspec.new(-48, 48, 'lin', 1, 0, 'st'),
			action = function(value)
				voice.transpose = value
				update_voice(v)
				dirty = true
				transposition_dirty = true
			end
		}
	end

	params:add_separator()

	params:add{
		type = 'trigger',
		id = 'restore_memory',
		name = 'restore memory',
		action = function()
			local data_file = norns.state.data .. 'memory.lua'
			if util.file_exists(data_file) then
				local data, errorMessage = tab.load(data_file)
				if errorMessage ~= nil then
					error(errorMessage)
				else
					tab.print(data)
					if data.masks ~= nil then
						saved_masks = data.masks
						mask_dirty = true
					end
					if data.transpositions ~= nil then
						saved_transpositions = data.transpositions
						transposition_dirty = true
					end
					if data.loops ~= nil then
						saved_loops = data.loops
						shift_register.dirty = true
					end
				end
			end
		end
	}

	params:add{
		type = 'trigger',
		id = 'save_memory',
		name = 'save memory',
		action = function()
			local data_file = norns.state.data .. 'memory.lua'
			local data = {}
			data.masks = saved_masks
			data.transpositions = saved_transpositions
			data.loops = saved_loops
			tab.save(data, data_file)
		end
	}
end

function init()

	-- initialize voices
	for v = 1, n_voices do
		voices[v] = ShiftRegisterVoice.new(0, shift_register)
	end
	top_voice = voices[top_voice_index]

	VesselEngine.add_params('basic')
	params:add_separator()
	add_params()

	crow.add = crow_setup -- when crow is connected
	crow_setup() -- calls params:bang()
	
	-- initialize grid controls
	grid_mode = grid_mode_play
	keyboard.get_key_level = key_level_callbacks[grid_mode]
	output_selector:reset(true)
	update_active_heads()

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

	info_metro = metro.init()
	info_metro.event = function()
		info_visible = false
		dirty = true
	end
	info_metro.count = 1
	-- TODO: why does info stay on screen indefinitely after load?
	
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

	for t = 1, 16 do
		saved_transpositions[t] = {}
		for o = 1, 4 do
			saved_transpositions[t][o] = 0
		end
	end
	transposition_selector.selected = 1
	save_transposition() -- read & save defaults from params

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

	params:set('restore_memory')
	recall_mask()
	recall_transposition()
	recall_loop()

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
		shift_register:delete(get_cursor_offset())
		-- TODO: move cursor: -1 if in central loop, more or less in other loops
	elseif n == 3 then
		shift_register:insert(get_cursor_offset())
		-- TODO: move cursor: +1 if in central loop, more or less in other loops
	end
	params:set('loop_length', shift_register.length) -- keep param value up to date
end

local function key_move_cursor(n)
	if n == 2 then
		cursor = (cursor + screen_note_center - 1) % n_screen_notes - screen_note_center
	elseif n == 3 then
		cursor = (cursor + screen_note_center + 1) % n_screen_notes - screen_note_center
	end
end

function key(n, z)
	if n == 1 then
		key_shift = z == 1
		show_info()
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
	local min = 0
	local max = 0
	local min_value = math.huge
	local max_value = -math.huge
	local selected_params = {}
	for n, is_selected in ipairs(selected) do
		if is_selected then
			local param_name = string.format(param_format, n)
			local param = params:lookup_param(param_name)
			local value = 0
			if param.value ~= nil then
				-- number param
				value = param.value
				min = param.min
				max = param.max
			else
				-- control param
				value = param:get()
				min = param.controlspec.minval
				max = param.controlspec.maxval
			end
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
		d = math.min(d,	max - max_value)
	elseif d < 0 then
		d = math.max(d, min - min_value)
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
			cursor = (cursor + screen_note_center + d) % n_screen_notes - screen_note_center
		else
			-- move head(s)
			params_multi_delta('voice_%d_offset', output_selector.selected, -d)
		end
	elseif n == 3 then
		if grid_mode == grid_mode_edit then
			-- change note at cursor
			local current_note = shift_register:read_loop_offset(get_cursor_offset())
			shift_register:write_loop_offset(get_cursor_offset(), current_note + d)
			for v = 1, n_voices do
				if shift_register:get_loop_pos(voices[v]:get_offset(0)) == shift_register:get_loop_pos(voices[v]:get_offset(cursor)) then
					update_voice(v)
				end
			end
		elseif key_shift then
			-- change head randomness
			params_multi_delta('voice_%d_scramble', output_selector.selected, d)
		else
			-- transpose head(s)
			params_multi_delta('voice_%d_transpose', output_selector.selected, d);
		end
	end
	dirty = true
end

function get_screen_offset_x(offset)
	return screen_note_width * (screen_note_center + offset)
end

function get_screen_note_y(note)
	return 71 + keyboard.octave * scale.length - note
end

-- calculate coordinates for each visible note
function calculate_voice_path(v)
	local voice = voices[v]
	local path = voice:get_path(-screen_note_center, n_screen_notes - screen_note_center)
	screen_notes[v] = {}
	for n = 1, n_screen_notes do
		local note = {}
		note.x = (n - 1) * screen_note_width
		note.y = get_screen_note_y(scale:snap(path[n].value))
		note.offset = path[n].offset
		screen_notes[v][n] = note
	end
end

function draw_voice_path(v, level)
	local voice = voices[v]

	calculate_voice_path(v) -- TODO: don't do this every time, only when it changes

	-- find the note at the shift register's write head
	local head = screen_note_center - voice.offset + 1

	screen.line_cap('square')

	-- draw background/outline
	screen.line_width(3)
	screen.level(0)
	for n = 1, n_screen_notes do
		local note = screen_notes[v][n]
		local x = note.x + 0.5
		local y = note.y + 0.5
		-- TODO: account for 'z' (gate): when current or prev z is low, don't draw connecting line
		-- move or connect from previous note
		if n == 1 then
			screen.move(x + 0.5, y + 0.5)
		else
			screen.line(x, y)
		end
		-- draw this note
		screen.line(x + screen_note_width, y)
	end
	screen.stroke()

	-- draw foreground/path
	screen.line_width(1)
	screen.level(level)
	for n = 1, n_screen_notes do
		local note = screen_notes[v][n]
		local x = note.x + 0.5
		local y = note.y + 0.5
		-- TODO: account for 'z' (gate): when current or prev z is low, don't draw connecting line; and when current z is low, draw current note as dots
		-- move or connect from previous note
		if n == 1 then
			screen.move(x, y)
		else
			screen.line(x, y)
		end
		-- draw this note
		screen.line(x + screen_note_width, y)
	end
	screen.stroke()

	-- add gap(s) for head
	for n = 1, n_screen_notes do
		local note = screen_notes[v][n]
		if note.offset == 0 then
			screen.pixel(note.x + 3, note.y)
			screen.level(0)
			screen.fill()
		end
	end

	screen.line_cap('butt')
end

function redraw()
	screen.clear()
	screen.stroke()
	screen.line_width(1)
	screen.font_face(2)
	screen.font_size(8)

	-- draw vertical output/head indicator
	-- TODO: I think this can go closer to the right edge of the screen, unless you start featuring retrograde motion more
	-- TODO: set heads/outputs to retrograde instead of allowing backwards clock ticks
	-- TODO: inversion too
	-- TODO: then you get into different loop lengths...
	local output_x = get_screen_offset_x(0) + 3
	screen.move(output_x, 0)
	screen.line(output_x, 64)
	screen.level(1)
	screen.stroke()

	-- draw paths
	for i, v in ipairs(voice_draw_order) do
		local level = output_selector:is_selected(v) and 3 + ((i - 1) * 4) or 2
		draw_voice_path(v, level)
	end

	-- highlight current notes after drawing all snakes, lest some be covered by outlines
	-- TODO: draw these based on voice.note_snapped in case that somehow ends up being different from what's shown on the screen??
	-- (but it shouldn't, ever)
	for i, v in ipairs(voice_draw_order) do
		local note = screen_notes[v][screen_note_center + 1] -- TODO: is this actually the current note?
		screen.pixel(note.x + 2, note.y)
		screen.level(15)
		screen.fill()
	end

	local function draw_input(x, y, level)
		screen.rect(x + 2, y - 2, 5, 5)
		screen.level(0)
		screen.fill()
		screen.rect(x + 3.5, y - 0.5, 2, 2)
		screen.level(15)
		screen.stroke()
	end

	-- draw input indicators
	-- TODO: I'm currently not drawing them at all when they aren't present (when keyboard gate is 0
	-- and no pitch is detected) but if a trigger is received the last value will be used. maybe flash
	-- that value when a write occurs?
	local input_transpose = top_voice.transpose
	for n = 1, n_screen_notes do
		local note = screen_notes[top_voice_index][n]
		if note.offset == 0 then
			local x = note.x
			-- grid pitch
			if input_keyboard.gate then
				local grid_y = get_screen_note_y(scale:snap(input_keyboard:get_last_note() + input_transpose))
				draw_input(x, grid_y)
			end
			-- pitch detector pitch
			if pitch_in_detected then
				local audio_y = get_screen_note_y(scale:snap(pitch_in + input_transpose))
				draw_input(x, audio_y)
			end
		end
	end

	-- draw cursor
	-- TODO: consider just circling a corner
	if grid_mode == grid_mode_edit then
		local note = screen_notes[top_voice_index][(screen_note_center + cursor - 1) % n_screen_notes + 1]
		local x = note.x
		local y1 = note.y - 5
		local y2 = note.y + 5
		local level = blink_fast and 15 or 7
		-- clear background/outline
		screen.rect(x - 1, y1 - 1, 7, 3)
		screen.rect(x - 1, y2 - 1, 7, 3)
		screen.rect(x + 1, y1, 3, 5)
		screen.rect(x + 1, y2 - 4, 3, 5)
		screen.level(0)
		screen.fill()
		-- set level
		screen.level(level)
		-- top left cap
		screen.rect(x, y1, 2, 1)
		screen.fill()
		-- top right cap
		screen.rect(x + 3, y1, 2, 1)
		screen.fill()
		-- top stem
		screen.move(x + 2.5, y1 + 1)
		screen.line_rel(0, 3)
		screen.level(level)
		screen.stroke()
		-- bottom stem
		screen.move(x + 2.5, y2)
		screen.line_rel(0, -3)
		screen.level(level)
		screen.stroke()
		-- bottom left cap
		screen.rect(x, y2, 2, 1)
		screen.fill()
		-- bottom right cap
		screen.rect(x + 3, y2, 2, 1)
		screen.fill()
	end

	if info_visible then
		screen.rect(0, 0, 26, 64)
		screen.level(0)
		screen.fill()
		screen.move(24.5, 0)
		screen.line(24.5, 64)
		screen.level(4)
		screen.stroke()

		screen.level(15)

		screen.move(0, 7)
		screen.text(string.format('P: %d%%', util.round(params:get('write_probability') - 1)))

		screen.move(0, 16)
		screen.text(string.format('L: %d', shift_register.length))

		screen.move(0, 25)
		screen.text(string.format('O: %d', top_voice.offset))

		screen.move(0, 34)
		screen.text(string.format('T: %d', top_voice.transpose))

		screen.move(0, 43)
		screen.text(string.format('S: %.1f', top_voice.scramble))
	end

	-- DEBUG: draw minibuffer, loop region, head
	--[[
	screen.move(0, 1)
	screen.line_rel(shift_register.buffer_size, 0)
	screen.level(1)
	screen.stroke()
	for offset = -shift_register.length, 0 do
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
	--]]

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
