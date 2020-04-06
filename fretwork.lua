-- fretwork
--
-- shift register sequencer,
-- microtonal autoharp,
-- etc.

engine.name = 'PolySub'
polysub = require 'we/lib/polysub'

musicutil = require 'musicutil'
BeatClock = require 'beatclock'

X0XRoll = include 'lib/grid_x0x_roll'
Keyboard = include 'lib/grid_keyboard'
Select = include 'lib/grid_select'
MultiSelect = include 'lib/grid_multi_select'
ShiftRegister = include 'lib/shift_register'
ShiftRegisterVoice = include 'lib/shift_register_voice'
Scale = include 'lib/scale'
Blinker = include 'lib/blinker'

pitch_poll = nil
pitch_in_value = 0
pitch_in_detected = false
pitch_in_octave = 0
crow_in_values = { 0, 0 }

-- calculate pitch class values
et12 = {} -- 12TET
for p = 1, 12 do 
	et12[p] = p / 12
end
scale = Scale.new(et12)

saved_masks = {}
mask_dirty = false
mask_selector = Select.new(1, 3, 4, 4)
mask_selector.on_select = function(m)
	if held_keys.shift then
		save_mask(m)
	else
		recall_mask(m)
	end
end

saved_transpositions = {}
transposition_dirty = false
transposition_selector = Select.new(1, 3, 4, 4)
transposition_selector.on_select = function(c)
	if held_keys.shift then
		save_transposition(c)
	else
		recall_transposition(c)
	end
end

saved_pitch_loops = {}
-- TODO: multi selects for 'pattern chaining'... or maybe pattern_time
pitch_loop_selector = Select.new(1, 3, 4, 4)
pitch_loop_selector.on_select = function(l)
	if held_keys.shift then
		save_pitch_loop(l)
	else
		recall_pitch_loop(l)
	end
end

saved_mod_loops = {}
mod_loop_selector = Select.new(1, 3, 4, 4)
mod_loop_selector.on_select = function(l)
	if held_keys.shift then
		save_mod_loop(l)
	else
		recall_mod_loop(l)
	end
end

memory_selector = MultiSelect.new(1, 2, 4, 1)
memory_pitch_loop = 1
memory_mask = 2
memory_transposition = 3
memory_mod_loop = 4

pitch_register = ShiftRegister.new(32)
mod_register = ShiftRegister.new(11)

source = 1
source_names = {
	'grid only',
	'pitch track',
	'crow input 2' -- TODO: make sure this works
	-- TODO: random, LFO
}
source_grid_only = 1
source_pitch = 2
source_crow = 3

noop = function() end
events = {
	beat = noop,
	trigger1 = noop,
	trigger2 = noop,
	key = noop
}

write_enable = true
write_probability = 0

clock_enable = false
beatclock = BeatClock.new()
beatclock.on_step = function()
	-- TODO: take advantage of this resolution: give voices/taps fractional shift rates
	-- (positive or negative), instead of directions
	if beatclock.step == 0 or beatclock.step == 2 then
		events.beat()
	end
end
beatclock.on_start = function()
	clock_enable = true
end
beatclock.on_stop = function()
	clock_enable = false
end

clock_mode = 1
clock_mode_names = {
	'crow input 1',
	'grid',
	'crow in OR grid',
	'beatclock'
}
clock_mode_trig = 1
clock_mode_grid = 2
clock_mode_trig_grid = 3
clock_mode_beatclock = 4

voices = {}
n_voices = 4
voice_draw_order = { 4, 3, 2, 1 }
top_voice_index = 1
for v = 1, n_voices do
	local voice = ShiftRegisterVoice.new(v * -3, pitch_register, scale, v * -4, mod_register)
	voices[v] = voice
end
top_voice = voices[top_voice_index]

grid_mode_selector = Select.new(1, 1, 4, 1)
grid_mode_pitch = 1
grid_mode_mask = 2
grid_mode_transpose = 3
grid_mode_mod = 4

voice_selector = MultiSelect.new(5, 3, 1, 4)

g = grid.connect()
m = midi.connect()

held_keys = {
	ctrl = false,
	ctrl_lock = false,
	shift = false,
	octave_down = false,
	octave_up = false,
}

view_octave = 0

pitch_keyboard_played = false -- i.e. played since last tick
pitch_keyboard = Keyboard.new(6, 1, 11, 8, scale)
mask_keyboard = Keyboard.new(6, 1, 11, 8, scale)
transpose_keyboard = Keyboard.new(6, 1, 11, 8, scale)
keyboards = { -- lookup array; indices match corresponding modes
	pitch_keyboard,
	mask_keyboard,
	transpose_keyboard
}
active_keyboard = pitch_keyboard

x0x_roll = X0XRoll.new(6, 1, 11, 8, n_voices, voices)

screen_note_width = 4
n_screen_notes = 128 / screen_note_width
screen_note_center = math.floor((n_screen_notes - 1) / 2 + 0.5)
screen_notes = { {}, {}, {}, {} }

recent_writes = { nil, nil, nil, nil, nil, nil, nil, nil }
n_recent_writes = 8
last_write = 0

key_shift = false
key_pitch = false
key_mod = false
blink_slow = false
framerate = 1 / 15
blinkers = {
	info = Blinker.new(0.75),
	play = Blinker.new(framerate),
	record = Blinker.new(framerate)
}
dirty = false

redraw_metro = metro.init{
	time = framerate,
	event = function(tick)
		x0x_roll:smooth_hold_distance()
		if not blink_slow and tick % 8 > 3 then
			blink_slow = true
			dirty = true
		elseif blink_slow and tick % 8 <= 3 then
			blink_slow = false
			dirty = true
		end
		if dirty then
			grid_redraw()
			redraw()
			dirty = false
		end
	end
}

