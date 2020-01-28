-- follower
-- follow pitch, quantize, etc...

engine.name = 'Analyst'

local musicutil = require 'musicutil'

local grid_keyboard = include 'lib/grid_keyboard'
local grid_multi_select = include 'lib/grid_multi_select'
local shift_register = include 'lib/shift_register'

local pitch_poll_l
local pitch_in = 0
local pitch_in_detected = false
local pitch_in_octave = 0
local crow_pitch_in = 0
local mask = {}
local saved_masks = {} -- TODO: save with params... somehow
-- idea: use a 'data file' param, so it can be changed; the hardest part will be naming new files, I think
local active_mask = 0
local mask_dirty = false
local max_pitch = 96

local saved_loops = {}
local active_loop = 0

local recall_mode_mask = 1
local recall_mode_loop = 2
local recall_mode = recall_mode_loop

-- TODO: save/recall memory/loop contents like masks
-- transposition settings too

local memory = shift_register.new(32)
local cursor_note = 0

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

local loop_probability = 100
-- TODO: add internal clock using beatclock
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
local output_source = {}
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

local grid_mode_play = 1
local grid_mode_mask = 2
local grid_mode_transpose = 3
local grid_mode_memory = 4
local grid_mode = grid_mode_play

local output_selector = grid_multi_select.new(5, 3, 4)

local g = grid.connect()

local grid_shift = false
local grid_ctrl = false
local grid_octave_key_held = false
local keyboard = grid_keyboard.new(6, 1, 11, 8)
local keyboard_note = 0

local screen_note_width = 4
local n_screen_notes = 128 / screen_note_width
local screen_note_center = math.floor((n_screen_notes - 1) / 2)

local blink_slow = false
local blink_fast = false
local dirty = false
local redraw_metro

local function quantize(pitch)
	return math.floor(pitch + 0.5)
end

local function snap(pitch)
	pitch = math.max(1, math.min(max_pitch, pitch))
	local quantized = quantize(pitch)
	-- print(string.format('quantize %f to %d', pitch, quantized))
	local low = quantized < pitch
	if mask[quantized] then
		-- print('pitch enabled')
		return quantized
	end
	for i = 1, 96 do
		local up = math.min(96, quantized + i)
		local down = math.max(1, quantized - i)
		if low then
			if mask[down] then
				return down
			elseif mask[up] then
				return up
			end
		else
			if mask[up] then
				return up
			elseif mask[down] then
				return down
			end
		end
	end
	return 0
end

local function recall_mask(m)
	if saved_masks[m] == nil then
		return
	end
	for i = 1, max_pitch do
		mask[i] = saved_masks[m][i]
	end
	active_mask = m
	mask_dirty = false
end

local function save_mask(m)
	for i = 1, max_pitch do
		saved_masks[m][i] = mask[i]
	end
	active_mask = m
	mask_dirty = false
end

local function recall_loop(l)
	if saved_loops[l] == nil then
		return
	end
	memory:set_loop(saved_loops[l])
	active_loop = l
	-- loop_dirty = false -- TODO
end

local function save_loop(l)
	saved_loops[l] = memory:get_loop()
	active_loop = l
	-- loop_dirty = false -- TODO
end

-- TODO: make this into a 'grid bank' control
local function get_grid_mask(x, y)
	return x + (y - 3) * 4
end

local function update_output(out)
	local output_source = output_source[out]
	local volts = 0
	if output_source == output_source_audio_in then
		output_note[out] = snap(quantize(pitch_in) + output_transpose[out])
	elseif output_source == output_source_grid then
		output_note[out] = snap(keyboard_note + output_transpose[out])
	else
		local output_head = output_source
		output_note[out] = snap(memory:read_head(output_head) + output_transpose[out])
	end
	volts = output_note[out] / 12 - 1
	dirty = true
	crow.output[out].volts = volts
end

local function sample_pitch()
	memory:shift(1)
	if loop_probability <= math.random(1, 100) then
		if source == source_crow then
			memory:write_head(crow_pitch_in)
		elseif keyboard.gate and (source == source_grid or source == source_grid_pitch or source == source_grid_crow) then
			memory:write_head(keyboard_note)
		elseif pitch_in_detected and (source == source_pitch or source == source_pitch_grid) then
			memory:write_head(pitch_in)
		elseif source == source_grid_crow then
			memory:write_head(crow_pitch_in)
		elseif keyboard.gate and source == source_pitch_grid then
			memory:write_head(keyboard_note)
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
	memory:shift(-1)
	for out = 1, 4 do
		if not output_stream[out] then
			update_output(out)
		end
	end
	dirty = true
end

