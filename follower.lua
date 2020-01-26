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

-- TODO: save/recall memory/loop contents like masks
-- transposition settings too

-- local memory = {}
-- local mem_size = 32
-- local loop_length = mem_size
-- local head = 1
-- local heads = {}
-- local n_heads = 4
-- local offset_to_edit = 0
-- local offset_to_edit_note = 0
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

local head_selected = 1

local g = grid.connect()

local grid_shift = false
local grid_ctrl = false
local scroll = 4
local keyboard = grid_keyboard.new(6, 1, 10, 8)

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

-- TODO: allow undo??
local function recall_mask(m)
	for i = 1, max_pitch do
		mask[i] = saved_masks[m][i]
	end
	active_mask = m
	mask_dirty = false
end

-- TODO: allow undo??
local function save_mask(m)
	for i = 1, max_pitch do
		saved_masks[m][i] = mask[i]
	end
	active_mask = m
	mask_dirty = false
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
		output_note[out] = snap(keyboard:get_last_note() + output_transpose[out])
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
			memory:write_head(keyboard:get_last_note())
		elseif pitch_in_detected and (source == source_pitch or source == source_pitch_grid) then
			memory:write_head(pitch_in)
		elseif source == source_grid_crow then
			memory:write_head(crow_pitch_in)
		elseif keyboard.gate and source == source_pitch_grid then
			memory:write_head(keyboard:get_last_note())
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

	-- recall buttons
	for x = 1, 4 do
		for y = 3, 6 do
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
		end
	end

	-- shift + ctrl
	g:led(1, 7, grid_shift and 15 or 2)
	g:led(1, 8, grid_ctrl and 15 or 2)

	-- output buttons
	output_selector:draw(g)

	-- scrollbar
	for y = 1, 8 do
		if 9 - y == keyboard.scroll or 8 - y == keyboard.scroll then
			g:led(16, y, 7)
		else
			g:led(16, y, 2)
		end
	end

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
	-- highlight mask
	if mask[n] then
		level = 4
	end
	-- TODO: draw trails / other notes in loop
	-- highlight the note we're editing
	if n == cursor_note then
		-- TODO: maybe make this blinking a little more relaxed
		level = blink_fast and 15 or 10
	end
	return level
end