function quantization_off()
	-- disable quantization if ctrl is held/locked or clock is paused
	return (held_keys.ctrl ~= held_keys.ctrl_lock) == clock_enable
end

-- TODO: the way voice offsets are recalled seems to be inconsistent when restoring a loop along
-- with config, if the new loop length is different from the current loop length; it's probably
-- important to make sure loop length and offsets are saved/restored in a consistent order
function recall_pitch_loop()
	local loop = saved_pitch_loops[pitch_loop_selector.selected]
	for v = 1, n_voices do
		voices[v].pitch_tap:set_offset(loop.voices[v].offset)
		params:set(string.format('voice_%d_pitch_scramble', v), loop.voices[v].scramble)
		params:set(string.format('voice_%d_pitch_direction', v), loop.voices[v].direction)
	end
	if quantization_off() then
		pitch_register:set_loop(0, loop.values)
		-- silently update the loop length
		params:set('pitch_loop_length', pitch_register.length, true)
		update_voices()
	else
		pitch_register:set_next_loop(1, loop.values)
		-- TODO: make sure the voices only get updated AFTER the loop is applied, otherwise length +
		-- offsets will get weird
	end
end

function save_pitch_loop()
	local offset = quantization_off() and 0 or 1 -- if quantizing, save the future loop state (on the next tick)
	local loop = {
		values = {},
		voices = {}
	}
	loop.values = pitch_register:get_loop(offset)
	for v = 1, n_voices do
		loop.voices[v] = {
			offset = voices[v].pitch_tap:get_offset(),
			scramble = voices[v].pitch_tap.scramble,
			direction = voices[v].pitch_tap.direction
		}
	end
	saved_pitch_loops[pitch_loop_selector.selected] = loop
	pitch_register.dirty = false
end

function recall_mask()
	local mask = saved_masks[mask_selector.selected]
	scale:set_next_mask(scale:pitches_to_mask(mask))
	if quantization_off() then
		update_voices()
	end
	mask_dirty = false
end

function save_mask()
	saved_masks[mask_selector.selected] = scale:mask_to_pitches(scale:get_next_mask())
	mask_dirty = false
end

function recall_transposition()
	local t = transposition_selector.selected
	for v = 1, n_voices do
		params:set(string.format('voice_%d_transpose', v), saved_transpositions[t][v])
	end
	if quantization_off() then
		update_voices()
	end
	transposition_dirty = false
end

function save_transposition()
	local transposition = {}
	for v = 1, n_voices do
		transposition[v] = voices[v].next_transpose
	end
	saved_transpositions[transposition_selector.selected] = transposition
	transposition_dirty = false
end

function recall_mod_loop()
	local loop = saved_mod_loops[mod_loop_selector.selected]
	for v = 1, n_voices do
		voices[v].mod_tap:set_offset(loop.voices[v].offset)
		params:set(string.format('voice_%d_mod_scramble', v), loop.voices[v].scramble)
		params:set(string.format('voice_%d_mod_direction', v), loop.voices[v].direction)
	end
	if quantization_off() then
		mod_register:set_loop(0, loop.values)
		-- silently update the lopo length
		params:set('mod_loop_length', mod_register.length, true)
		update_voices()
	else
		mod_register:set_next_loop(1, loop.values)
		-- TODO: make sure the voices only get updated AFTER the loop is applied, otherwise length +
		-- offsets will get weird
	end
end

function save_mod_loop()
	local offset = quantization_off() and 0 or 1
	local loop = {
		values = {},
		voices = {}
	}
	loop.values = mod_register:get_loop(offset)
	for v = 1, n_voices do
		loop.voices[v] = {
			offset = voices[v].mod_tap:get_offset(),
			scramble = voices[v].mod_tap.scramble,
			direction = voices[v].mod_tap.direction
		}
	end
	saved_mod_loops[mod_loop_selector.selected] = loop
	mod_register.dirty = false
end

function update_voice(v)
	local voice = voices[v]
	voice:update_values()
	if voice.active and voice.mod > 0 then
		engine.start(v - 1, musicutil.note_num_to_freq(60 + voice.pitch * 12))
		-- crow.output[v].volts = voice.value
	else
		engine.stop(v - 1)
	end
end

function update_voices()
	for v = 1, n_voices do
		update_voice(v)
	end
end

function get_write_pitch()
	-- TODO: watch debug output using pitch + crow sources to make sure they're working
	if (pitch_keyboard_played or pitch_keyboard.gate) then
		pitch_keyboard_played = false
		print(string.format('writing grid pitch (source = %d)', source))
		return pitch_keyboard:get_last_value()
	elseif source == source_pitch then
		print(string.format('writing audio pitch (source = %d)', source))
		return pitch_in_value
	elseif source == source_crow then
		print(string.format('writing crow pitch (source = %d)', source))
		return crow_in_values[2]
	end
	-- print(string.format('nothing to write (source = %d)', source))
	return false
end

function maybe_write()
	if write_enable and write_probability > math.random(1, 100) then
		local pitch = get_write_pitch()
		if pitch then
			write(pitch)
		end
	end
end

function write(pitch)
	for v = 1, n_voices do
		if voice_selector:is_selected(v) then
			local voice = voices[v]
			voice:set_pitch(0, pitch)
			last_write = last_write % n_recent_writes + 1
			recent_writes[last_write] = {
				level = 15,
				pitch_pos = voice.pitch_tap:get_pos(0),
				mod_pos = voice.mod_tap:get_pos(0)
			}
			update_voice(v)
		end
	end
	blinkers.record:start()