local function grid_redraw()

	-- mode buttons
	g:led(1, 1, grid_mode == grid_mode_play and 7 or 2)
	g:led(2, 1, grid_mode == grid_mode_mask and 7 or 2)
	g:led(3, 1, grid_mode == grid_mode_transpose and 7 or 2)
	g:led(4, 1, grid_mode == grid_mode_memory and 7 or 2)

	-- recall mode buttons
	g:led(2, 2, recall_mode == recall_mode_mask and 7 or 2)
	g:led(4, 2, recall_mode == recall_mode_loop and 7 or 2)

	-- recall buttons
	for x = 1, 4 do
		for y = 3, 6 do
			if recall_mode == recall_mode_mask then
				local m = get_grid_mask(x, y)
				if active_mask == m then
					if mask_dirty and blink_slow then
						g:led(x, y, 8)
					else
						g:led(x, y, 7)
					end
				else
					g:led(x, y, 2)
				end
			elseif recall_mode == recall_mode_loop then
				local l = get_grid_mask(x, y) -- TODO: silly; make this a grid control
				if active_loop == l then
					g:led(x, y, 7) -- TODO: track dirty/not?
				else
					g:led(x, y, 2)
				end
			end
		end
	end

	-- shift + ctrl
	g:led(1, 7, grid_shift and 15 or 2)
	g:led(1, 8, grid_ctrl and 15 or 2)

	-- output buttons
	output_selector:draw(g)

	-- keyboard octaves
	g:led(3, 8, 2 - math.min(keyboard.octave, 0))
	g:led(4, 8, 2 + math.max(keyboard.octave, 0))

	-- keyboard
	keyboard:draw(g)
	g:refresh()
end

local key_level_callbacks = {}

key_level_callbacks[grid_mode_play] = function(x, y, n)
	local level = 0
	-- highlight mask
	if mask[n] then
		level = 4
	end
	-- highlight output notes
	for o = 1, 4 do
		if n == output_note[o] then
			level = 10
		end
	end
	-- highlight current note
	if keyboard.gate and keyboard:is_key_last(x, y) then
		level = 15
	end
	return level
end

key_level_callbacks[grid_mode_mask] = function(x, y, n)
	local level = 0
	-- highlight white keys
	if keyboard:is_white_key(n) then
		level = 2
	end
	-- highlight mask
	if mask[n] then
		level = 5
	end
	-- highlight output notes
	for o = 1, 4 do
		if n == output_note[o] then
			level = 10
		end
	end
	return level
end

key_level_callbacks[grid_mode_transpose] = function(x, y, n)
	local level = 0
	-- highlight octaves
	if n % 12 == 0 then
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

key_level_callbacks[grid_mode_memory] = function(x, y, n)
	local level = 0
	-- highlight other notes in the sequence
	-- TODO: this is probably ridiculously inefficient
	for offset = memory.start_offset, memory.end_offset do
		if n == memory:read_loop_offset(offset) then
			-- notes that fall on the mask are brighter
			level = mask[n] and 4 or 2
		end
	end
	-- highlight the note we're editing
	if n == cursor_note then
		level = blink_fast and 15 or 14
	end
	return level
end

-- enable/disable the given note in all octaves
local function mask_set_pitch_class(note, enable)
	local pitch = (note - 1 ) % 12 + 1
	for octave = 0, 7 do
		mask[pitch + octave * 12] = enable
	end
	mask_dirty = true
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
				mask_set_pitch_class(n, not mask[n])
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
		elseif grid_mode == grid_mode_memory then
			keyboard:note(x, y, z)
			if keyboard.gate then
				local note = keyboard:get_last_note()
				memory:write_cursor(note)
				cursor_note = snap(note)
				-- update outputs immediately, if appropriate
				for h = 1, memory.n_read_heads do
					if memory.read_heads[h].offset == memory.cursor then
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
		-- output select buttons
		-- TODO: what should these do in modes other than transpose?
		output_selector:key(x, y, z)
	elseif x == 3 and y == 8 then
		if z == 1 then
			if grid_octave_key_held then
				keyboard.octave = 0
			else
				keyboard.octave = keyboard.octave - 1
			end
		end
		grid_octave_key_held = z == 1
	elseif x == 4 and y == 8 then
		if z == 1 then
			if grid_octave_key_held then
				keyboard.octave = 0
			else
				keyboard.octave = keyboard.octave + 1
			end
		end
		grid_octave_key_held = z == 1
	elseif x < 5 and y == 1 and z == 1 then
		-- grid mode buttons
		if x == 1 then
			grid_mode = grid_mode_play
		elseif x == 2 then
			grid_mode = grid_mode_mask
		elseif x == 3 then
			grid_mode = grid_mode_transpose
		elseif x == 4 then
			grid_mode = grid_mode_memory
		end
		-- set the grid drawing routine based on new mode
		keyboard.get_key_level = key_level_callbacks[grid_mode]
		-- clear held note stack
		-- this prevents held notes from getting stuck when switching to a mode that doesn't call
		-- keyboard:note()
		keyboard:reset()
	elseif x == 2 and y == 2 and z == 1 then
		recall_mode = recall_mode_mask
	elseif x == 4 and y == 2 and z == 1 then
		recall_mode = recall_mode_loop
	elseif x < 5 and y > 2 and y < 7 and z == 1 then
		-- recall buttons
		if recall_mode == recall_mode_mask then
			local m = get_grid_mask(x, y)
			if grid_shift then
				save_mask(m)
			else
				recall_mask(m)
			end
			if grid_ctrl then
				for out = 1, 4 do
					update_output(out)
				end
			end
		elseif recall_mode == recall_mode_loop then
			local l = get_grid_mask(x, y) -- TODO
			if grid_shift then
				save_loop(l)
			else
				recall_loop(l)
				for out = 1, 4 do
					update_output(out)
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
		pitch_in = musicutil.freq_to_note_num(value) + (pitch_in_octave - 2) * 12
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
		crow_pitch_in = math.floor(value * 12 + 0.5)
		print(string.format('crow input 2: %fV = %d', value, crow_pitch_in))
	end
	params:bang()