local function grid_key(x, y, z)
	if keyboard:should_handle_key(x, y) then
		if grid_mode == grid_mode_play then
			keyboard:note(x, y, z)
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
		elseif grid_mode == grid_mode_mask then
			if z == 1 then
				local n = keyboard:get_key_note(x, y)
				local enable = not mask[n]
				local pitch = (n - 1 ) % 12 + 1
				for octave = 0, 7 do
					mask[pitch + octave * 12] = enable
				end
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
		elseif grid_mode == grid_mode_memory then
			keyboard:note(x, y, z)
			if keyboard.gate then
				local note = keyboard:get_last_note()
				memory:write_cursor(note)
				cursor_note = snap(note)
				-- update outputs immediately, if appropriate
				for h = 1, memory.n_read_heads do
					if memory.read_heads[h].pos == memory.cursor then
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
	elseif x == 16 then
		-- scroll
		-- TODO: no more scroll; use octave buttons
		if z == 1 then
			if 9 - y < keyboard.scroll and keyboard.scroll > 1 then
				keyboard.scroll = 9 - y
			elseif 8 - y > keyboard.scroll and keyboard.scroll < 7 then
				keyboard.scroll = 8 - y
			end
		end
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
	elseif x < 5 and y > 2 and y < 7 and z == 1 then
		-- recall buttons
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
		params:add{
			type = 'number',
			id = 'head_' .. i .. '_offset',
			name = 'head ' .. i .. ' offset',
			min = 0,
			max = 31, -- TODO
			default = i * 3,
			action = function(value)
				memory.read_heads[i].offset_min = value * -1
				dirty = true
			end
		}
		params:add{
			type = 'number',
			id = 'head_' .. i .. '_offset_random',
			name = 'head ' .. i .. ' offset random',
			min = 0,
			max = 31, -- TODO
			default = 0,
			action = function(value)
				memory.read_heads[i].offset_random = value
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
			cursor_note = snap(memory:read_absolute(memory.cursor))
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
				for h = 1, memory.n_read_heads do
					local active = false
					for o = 1, 4 do
						active = active or output_source[o] == h
					end
					memory.read_heads[h].active = active
				end
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

local function key_select_head(n)
	-- TODO: select heads based on offsets (i.e. visually) instead of by index
	if n == 2 then
		head_selected = head_selected % 4 + 1
		dirty = true
	elseif n == 3 then
		head_selected = (head_selected - 2) % 4 + 1
		dirty = true
	end
end

local function key_select_pos(n)
	if n == 2 then
		memory:move_cursor(-1)
		cursor_note = snap(memory:read_absolute(memory.cursor))
	elseif n == 3 then
		memory:move_cursor(1)
		cursor_note = snap(memory:read_absolute(memory.cursor))
	end
end

function key(n, z)
	if n == 1 then
		key_shift = z == 1
	elseif z == 1 then
		if grid_mode == grid_mode_play then
			if key_shift then
				key_select_head(n)
			else
				key_shift_clock(n)
			end
		elseif grid_mode == grid_mode_mask then
			if key_shift then
				key_shift_clock(n)
			else
				key_select_head(n)
			end
		elseif grid_mode == grid_mode_transpose then
			if key_shift then
				key_shift_clock(n)
			else
				key_select_head(n)
			end
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
		params:delta('head_' .. head_selected .. '_offset_max', d * -1)
	elseif n == 3 then
		params:delta('head_' .. head_selected .. '_offset_random', d)
	end
end

local function draw_head_brackets(h)
	-- TODO
	-- if not memory.read_heads[h].active then
		return
	-- end
	-- local x1 = (mem_size - heads[h].offset_max - 1) * 4 + 2
	-- local x2 = x1 + 2 + (math.min(heads[h].offset_max, heads[h].offset_random)) * 4
	-- screen.move(x2, 2)
	-- screen.line(x2, 1)
	-- screen.line(x1, 1)
	-- screen.line(x1, 2)
	-- screen.stroke()
	-- screen.move(x2, 62)
	-- screen.line(x2, 64)
	-- screen.line(x1, 64)
	-- screen.line(x1, 62)
	-- screen.stroke()
end

function redraw()
	screen.clear()
	screen.stroke()
	screen.line_width(1)

	-- local y_memory = {}

	-- draw head/range indicators
	-- for h = 1, memory.n_read_heads do
		-- if h ~= head_selected then
			-- screen.level(1)
			-- -- draw_head_brackets(h)
		-- end
	-- end
	-- screen.level(3)
	-- draw_head_brackets(head_selected)

	-- draw loop region
	-- local x = (mem_size - loop_length) * 4
	-- screen.level(1)
	-- for y = 4, 60 do
		-- if y % 2 == 0 then
			-- screen.level(2)
			-- screen.pixel(x, y)
			-- screen.fill()
		-- end
	-- end

	-- draw memory contents
	local screen_note_width = 4
	local n_screen_notes = 128 / screen_note_width
	local screen_note_center = math.floor((n_screen_notes - 1) / 2)
	-- local n_ghost_notes = n_screen_notes - memory.length
	-- local n_ghost_notes_left = math.floor(n_ghost_notes / 2)
	-- local x = 1
	for n = 1, n_screen_notes do
		local x = (n - 1) * screen_note_width
		local y = 63 + keyboard.scroll * 2 - snap(memory:read_loop_offset(n - screen_note_center))
		if n == screen_note_center then
			screen.level(4)
		else
			screen.level(1)
		end
		screen.move(x, y)
		screen.line_rel(3, 0)
		screen.stroke()
	end

	-- for offset = 0, mem_size - 1 do
		-- local x = (mem_size - offset - 1) * 4 + 1
		-- local pos = get_offset_pos(offset)
		-- if grid_mode == grid_mode_memory and offset == offset_to_edit then
			-- screen.level(blink_fast and 15 or 7)
		-- elseif offset > loop_length - 1 then
			-- screen.level(1)
		-- else
			-- screen.level(2)
		-- end
		-- y_memory[pos] = 63 + keyboard.scroll * 2 - snap(memory[pos])
		-- screen.move(x, y_memory[pos])
		-- screen.line_rel(3, 0)
		-- screen.stroke()
	-- end

	-- draw incoming grid pitch
	-- for o = 1, 4 do
		-- local y = -1
		-- if output_source[o] == output_source_grid then
			-- y = 63 + keyboard.scroll * 2 - snap(keyboard:get_last_note())
		-- elseif pitch_in_detected and (output_source[o] == output_source_audio_in) then
			-- y = 63 + keyboard.scroll * 2 - snap(quantize(pitch_in))
		-- end
		-- if y > -1 then
			-- screen.pixel(127, y - 1)
			-- screen.level(2)
			-- screen.fill()
		-- end
	-- end

	-- draw output states
	-- for o = 1, 4 do
		-- local y_transposed = 63 + keyboard.scroll * 2 - output_note[o]
		-- local level = 7
		-- -- in transpose mode, blink selected output(s)
		-- if grid_mode == grid_mode_transpose and output_selector:is_selected(o) then
			-- if blink_fast then
				-- level = 15
			-- else
				-- level = 7
			-- end
		-- end
		-- if output_source[o] == output_source_head_1 or output_source[o] == output_source_head_2 or output_source[o] == output_source_head_3 or output_source[o] == output_source_head_4 then
			-- local output_head = output_source[o]
			-- local x = 129 - ((heads[output_head].offset + 1) % mem_size * 4)
			-- local y_original = y_memory[heads[output_head].pos]
			-- if grid_mode == grid_mode_memory and heads[output_head].offset == offset_to_edit then
				-- level = blink_fast and 15 or 7
			-- end
			-- screen.level(level)
			-- screen.move(x, y_transposed)
			-- screen.line_rel(3, 0)
			-- screen.stroke()
			-- -- draw a line connecting transposed output with original note
			-- screen.level(1)
			-- local transpose_distance = y_transposed - y_original
			-- if transpose_distance < -2 or transpose_distance > 2 then
				-- local transpose_point_y = transpose_distance < 0 and y_transposed + 1 or y_transposed - 3
				-- screen.pixel(x + 1, transpose_point_y)
				-- screen.fill()
				-- local transpose_line_length = math.abs(y_transposed - y_original) - 4
				-- -- if transpose_line_length > 0 then
					-- local transpose_line_top = math.min(y_transposed + 3, y_original)
					-- screen.move(x + 2, transpose_line_top)
					-- screen.line_rel(0, transpose_line_length)
					-- screen.stroke()
				-- end
			-- end
		-- elseif output_source[o] == output_source_audio_in or output_source[o] == output_source_grid then
			-- -- draw output pitch
			-- screen.pixel(127, y_transposed - 1)
			-- screen.level(level)
			-- screen.fill()
		-- end
	-- end

	-- DEBUG: positions
	screen.move(0, 1)
	screen.line_rel(memory.buffer_size, 0)
	screen.level(1)
	screen.stroke()
	screen.pixel(memory:get_loop_pos(0) - 1, 0)
	screen.level(15)
	screen.fill()
	screen.pixel(memory:get_loop_pos(memory.length - 1) - 1, 0)
	screen.level(15)
	screen.fill()
	for offset = 1, memory.length - 2 do
		screen.pixel(memory:get_loop_pos(offset) - 1, 0)
		screen.level(7)
		screen.fill()
	end

	screen.update()
end

function cleanup()
  pitch_poll_l:stop()
  redraw_metro:stop()
end