end

function shift(d)
	-- TODO: only shift registers if they're synced with the top voice
	pitch_register:shift(d)
	mod_register:shift(d)
	x0x_roll:shift(-d)
	for v = 1, n_voices do
		voices[v]:shift(d)
	end
	maybe_write()
	scale:apply_edits()
	update_voices()
	-- silently update loop length params, as they may have changed after shift
	params:set('pitch_loop_length', pitch_register.length, true)
	params:set('mod_loop_length', mod_register.length, true)
	dirty = true
end

function advance()
	shift(1)
end

function rewind()
	shift(-1)
end

function tick()
	if not clock_enable then
		return
	end
	advance()
	blinkers.play:start()
end

function update_voice_order()
	local selected = {}
	local new_draw_order = {}
	for i, v in ipairs(voice_draw_order) do
		if voice_selector:is_selected(v) then
			table.insert(selected, v)
		else
			table.insert(new_draw_order, v)
		end
	end
	for i, v in ipairs(selected) do
		table.insert(new_draw_order, v)
	end
	top_voice_index = new_draw_order[n_voices]
	top_voice = voices[top_voice_index]
	voice_draw_order = new_draw_order
end

function grid_redraw()

	-- mode buttons
	grid_mode_selector:draw(g, 7, 2)

	-- recall mode buttons
	memory_selector:draw(g, 7, 2)

	-- recall buttons, for all selected memory types
	for x = 1, 4 do
		for y = 3, 6 do
			local level = 2
			if memory_selector:is_selected(memory_pitch_loop) and pitch_loop_selector:is_selected(pitch_loop_selector:get_key_option(x, y)) then
				level = math.max(level, pitch_register.dirty and blink_slow and 8 or 7)
			end
			if memory_selector:is_selected(memory_mask) and mask_selector:is_selected(mask_selector:get_key_option(x, y)) then
				level = math.max(level, mask_dirty and blink_slow and 8 or 7)
			end
			if memory_selector:is_selected(memory_transposition) and transposition_selector:is_selected(transposition_selector:get_key_option(x, y)) then
				level = math.max(level, transposition_dirty and blink_slow and 8 or 7)
			end
			if memory_selector:is_selected(memory_mod_loop) and mod_loop_selector:is_selected(mod_loop_selector:get_key_option(x, y)) then
				level = math.max(level, mod_register.dirty and blink_slow and 8 or 7)
			end
			g:led(x, y, level)
		end
	end

	-- shift + ctrl
	g:led(1, 7, held_keys.shift and 15 or 2)
	if held_keys.ctrl_lock then
		g:led(1, 8, held_keys.ctrl and 2 or 10)
	else
		g:led(1, 8, held_keys.ctrl and 15 or 2)
	end

	-- voice buttons
	for y = voice_selector.y, voice_selector.y2 do
		local level = 0
		local voice_index = voice_selector:get_key_option(voice_selector.x, y)
		local voice = voices[voice_index]
		local mod_level = (voice.active and voice.mod > 0) and 1 or 0
		if voice.next_active then
			if voice_index == top_voice_index then
				level = 14 + mod_level
			elseif voice_selector:is_selected(voice_index) then
				level = 9 + mod_level
			else
				level = 3 + mod_level
			end
		else
			if voice_index == top_voice_index then
				level = 12 + mod_level
			elseif voice_selector:is_selected(voice_index) then
				level = 7 + mod_level
			else
				level = 1 + mod_level
			end
		end
		g:led(voice_selector.x, y, level)
	end

	-- octave switches
	g:led(3, 8, 2 - math.min(view_octave, 0))
	g:led(4, 8, 2 + math.max(view_octave, 0))

	if active_keyboard ~= nil then
		-- keyboard, for keyboard-based modes
		active_keyboard:draw(g)
	else
		-- 'x0x-roll' interface for mod mode
		x0x_roll:draw(g)
	end

	-- transport
	local play_button_level = 3
	if blinkers.play.on then
		play_button_level = 8
	elseif clock_enable then
		play_button_level = 7
	end
	g:led(3, 7, play_button_level)
	local record_button_level = 3
	if blinkers.record.on then
		record_button_level = 8
	elseif write_enable then
		if write_probability > 0 then
			record_button_level = 7
		else
			record_button_level = 4
		end
	end
	g:led(4, 7, record_button_level)

	g:refresh()
end

function pitch_keyboard:get_key_level(x, y, n)
	local level = 0
	-- highlight mask
	if self.scale:mask_contains(n) then
		level = 4
	end
	-- highlight voice notes
	for v = 1, n_voices do
		local voice = voices[v]
		if voice.active and voice.mod > 0 and n == voice.pitch_id then
			if v == top_voice_index then
				level = 14
			elseif voice_selector:is_selected(v) then
				level = math.max(level, 10)
			else
				level = math.max(level, 7)
			end
		end
	end
	-- highlight current note
	if self.gate and self:is_key_last(x, y) then
		level = 15
	end
	return level
end

function mask_keyboard:get_key_level(x, y, n)
	local level = 0
	-- highlight white keys
	if self:is_white_key(n) then
		level = 2
	end
	-- highlight mask
	local in_mask = self.scale:mask_contains(n)
	local in_next_mask = self.scale:next_mask_contains(n)
	if in_mask and in_next_mask then
		level = 5
	elseif in_next_mask then
		level = 4
	elseif in_mask then
		level = 3
	end
	-- highlight voice notes
	for v = 1, n_voices do
		local voice = voices[v]
		if voice.active and voice.mod > 0 and n == voice.pitch_id then
			if v == top_voice_index then
				level = 14
			elseif voice_selector:is_selected(v) then
				level = math.max(level, 10)
			else
				level = math.max(level, 7)
			end
		end
	end
	return level