end

function init()
	
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
			grid_redraw(blink_slow, blink_fast)
			redraw()
			dirty = false
		end
	end
	redraw_metro:start(1 / 15)
	
	engine.amp_threshold(util.dbamp(-80))
	-- TODO: did you get rid of the 'clarity' threshold in the engine, or no?
	pitch_poll_l = poll.set('pitch_analyst_l', update_freq)
	pitch_poll_l.time = 1 / 8
	
	for m = 1, 16 do
		saved_masks[m] = {}
		for i = 1, max_pitch do
			saved_masks[m][i] = false
		end
	end
	for i = 1, max_pitch do
		local pitch_class = (i - 1) % 12 + 1
		-- C maj pentatonic
		mask[i] = pitch_class == 2 or pitch_class == 4 or pitch_class == 7 or pitch_class == 9 or pitch_class == 12
	end
	save_mask(1)

	for l = 1, 16 do
		saved_loops[l] = {}
		for i = 1, 16 do
			saved_loops[l][i] = 24
		end
	end
	for i = 1, 16 do
		saved_loops[1][i] = 24 + i * 3
	end
	recall_loop(1)
	
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
		type = 'number',
		id = 'loop_probability',
		name = 'loop probability',
		min = 0,
		max = 100,
		default = 0,
		controlspec = controlspec.new(0, 100, 'lin', 1, 0, '%'),
		formatter = function(param)
			return string.format('%d%%', param:get())
		end,
		action = function(value)
			loop_probability = value
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
	
	params:add_separator()
	
	for i = 1, memory.n_read_heads do
		local head = memory.read_heads[i]
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
				head:update(true)
				for o = 1, 4 do
					if output_source[o] == i then
						update_output(o)
					end
				end
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
			memory:set_length(value)
			cursor_note = snap(memory:read_cursor())
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
			end
		}
	end
	
	pitch_poll_l:start()
	g.key = grid_key
	
	crow.add = crow_setup -- when crow is connected
	crow_setup() -- calls params:bang()
	
	dirty = true
end

local function key_shift_clock(n)
	if n == 2 then
		rewind()
	elseif n == 3 then
		sample_pitch()
	end
end

local function key_select_pos(n)
	if n == 2 then
		memory:move_cursor(-1)
		cursor_note = snap(memory:read_cursor())
		dirty = true
	elseif n == 3 then
		memory:move_cursor(1)
		cursor_note = snap(memory:read_cursor())
		dirty = true
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
		elseif grid_mode == grid_mode_memory then
			if key_shift then
				key_shift_clock(n)
			else
				key_select_pos(n)
			end
		end
	end
end

function enc(n, d)
	if n == 1 then
		params:delta('loop_length', d)
	elseif n == 2 then
		for o = 1, 4 do
			if output_selector:is_selected(o) then
				if output_source[o] < 5 then
					-- TODO: this will behave weirdly if more than one output reads from the same head
					params:delta('head_' .. o .. '_offset', d)
				end
			end
		end
	elseif n == 3 then
		for o = 1, 4 do
			if output_selector:is_selected(o) then
				if output_source[o] < 5 then
					params:delta('head_' .. o .. '_offset_random', d)
				end
			end
		end
	end
end

local function get_screen_offset_x(offset)
	return screen_note_width * (screen_note_center + offset)
end

local function get_screen_note_y(note)
	return 63 + keyboard.octave * 12 - note
end