end

function transpose_keyboard:get_key_level(x, y, n)
	local level = 0
	-- highlight octaves
	if (n - self.scale.center_pitch_id) % self.scale.length == 1 then
		level = 2
	end
	-- highlight transposition settings
	for v = 1, n_voices do
		local voice = voices[v]
		if voice.active then
			local is_transpose = n == self.scale:get_nearest_pitch_id(voices[v].transpose)
			local is_next_transpose = n == self.scale:get_nearest_pitch_id(voices[v].next_transpose)
			if is_transpose and is_next_transpose then
				if v == top_voice_index then
					level = 14
				elseif voice_selector:is_selected(v) then
					level = math.max(level, 10)
				else
					level = math.max(level, 5)
				end
			elseif is_next_transpose then
				if v == top_voice_index then
					level = math.max(level, 8)
				elseif voice_selector:is_selected(v) then
					level = math.max(level, 7)
				else
					level = math.max(level, 4)
				end
			elseif is_transpose then
				level = math.max(level, 3)
			end
		end
	end
	return level
end

function x0x_roll:get_key_level(x, y, v, offset, value)
	local head = offset == 0
	local gate = value > 0
	local active = voices[v].active
	if not active then
		if gate then
			return 2
		elseif head then
			return 1
		end
	elseif v == top_voice_index then
		if gate then
			if head then
				return 14
			end
			return 9
		elseif head then
			return 2
		end
	elseif voice_selector:is_selected(v) then
		if gate then
			if head then
				return 12
			end
			return 7
		elseif head then
			return 2
		end
	end
	if gate then
		if head then
			return 6
		end
		return 4
	elseif head then
		return 2
	end
	return 0
end

function toggle_mask_class(pitch_id)
	scale:toggle_class(pitch_id)
	mask_dirty = true
	if quantization_off() then
		scale:apply_edits()
		update_voices()
	end
end

function pitch_keyboard:key(x, y, z)
	if held_keys.shift then
		-- TODO: fix stuck notes when holding a key, holding shift, then letting go of key
		if z == 1 then
			toggle_mask_class(self:get_key_pitch_id(x, y))
		end
		return
	end
	local previous_note = self:get_last_pitch_id()
	self:note(x, y, z)
	if self.gate and (z == 1 or previous_note ~= self:get_last_pitch_id()) then
		if write_enable then
			if quantization_off() then
				write(self:get_last_value())
			else
				pitch_keyboard_played = true
			end
		end
		events.key()
	end
end

function mask_keyboard:key(x, y, z)
	if z == 1 then
		toggle_mask_class(self:get_key_pitch_id(x, y))
	end
end

function transpose_keyboard:key(x, y, z)
	self:note(x, y, z)
	if not self.gate then
		return
	end
	local transpose = self:get_last_value() - top_voice.next_transpose
	for v = 1, n_voices do
		if voice_selector:is_selected(v) then
			params:set(string.format('voice_%d_transpose', v), voices[v].next_transpose + transpose)
		end
	end
	if quantization_off() then
		update_voices()
	end
end

function grid_octave_key(z, d)
	if d < 0 then
		held_keys.octave_down = z == 1
	elseif d > 0 then
		held_keys.octave_up = z == 1
	end
	if z == 1 then
		if held_keys.octave_down and held_keys.octave_up then
			view_octave = 0
		else
			view_octave = view_octave + d
		end
	end
	if active_keyboard ~= nil then
		active_keyboard.octave = view_octave
	end
end

function grid_key(x, y, z)
	if active_keyboard ~= nil and active_keyboard:should_handle_key(x, y) then
		active_keyboard:key(x, y, z)
	elseif grid_mode_selector:is_selected(grid_mode_mod) and x0x_roll:should_handle_key(x, y) then
		x0x_roll:key(x, y, z)
		if quantization_off() then
			update_voices()
		end
	elseif voice_selector:should_handle_key(x, y) then
		if held_keys.shift then
			if z == 1 then
				local voice_index = voice_selector:get_key_option(x, y)
				local voice = voices[voice_index]
				voice.next_active = not voice.active
				if quantization_off() then
					update_voice(voice_index)
				end
			end
		else
			voice_selector:key(x, y, z)
			if z == 1 then
				update_voice_order()
			end
		end
	elseif x == 3 and y == 8 then
		grid_octave_key(z, -1)
	elseif x == 4 and y == 8 then
		grid_octave_key(z, 1)
	elseif grid_mode_selector:should_handle_key(x, y) then
		-- clear the current keyboard's held note stack, in order to prevent held notes from getting
		-- stuck when switching to a mode that doesn't call `keyboard:note()`
		if active_keyboard ~= nil then
			active_keyboard:reset()
		end
		grid_mode_selector:key(x, y, z)
		active_keyboard = keyboards[grid_mode_selector.selected]
	elseif memory_selector:should_handle_key(x, y) then
		memory_selector:key(x, y, z)
	elseif x <= 4 and y >= 3 and y <= 6 then
		if memory_selector:is_selected(memory_mask) then
			mask_selector:key(x, y, z)
		end
		if memory_selector:is_selected(memory_transposition) then
			transposition_selector:key(x, y, z)
		end
		if memory_selector:is_selected(memory_pitch_loop) then
			pitch_loop_selector:key(x, y, z)
		end
		if memory_selector:is_selected(memory_mod_loop) then
			mod_loop_selector:key(x, y, z)
		end
	elseif x == 1 and y == 7 then
		-- shift key
		held_keys.shift = z == 1
	elseif x == 1 and y == 8 then
		-- ctrl key
		if z == 1 and held_keys.shift then
			held_keys.ctrl_lock = not held_keys.ctrl_lock
		end
		held_keys.ctrl = z == 1
	elseif x == 3 and y == 7 and z == 1 then
		-- play key
		if clock_mode == clock_mode_beatclock then
			if clock_enable then
				beatclock:stop()
			else
				beatclock:reset()
				beatclock:start()
			end
		else
			clock_enable = not clock_enable
		end
	elseif x == 4 and y == 7 and z == 1 then
		-- record key
		write_enable = not write_enable
	end
	dirty = true
end

function midi_event(data)
	local msg = midi.to_msg(data)
	if msg.type == 'note_on' then
		for v = 1, n_voices do
			local voice = voices[v]
			if voice.clock_channel == msg.ch and voice.clock_note == msg.note then
				voice:shift(1)
				update_voice(v)
				dirty = true
			end
		end
	end
end

function update_freq(value)
	-- TODO: better check amplitude too -- this detects a 'pitch' when there's no audio input
	pitch_in_detected = value > 0
	if pitch_in_detected then
		pitch_in_value = math.log(value / 440.0) / math.log(2) + 3.75 + pitch_in_octave
		dirty = true
	end
end

function crow_setup()
	crow.clear()
	-- input modes will be set by params
	crow.input[1].change = function()
		events.trigger1()
	end
	crow.input[2].change = function()
		events.trigger2()
	end
	crow.input[1].stream = function(value) -- not used... yet!
		crow_in_values[1] = value
	end
	crow.input[2].stream = function(value)
		crow_in_values[2] = value
	end
	params:bang()
end

function add_params()

	params:add_separator()

	params:add_group('clock', 4)
	params:add{
		type = 'option',
		id = 'shift_clock',
		name = 'sr/s+h clock',
		options = clock_mode_names,
		default = clock_mode_beatclock,
		action = function(value)
			clock_mode = value
			if clock_mode == clock_mode_grid or clock_mode == clock_mode_trig_grid then
				events.key = tick
			else
				events.key = noop
			end
			if clock_mode == clock_mode_trig or clock_mode == clock_mode_trig_grid then
				events.trigger1 = tick
				crow.input[1].mode('change', 2.0, 0.25, 'rising')
			else
				events.trigger1 = noop
				crow.input[1].mode('none')
			end
			if clock_mode == clock_mode_beatclock then
				events.beat = tick
				beatclock:start()
			else
				events.beat = noop
				beatclock:stop()
			end
		end
	}
	beatclock:add_clock_params()

	params:add{
		type = 'number',
		id = 'pitch_loop_length',
		name = 'pitch loop length',
		min = 2,
		max = 128,
		default = 16,
		-- TODO: make this adjust loop length with the top voice's current note as the loop end point,
		-- so one could easily lock in the last few notes heard; I don't really get what it's doing now
		action = function(value)
			pitch_register:set_length(value)
			update_voices()
			blinkers.info:start()
			dirty = true
		end
	}
	params:add{
		type = 'number',
		id = 'mod_loop_length',
		name = 'mod loop length',
		min = 2,
		max = 128,
		default = 18,
		action = function(value)
			mod_register:set_length(value)
			update_voices()
			blinkers.info:start()
			dirty = true
		end
	}
	params:add{
		type = 'option',
		id = 'shift_source',
		name = 'sr source',
		options = source_names,
		default = source_grid_only,
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
		controlspec = controlspec.new(1, 101, 'exp', 1, 101),
		formatter = function(param)
			return string.format('%1.f%%', param:get() - 1)
		end,
		action = function(value)
			write_probability = value - 1
			blinkers.info:start()
		end
	}
	-- TODO: can you do away with this, now that you're applying the current voice's transposition to all recorded notes?
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
	
	for v = 1, n_voices do
		local voice = voices[v]
		params:add_group(string.format('voice %d', v), 8)
		-- TODO: maybe some of these things really shouldn't be params?
		params:add{
			type = 'control',
			id = string.format('voice_%d_detune', v),
			name = string.format('voice %d detune', v),
			controlspec = controlspec.new(-50, 50, 'lin', 0.5, (v - 2.5) * 2, 'cents'),
			action = function(value)
				voice.detune = value / 1200
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_transpose', v),
			name = string.format('voice %d transpose', v),
			controlspec = controlspec.new(-4, 4, 'lin', 1 / scale.length, 0, 'st'),
			action = function(value)
				voice.next_transpose = value
				transposition_dirty = true
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_pitch_scramble', v),
			name = string.format('voice %d pitch scramble', v),
			controlspec = controlspec.new(0, 16, 'lin', 0.2, 0),
			action = function(value)
				voice.pitch_tap.scramble = value
				dirty = true
				transposition_dirty = true
			end
		}
		params:add{
			type = 'option',
			id = string.format('voice_%d_pitch_direction', v),
			name = string.format('voice %d pitch direction', v),
			options = {
				'forward',
				'retrograde'
			},
			action = function(value)
				voice.pitch_tap.direction = value == 2 and -1 or 1
				dirty = true
				transposition_dirty = true
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_mod_scramble', v),
			name = string.format('voice %d mod scramble', v),
			controlspec = controlspec.new(0, 16, 'lin', 0.2, 0),
			action = function(value)
				voice.mod_tap.scramble = value
				dirty = true
				transposition_dirty = true
			end
		}
		params:add{
			type = 'option',
			id = string.format('voice_%d_mod_direction', v),
			name = string.format('voice %d mod direction', v),
			options = {
				'forward',
				'retrograde'
			},
			action = function(value)
				voice.mod_tap.direction = value == 2 and -1 or 1
				dirty = true
				transposition_dirty = true
			end
		}
		-- TODO: inversion too? value scaling?
		-- TODO: maybe even different loop lengths... which implies multiple independent SRs
		params:add{
			type = 'number',
			id = string.format('voice_%d_clock_note', v),
			name = string.format('voice %d clock note', v),
			min = 0,
			max = 127,
			default = 63 + v,
			action = function(value)
				voice.clock_note = value
			end
		}
		params:add{
			type = 'number',
			id = string.format('voice_%d_clock_channel', v),
			name = string.format('voice %d clock channel', v),
			min = 1,
			max = 16,
			default = 1,
			action = function(value)
				voice.clock_channel = value
			end
		}
	end

	params:add_separator()

	params:add_group('polysub', 19)
	polysub.params()

	params:add_group('crow', 4)
	for v = 1, n_voices do
		params:add{
			type = 'control',
			id = string.format('voice_%d_slew', v),
			name = string.format('voice %d slew', v),
			controlspec = controlspec.new(1, 1000, 'exp', 1, 4, 'ms'),
			action = function(value)
				crow.output[v].slew = value / 1000
			end
		}
	end

	params:add_separator()

	-- TODO: set tuning root note (as scale degree, or in 12 equal?)
	params:add{
		type = 'file',
		id = 'tuning_file',
		name = 'tuning_file',
		path = '/home/we/dust/data/fretwork/scales/y/young-lm_guitar.scl',
		action = function(value)
			scale:read_scala_file(value)
			mask_keyboard:set_white_keys()
		end
	}

	params:add{
		type = 'trigger',
		id = 'restore_memory',
		name = 'restore memory',
		action = function()
			-- TODO: allow multiple memory files, using a 'data file' param
			local data_file = norns.state.data .. 'memory.lua'
			if util.file_exists(data_file) then
				local data, errorMessage = tab.load(data_file)
				if errorMessage ~= nil then
					error(errorMessage)
				else
					set_memory(data)
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
			data.pitch_loops = saved_pitch_loops
			data.mod_loops = saved_mod_loops
			tab.save(data, data_file)
		end
	}