local function draw_head_brackets(h, level)
	local head = memory.read_heads[h]
	local x1 = get_screen_offset_x(head.offset_base) + 1
	local x2 = get_screen_offset_x(math.min(16, head.offset_base + head.randomness)) + 3
	screen.level(0)
	screen.rect(x1 - 2, 0, 3, 3)
	screen.rect(x2 - 2, 0, 3, 3)
	screen.fill()
	screen.rect(x1 - 2, 61, 3, 3)
	screen.rect(x2 - 2, 61, 3, 3)
	screen.fill()
	screen.move(x2, 2)
	screen.line(x2, 1)
	screen.line(x1, 1)
	screen.line(x1, 2)
	screen.level(level)
	screen.stroke()
	screen.move(x2, 62)
	screen.line(x2, 64)
	screen.line(x1, 64)
	screen.line(x1, 62)
	screen.level(level)
	screen.stroke()
end

function redraw()
	screen.clear()
	screen.stroke()
	screen.line_width(1)

	-- draw loop region
	local loop_start_x = get_screen_offset_x(memory.start_offset)
	local loop_end_x = get_screen_offset_x(memory.end_offset) + 2
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
	
	-- draw memory contents
	for n = 1, n_screen_notes do
		local offset = n - screen_note_center - 1
		local loop_pos = memory:get_loop_pos(offset)
		local x = (n - 1) * screen_note_width
		local y = get_screen_note_y(snap(memory:read_absolute(loop_pos)))
		if grid_mode == grid_mode_memory and offset == memory.cursor then
			-- blink the cursor in edit mode
			if blink_fast then
				screen.level(15)
			else
				screen.level(7)
			end
		elseif offset == 0 then
			-- highlight head
			screen.level(15)
		elseif offset >= memory.start_offset and offset <= memory.end_offset then
			-- highlight content between loop points (center of screen)
			screen.level(2)
		else
			screen.level(1)
		end
		screen.move(x, y)
		screen.line_rel(3, 0)
		screen.stroke()
	end

	-- draw incoming grid pitch
	-- TODO
	-- for o = 1, 4 do
		-- local y = -1
		-- if output_source[o] == output_source_grid then
			-- y = get_screen_note_y(snap(keyboard:get_last_note()))
		-- elseif pitch_in_detected and (output_source[o] == output_source_audio_in) then
			-- y = get_screen_note_y(snap(quantize(pitch_in)))
		-- end
		-- if y > -1 then
			-- screen.pixel(127, y - 1)
			-- screen.level(2)
			-- screen.fill()
		-- end
	-- end

	local active_heads = { false, false, false, false }
	local selected_heads = { false, false, false, false }

	-- draw output states
	for o = 1, 4 do
		local y_transposed = get_screen_note_y(output_note[o])
		local level = 7
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
			local head = memory.read_heads[head_index]
			local x = get_screen_offset_x(head.offset)
			local y_original = get_screen_note_y(snap(memory:read_loop_offset(head.offset)))
			-- TODO: how do I make sure the selected head is drawn over the others?
			if output_selector:is_selected(o) then
				selected_heads[head_index] = true
			else
				active_heads[head_index] = true
			end
			-- blink if cursor overlaps and not transposed (if transposed, the original pitch will blink)
			if grid_mode == grid_mode_memory and head.offset == memory.cursor and y_original == y_transposed then
				level = blink_fast and 15 or 7
			end
			screen.level(level)
			screen.move(x, y_transposed)
			screen.line_rel(3, 0)
			screen.stroke()
			-- draw a line connecting transposed output with original note
			screen.level(1)
			local transpose_distance = y_transposed - y_original
			if transpose_distance < -2 or transpose_distance > 2 then
				local transpose_point_y = transpose_distance < 0 and y_transposed + 1 or y_transposed - 3
				screen.pixel(x + 1, transpose_point_y)
				screen.fill()
				local transpose_line_length = math.abs(y_transposed - y_original) - 4
				if transpose_line_length > 0 then
					local transpose_line_top = math.min(y_transposed + 3, y_original)
					screen.move(x + 2, transpose_line_top)
					screen.line_rel(0, transpose_line_length)
					screen.stroke()
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

	-- DEBUG: draw minibuffer, loop region, head
	--[[
	screen.move(0, 1)
	screen.line_rel(memory.buffer_size, 0)
	screen.level(1)
	screen.stroke()
	for offset = memory.start_offset, memory.end_offset do
		screen.pixel(memory:get_loop_pos(offset) - 1, 0)
		if grid_mode == grid_mode_memory and offset == memory.cursor then
			screen.level(blink_fast and 15 or 7)
		elseif offset == memory.start_offset or offset == memory.end_offset or offset == 0 then
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
  pitch_poll_l:stop()
  redraw_metro:stop()
end