end

function set_memory(data)

	if type(data) ~= 'table' then
		data = {}
	end

	-- restore/initialize pitch loops
	saved_pitch_loops = {}
	for l = 1, 16 do
		local loop = {
			values = {},
			voices = {}
		}
		if data.pitch_loops ~= nil and data.pitch_loops[l] ~= nil then
			-- restore
			local old_loop = data.pitch_loops[l]
			if old_loop.values ~= nil then
				-- newest format
				for i, v in ipairs(old_loop.values) do
					loop.values[i] = v
				end
				for v = 1, n_voices do
					loop.voices[v] = {
						offset = old_loop.voices[v].offset,
						scramble = old_loop.voices[v].scramble or 0, -- TODO: remove these fallbacks once everything's converted
						direction = old_loop.voices[v].direction or 1
					}
				end
			else
				-- old format
				for i, v in ipairs(old_loop) do
					loop.values[i] = v
				end
				for v = 1, n_voices do
					loop.voices[v] = {
						offset = v * -3,
						scramble = data.configs[l][v].pitch_scramble or 0,
						direction = data.configs[l][v].pitch_direction or 1
					}
				end
			end
		else
			-- initialize
			for i = 1, 16 do
				saved_pitch_loops[l].values[i] = 0
			end
			for v = 1, 4 do
				saved_mod_loops[l].voices[v] = {
					offset = v * -3,
					scramble = 0,
					direction = 1
				}
			end
		end
		saved_pitch_loops[l] = loop
	end
	pitch_register.dirty = true

	-- restore/initialize masks
	saved_masks = {}
	for m = 1, 16 do
		local mask = {}
		if data.masks ~= nil and data.masks[m] ~= nil then
			-- restore
			for i, v in ipairs(data.masks[m]) do
				mask[i] = v
			end
		else
			-- initialize
			for i = 1, 12 do
				mask[i] = { 0, 2/12, 4/12, 5/12, 7/12, 9/12, 11/12 } -- C major
			end
		end
		saved_masks[m] = mask
	end
	mask_dirty = true

	-- restore/initialize transpositions
	saved_transpositions = {}
	for t = 1, 16 do
		local transposition = {}
		if data.transpositions ~= nil and data.transpositions[t] ~= nil then
			-- restore
			for v = 1, n_voices do
				transposition[v] = data.transpositions[t][v]
			end
		elseif data.configs ~= nil and data.configs[t] ~= nil then
			-- restore old format
			for v = 1, n_voices do
				transposition[v] = data.configs[t][v].transpose
			end
		else
			-- initialize
			for v = 1, n_voices do
				transposition[v] = 0.75 - v / 4
			end
		end
		saved_transpositions[t] = transposition
	end
	transposition_dirty = true

	-- restore/initialize mod loops
	saved_mod_loops = {}
	for l = 1, 16 do
		local loop = {
			values = {},
			voices = {}
		}
		if data.mod_loops ~= nil and data.mod_loops[l] ~= nil then
			-- restore
			local old_loop = data.mod_loops[l]
			if old_loop.values ~= nil then
				-- newest format
				for i, v in ipairs(old_loop.values) do
					loop.values[i] = v
				end
				for v = 1, n_voices do
					loop.voices[v] = {
						offset = old_loop.voices[v].offset,
						scramble = old_loop.voices[v].scramble or 0,
						direction = old_loop.voices[v].direction or 1
					}
				end
			else
				-- old format
				for i, v in ipairs(old_loop) do
					loop.values[i] = v
				end
				for v = 1, n_voices do
					loop.voices[v] = {
						offset = v * -4,
						scramble = data.configs[l][v].mod_scramble or 0,
						direction = data.configs[l][v].mod_direction or 1
					}
				end
			end
		else
			-- initialize
			for i = 1, 14 do
				saved_pitch_loops[l].values[i] = 0
			end
			for v = 1, 4 do
				saved_mod_loops[l].voices[v] = {
					offset = v * -4,
					scramble = 0,
					direction = 1
				}
			end
		end
		saved_mod_loops[l] = loop
	end
	mod_register.dirty = true
end

function init()

	add_params()
	params:set('hzlag', 0.02)
	params:set('cut', 8.32)
	params:set('fgain', 1.26)
	params:set('ampatk', 0.03)
	params:set('ampdec', 0.17)
	params:set('output_level', -48)
	
	crow.add = crow_setup -- when crow is connected
	crow_setup() -- calls params:bang()
	
	-- initialize grid controls
	grid_mode = grid_mode_pitch
	voice_selector:reset(true)
	memory_selector:reset(true)
	update_voice_order()

	pitch_poll = poll.set('pitch_in_l', update_freq)
	pitch_poll.time = 1 / 10 -- was 8, is 10 OK?
	
	-- TODO: if memory file is missing (like when freshly installed), copy defaults from the code directory?
	params:set('restore_memory')
	recall_mask()
	recall_transposition()
	recall_pitch_loop()
	recall_mod_loop()

	pitch_poll:start()
	g.key = grid_key
	m.event = midi_event
	
	update_voices()

	dirty = true
	redraw_metro:start()
end

function key(n, z)
	if n == 1 then
		key_shift = z == 1
		if not key_shift then
			blinkers.info:start()
		end
	elseif n == 2 then
		key_pitch = z == 1
	elseif n == 3 then
		key_mod = z == 1
	end
end

function params_multi_delta(param_format, selected, d)
	-- TODO: do I always want to retain the current relationship between the voices? in the case of
	-- scramble, I often want to zero it out for all voices at once, even if they currently have
	-- different values
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
			params:delta('write_probability', d)
		else
			if key_pitch and not key_mod then
				params:delta('pitch_loop_length', d)
			elseif key_mod and not key_pitch then
				params:delta('mod_loop_length', d)
			else
				params:delta('pitch_loop_length', d)
				params:delta('mod_loop_length', d)
			end
		end
	elseif n == 2 then
		-- shift voices
		-- TODO: somehow do this more slowly / make it less sensitive?
		for v = 1, n_voices do
			if voice_selector:is_selected(v) then
				local voice = voices[v]
				local mod_roll = voices[v].mod_roll
				if key_pitch == key_mod then -- neither or both held
					voice:shift(-d)
				elseif key_mod then
					voice:shift_mod(-d)
				elseif key_pitch then
					voice:shift_pitch(-d)
				end
				update_voice(v)
			end
		end
		transposition_dirty = true
		dirty = true
	elseif n == 3 then
		if key_shift then
			-- transpose voice(s)
			params_multi_delta('voice_%d_transpose', voice_selector.selected, d);
		else
			-- change voice randomness
			if key_pitch and not key_mod then
				params_multi_delta('voice_%d_pitch_scramble', voice_selector.selected, d)
			elseif key_mod and not key_pitch then
				params_multi_delta('voice_%d_mod_scramble', voice_selector.selected, d)
			else
				params_multi_delta('voice_%d_pitch_scramble', voice_selector.selected, d)
				params_multi_delta('voice_%d_mod_scramble', voice_selector.selected, d)
			end
		end
		update_voices()
	end
	dirty = true
end

function get_screen_offset_x(offset)
	return screen_note_width * (screen_note_center + offset)
end

function get_screen_note_y(value)
	if value == nil then
		return -1
	end
	return util.round(32 + (view_octave - value) * 12)
end

-- calculate coordinates for each visible note
function calculate_voice_path(v, level)
	local voice = voices[v]
	local path = voice:get_path(-screen_note_center, n_screen_notes - screen_note_center)
	screen_notes[v] = {}
	for n = 1, n_screen_notes do
		local note = {}
		note.x = (n - 1) * screen_note_width
		note.y = get_screen_note_y(scale:snap(path[n].pitch))
		note.z = path[n].mod
		note.pitch_pos = path[n].pitch_pos
		note.level = level
		for w = 1, n_recent_writes do
			local write = recent_writes[w]
			if write ~= nil and write.level > 0 then
				-- TODO: what about mod writes?
				if pitch_register:clamp_loop_pos(note.pitch_pos) == pitch_register:clamp_loop_pos(write.pitch_pos) then
					note.level = math.max(note.level, write.level)
				end
			end
		end
		screen_notes[v][n] = note
	end
end

function draw_voice_path(v, level)
	local voice = voices[v]

	calculate_voice_path(v, level)

	-- draw background/outline
	screen.line_cap('square')
	screen.line_width(3)
	screen.level(0)
	for n = 1, n_screen_notes do
		local note = screen_notes[v][n]
		local x = note.x + 0.5
		local y = note.y + 0.5
		local z = voice.active and note.z or 0
		local prev_note = screen_notes[v][n - 1] or note
		local prev_z = voice.active and prev_note.z or 0
		-- draw connector, if this note and the previous note are active
		if prev_z > 0 and z > 0 then
			screen.line(x, y)
		else
			screen.move(x, y)
		end
		-- draw this note, if active; draw all notes for selected voices
		if z > 0 or voice_selector:is_selected(v) then
			screen.line(x + screen_note_width, y)
			screen.stroke()
			screen.move(x + screen_note_width, y)
		end
	end
	screen.stroke()
	screen.line_cap('butt')

	-- draw foreground/path
	screen.line_width(1)
	for n = 1, n_screen_notes do
		local note = screen_notes[v][n]
		local x = note.x
		local y = note.y + 0.5
		local z = voice.active and note.z or 0
		local level = note.level
		local prev_note = screen_notes[v][n - 1] or note
		local prev_x = prev_note.x
		local prev_y = prev_note.y + 0.5
		local prev_z = voice.active and prev_note.z or 0
		local prev_level = prev_note.level
		-- draw connector
		if prev_z > 0 and z > 0 then
			local connector_level = math.min(level, prev_level) + math.floor(math.abs(level - prev_level) / 4)
			local min_y = math.min(prev_y, y)
			local max_y = math.max(prev_y, y)
			screen.move(x + 0.5, math.min(max_y, min_y + 0.5))
			screen.line(x + 0.5, math.max(min_y, max_y - 0.5))
			screen.level(connector_level)
			screen.stroke()
		else
			screen.move(x + 0.5, y)
		end
		-- draw this note, including dotted lines for inactive notes in selected voices
		if z > 0 then
			-- solid line for active notes
			screen.move(x, y)
			screen.line(x + screen_note_width + 1, y)
			screen.level(level)
			screen.stroke()
		elseif voice_selector:is_selected(v) then
			-- dotted line for inactive notes
			if prev_y ~= y then
				-- no need to re-draw this pixel if it's already been drawn as part of the previous note
				-- (possibly brighter, if prev note was active)
				screen.pixel(x, y)
			end
			screen.pixel(x + 2, y)
			screen.pixel(x + 4, y)
			screen.level(math.ceil(level / 3))
			screen.fill(0)
		end
	end
	screen.stroke()
end

function redraw()
	screen.clear()
	screen.stroke()
	screen.line_width(1)
	screen.font_face(2)
	screen.font_size(8)
	screen.line_cap('butt')

	-- draw paths
	for i, v in ipairs(voice_draw_order) do
		local level = voices[v].active and 1 or 0
		if v == top_voice_index then
			level = 15
		elseif voice_selector:is_selected(v) then
			level = 4
		end
		if level > 0 then
			draw_voice_path(v, level)
		end
	end

	-- draw play head indicator, which will be interrupted by active notes but not by inactive ones
	local output_x = get_screen_offset_x(-1) + 3
	screen.move(output_x, 0)
	screen.line(output_x, 64)
	screen.level(1)
	screen.stroke()

	-- highlight current notes after drawing all snakes
	for i, v in ipairs(voice_draw_order) do
		if voices[v].active then
			local note = screen_notes[v][screen_note_center]
			if note.z > 0 then
				screen.move(note.x + 2.5, note.y - 1)
				screen.line(note.x + 2.5, note.y + 2)
				screen.level(0)
				screen.stroke()
				screen.pixel(note.x + 2, note.y)
				screen.level(15)
				screen.fill()
			end
		end
	end

	-- fade write indicators
	for w = 1, n_recent_writes do
		local write = recent_writes[w]
		if write ~= nil and write.level > 0 then
			write.level = math.floor(write.level * 0.7)
		end
	end

	if key_shift or blinkers.info.on then
		screen.rect(0, 0, 26, 64)
		screen.level(0)
		screen.fill()
		screen.move(24.5, 0)
		screen.line(24.5, 64)
		screen.level(4)
		screen.stroke()

		screen.level(15)

		screen.move(0, 7)
		screen.text(string.format('P: %d%%', util.round(write_probability)))

		screen.move(0, 16)
		screen.text(string.format('Lp: %d', pitch_register.length))

		screen.move(0, 25)
		screen.text(string.format('Lm: %d', mod_register.length))

		screen.move(0, 34)
		screen.text(string.format('O: %d', top_voice.pitch_tap:get_offset()))

		screen.move(0, 43)
		screen.text(string.format('T: %.2f', top_voice.next_transpose))

		screen.move(0, 52)
		screen.text(string.format('S: %.1f', top_voice.pitch_tap.scramble))

		screen.level(top_voice.pitch_tap.direction == -1 and 15 or 2)
		screen.move(0, 61)
		screen.text('Ret.')
	end

	-- DEBUG: draw minibuffer, loop region, head
	--[[
	screen.move(0, 1)
	screen.line_rel(pitch_register.buffer_size, 0)
	screen.level(1)
	screen.stroke()
	for offset = 1, pitch_register.length do
		local pos = pitch_register:clamp_buffer_pos(pitch_register:get_loop_offset_pos(offset))
		screen.pixel(pos - 1, 0)
		screen.level(7)
		for v = 1, n_voices do
			if voice_selector:is_selected(v) and pos == pitch_register:clamp_buffer_pos(pitch_register:clamp_loop_pos(voices[v].pitch_tap:get_pos(0))) then
				screen.level(15)
			end
		end
		screen.fill()
	end
	--]]

	screen.update()
end

function cleanup()
	redraw_metro:stop()
	beatclock:stop()
	if pitch_poll ~= nil then
		pitch_poll:stop()
	end
	for i, blinker in ipairs(blinkers) do
		blinker:stop()
	end
end
