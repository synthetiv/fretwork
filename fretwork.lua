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
PitchMemory = include 'lib/memory_pitch'
MaskMemory = include 'lib/memory_mask'
TranspositionMemory = include 'lib/memory_transposition'
ModMemory = include 'lib/memory_mod'

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
scale = Scale.new(et12, 12)

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

n_voices = 4
voices = {}
voice_draw_order = { 4, 3, 2, 1 }
top_voice_index = 1
for v = 1, n_voices do
	local voice = ShiftRegisterVoice.new(v * -3, pitch_register, scale, v * -4, mod_register)
	voices[v] = voice
end
top_voice = voices[top_voice_index]

n_recent_voice_notes = 4
recent_voice_notes = {}
for v = 1, n_voices do
	recent_voice_notes[v] = {
		last = n_recent_voice_notes
	}
	for n = 1, n_recent_voice_notes do
		recent_voice_notes[v][n] = {
			pitch_id = 0,
			active = false,
			onset_level = 0,
			release_level = 0
		}
	end
end

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
	edit_alt = false,
	edit_tap = false,
	edit_fine = false
}

absolute_pitch_levels = {} -- used by pitch + mask keyboards
relative_pitch_levels = {} -- used by transpose keyboard
for n = 1, scale.n_values do
	absolute_pitch_levels[n] = 0
	relative_pitch_levels[n] = 0
end

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
screen_notes = {}
-- initialize these so every redraw doesn't create a zillion new tables, triggering GC
for v = 1, n_voices do
	voices[v]:initialize_path(n_screen_notes)
	screen_notes[v] = {}
	for n = 1, n_screen_notes do
		screen_notes[v][n] = {
			x = 0,
			y = 0,
			gate = 0,
			pitch_pos = 0,
			mod_pos = 0,
			level = 0
		}
	end
end

n_recent_writes = 8
write_type_pitch = 1
write_type_mod = 2
recent_writes = {
	last = n_recent_writes
}
for w = 1, n_recent_writes do
	recent_writes[w] = {
		type = 0,
		level = 0,
		pos = 0,
	}
end

n_edit_taps = 2
edit_tap_pitch = 1
edit_tap_mod = 2
edit_tap = edit_tap_pitch

n_edit_fields = 6
edit_field_direction = 1
edit_field_scramble = 2
edit_field_offset = 3
edit_field_noise = 4
edit_field_bias = 5
edit_field_length = 6
edit_field = edit_field_offset

blink_slow = false
framerate = 1 / 15
blinkers = {
	info = Blinker.new(6),
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

		-- fade recent voice notes
		for v = 1, n_voices do
			for n = 1, n_recent_voice_notes do
				local note = recent_voice_notes[v][n]
				if note.onset_level > 0 then
					note.onset_level = note.onset_level - 1
					dirty = true
				end
				if not note.active then
					if note.release_level > 0.06 then -- < 1/15
						note.release_level = note.release_level * 0.4
						dirty = true
					elseif note.release_level > 0 then
						note.release_level = 0
						dirty = true
					end
				end
			end
		end

		-- fade write indicators
		for w = 1, n_recent_writes do
			local write = recent_writes[w]
			if write.level > 0 then
				write.level = math.floor(write.level * 0.7)
				dirty = true
			end
		end
	end
}

memory_selector = MultiSelect.new(1, 2, 4, 1)
memory_pitch_loop = 1
memory_mask = 2
memory_transposition = 3
memory_mod_loop = 4
memory = {
	pitch = PitchMemory.new(),
	mask = MaskMemory.new(),
	transposition = TranspositionMemory.new(),
	mod = ModMemory.new()
}

function quantization_off()
	-- disable quantization if ctrl is held/locked or clock is paused
	return (held_keys.ctrl ~= held_keys.ctrl_lock) == clock_enable
end

function flash_note(v, active)
	local voice = voices[v]
	local pitch_tap = voices[v].pitch_tap
	local recent_notes = recent_voice_notes[v]
	local recent_note = recent_notes[recent_notes.last]
	-- stop the previous note
	recent_note.active = false
	-- update the new one
	recent_notes.last = recent_notes.last % n_recent_voice_notes + 1
	recent_note = recent_notes[recent_notes.last]
	-- set absolute pitch data
	recent_note.pitch_id = voice.pitch_id
	-- set relative pitch data
	recent_note.bias_pitch_id = scale:get_nearest_pitch_id(pitch_tap.bias)
	recent_note.noisy_bias_pitch_id = scale:get_nearest_pitch_id(pitch_tap.bias + pitch_tap.noise_values:get(0) * pitch_tap.noise)
	-- set level
	if active then
		-- real, active note
		recent_note.active = true
		recent_note.onset_level = 2
		recent_note.release_level = 1
	else
		-- "ghost" note that just flashes once
		recent_note.active = false
		recent_note.onset_level = 2
		recent_note.release_level = 0
	end
	dirty = true
end

function dim_note(v)
	local recent_notes = recent_voice_notes[v]
	local recent_note = recent_notes[recent_notes.last]
	recent_note.active = false
	dirty = true
end

function update_voice(v)
	local voice = voices[v]
	local prev_gate = voice.gate
	local prev_active = voice.active
	local prev_pitch_id = voice.pitch_id
	voice:update_values()
	if voice.active and voice.gate then
		engine.start(v - 1, musicutil.note_num_to_freq(60 + voice.pitch * 12))
		-- crow.output[v].volts = voice.value
		if not prev_gate or not prev_active or prev_pitch_id ~= voice.pitch_id then
			flash_note(v, true)
		end
	else
		engine.stop(v - 1)
		if voice.gate and voice_selector:is_selected(v) then
			-- if gate is active but voice is muted, flash a ghost note
			flash_note(v, false)
		else
			dim_note(v)
		end
	end
	voice:update_path(-screen_note_center, n_screen_notes - screen_note_center)
	calculate_voice_path(v)
end

function update_voices()
	for v = 1, n_voices do
		update_voice(v)
	end
end

function get_write_pitch()
	-- TODO: watch debug output using pitch + crow sources to make sure they're working
	if (pitch_keyboard_played or pitch_keyboard.n_held_keys > 0) then
		pitch_keyboard_played = false
		-- print(string.format('writing grid pitch (source = %d)', source))
		return pitch_keyboard:get_last_value()
	elseif source == source_pitch then
		-- print(string.format('writing audio pitch (source = %d)', source))
		return pitch_in_value
	elseif source == source_crow then
		-- print(string.format('writing crow pitch (source = %d)', source))
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

function flash_write(write_type, pos)
	recent_writes.last = recent_writes.last % n_recent_writes + 1
	local write = recent_writes[recent_writes.last]
	write.type = write_type
	write.pos = pos
	write.level = 15
	dirty = true
end

function write(pitch)
	for v = 1, n_voices do
		if voice_selector:is_selected(v) then
			local voice = voices[v]
			voice:set_pitch(0, pitch)
			flash_write(write_type_pitch, voice.pitch_tap:get_pos(0))
			update_voice(v)
		end
	end
	blinkers.record:start()
end

function shift(d)
	pitch_register:shift(d)
	mod_register:shift(d)
	x0x_roll:shift(-d)
	for v = 1, n_voices do
		voices[v].pitch_tap:shift(d)
		voices[v].mod_tap:shift(d)
	end
	pitch_register:sync_to(top_voice.pitch_tap)
	mod_register:sync_to(top_voice.mod_tap)
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

-- DEBUG: print roughly when garbage collection starts and how much memory has been used
mem = 0
mem_after_gc = 0
ticks_since_gc = 0
function print_memory()
	local mem_since_gc = mem - mem_after_gc
	print('memory since gc', mem_since_gc)
	print('average memory per second', mem_since_gc / ticks_since_gc)
end
memory_metro = metro.init{
	time = 1,
	event = function()
		local new_mem = collectgarbage('count') * 1024
		if new_mem < mem then
			if ticks_since_gc > 1 then
				print('-- gc --', ticks_since_gc)
				print_memory()
			end
			ticks_since_gc = 0
			mem_after_gc = new_mem
		else
			ticks_since_gc = ticks_since_gc + 1
		end
		mem = new_mem
	end
}
--]]

function tick()
	if not clock_enable then
		return
	end
	advance()
	blinkers.play:start()
end

function update_voice_order()
	-- TODO: it would be nice to avoid creating new tables here, but none have > 4 values, so... eh
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
	pitch_register:sync_to(top_voice.pitch_tap)
	mod_register:sync_to(top_voice.mod_tap)
	voice_draw_order = new_draw_order
end

function led_blend(a, b)
	a = 1 - a / 15
	b = 1 - b / 15
	return (1 - (a * b)) * 15
end

function grid_redraw()

	-- mode buttons
	grid_mode_selector:draw(g, 7, 2)

	-- recall mode buttons
	memory_selector:draw(g, 7, 2)

	-- recall buttons, for all selected memory types
	local pitch_loop_selector = memory.pitch.selector
	local mask_selector = memory.mask.selector
	local transposition_selector = memory.transposition.selector
	local mod_loop_selector = memory.mod.selector
	for x = 1, 4 do
		for y = 3, 6 do
			local level = 2
			if memory_selector:is_selected(memory_pitch_loop) and pitch_loop_selector:is_selected(pitch_loop_selector:get_key_option(x, y)) then
				level = math.max(level, (memory.pitch.dirty or pitch_register.dirty) and blink_slow and 8 or 7)
			end
			if memory_selector:is_selected(memory_mask) and mask_selector:is_selected(mask_selector:get_key_option(x, y)) then
				level = math.max(level, memory.mask.dirty and blink_slow and 8 or 7)
			end
			if memory_selector:is_selected(memory_transposition) and transposition_selector:is_selected(transposition_selector:get_key_option(x, y)) then
				level = math.max(level, memory.transposition.dirty and blink_slow and 8 or 7)
			end
			if memory_selector:is_selected(memory_mod_loop) and mod_loop_selector:is_selected(mod_loop_selector:get_key_option(x, y)) then
				level = math.max(level, (memory.mod.dirty or mod_register.dirty) and blink_slow and 8 or 7)
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
		local voice_index = voice_selector:get_key_option(voice_selector.x, y)
		local voice = voices[voice_index]
		local notes = recent_voice_notes[voice_index]
		local last_note = notes[notes.last]
		local level = last_note.release_level * 3
		if voice.next_active then
			level = level + last_note.onset_level
		end
		if voice_index == top_voice_index then
			level = level + 11
		elseif voice_selector:is_selected(voice_index) then
			level = level + 6
		else
			level = level + 2
		end
		g:led(voice_selector.x, y, math.floor(math.min(15, level)))
	end

	-- octave switches
	g:led(3, 8, 2 - math.min(view_octave, 0))
	g:led(4, 8, 2 + math.max(view_octave, 0))

	if active_keyboard ~= nil then
		-- calculate levels for keyboards
		local low_pitch_id = active_keyboard:get_key_pitch_id(pitch_keyboard.x, pitch_keyboard.y2)
		local high_pitch_id = active_keyboard:get_key_pitch_id(pitch_keyboard.x2, pitch_keyboard.y)
		for n = low_pitch_id, high_pitch_id do
			absolute_pitch_levels[n] = 0
			relative_pitch_levels[n] = 0
		end
		for v = 1, n_voices do
			local voice = voices[v]
			local recent_notes = recent_voice_notes[v]
			local voice_level = 3
			if v == top_voice_index then
				voice_level = 13
			elseif voice_selector:is_selected(v) then
				voice_level = 5
			end
			for n = 1, n_recent_voice_notes do
				local note = recent_notes[n]
				local pitch_id = note.pitch_id
				local bias_pitch_id = note.bias_pitch_id
				local noisy_bias_pitch_id = note.noisy_bias_pitch_id
				local release_level = note.release_level * voice_level
				local level = release_level + note.onset_level
				if release_level > 0 or note.onset_level > 0 then
					absolute_pitch_levels[pitch_id] = led_blend(absolute_pitch_levels[pitch_id], level)
					relative_pitch_levels[bias_pitch_id] = led_blend(relative_pitch_levels[bias_pitch_id], level)
					relative_pitch_levels[noisy_bias_pitch_id] = led_blend(relative_pitch_levels[noisy_bias_pitch_id], release_level / 2 + note.onset_level)
				end
			end
		end
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
	-- highlight current note (and return, because nothing can be brighter)
	if self.n_held_keys > 0 and self:is_key_last(x, y) then
		return 15
	end
	-- highlight voice notes
	local level = absolute_pitch_levels[n]
	-- highlight mask
	if self.scale:mask_contains(n) then
		level = led_blend(level, 3.5)
	end
	return math.min(15, math.floor(level))
end

function mask_keyboard:get_key_level(x, y, n)
	-- highlight voice notes
	local level = absolute_pitch_levels[n]
	-- highlight mask
	local in_mask = self.scale:mask_contains(n)
	local in_next_mask = self.scale:next_mask_contains(n)
	if in_mask and in_next_mask then
		level = led_blend(level, 4)
	elseif in_next_mask then
		level = led_blend(level, 2)
	elseif in_mask then
		level = led_blend(level, 1)
	end
	-- highlight white keys
	if self:is_white_key(n) then
		level = led_blend(level, 2)
	end
	return math.min(15, math.floor(level))
end

function transpose_keyboard:get_key_level(x, y, n)
	local level = relative_pitch_levels[n]
	-- highlight transposition settings
	-- TODO: this is mostly taken care of by flashing notes now, but it would be nice to show 'next's
	-- highlight octaves
	if (n - scale.center_pitch_id) % scale.length == 0 then
		level = math.max(level, 2)
	end
	return math.min(15, math.floor(level))
end

function x0x_roll:get_key_level(x, y, v, offset, gate)
	local head = offset == 0
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
	memory.mask.dirty = true
	if quantization_off() then
		scale:apply_edits()
		update_voices()
	end
end

function pitch_keyboard:key(x, y, z)
	if held_keys.shift and z == 1 then
		toggle_mask_class(self:get_key_pitch_id(x, y))
		return
	end
	local previous_note = self:get_last_pitch_id()
	self:note(x, y, z)
	if self.n_held_keys > 0 and (z == 1 or previous_note ~= self:get_last_pitch_id()) then
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
	if self.n_held_keys < 1 then
		return
	end
	local delta = self:get_last_value() - top_voice.pitch_tap.next_bias
	if held_keys.shift then
		-- adjust noise (random transposition)
		for v = 1, n_voices do
			if voice_selector:is_selected(v) then
				params:set(string.format('voice_%d_pitch_noise', v), math.abs(delta))
			end
		end
	else
		-- adjust bias (fixed transposition)
		for v = 1, n_voices do
			if voice_selector:is_selected(v) then
				params:set(string.format('voice_%d_transpose', v), (voices[v].pitch_tap.next_bias + delta) * 12)
			end
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
			memory.mask.selector:key(x, y, z)
		end
		if memory_selector:is_selected(memory_transposition) then
			memory.transposition.selector:key(x, y, z)
		end
		if memory_selector:is_selected(memory_pitch_loop) then
			memory.pitch.selector:key(x, y, z)
		end
		if memory_selector:is_selected(memory_mod_loop) then
			memory.mod.selector:key(x, y, z)
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
				voice.pitch_tap:shift(1) -- TODO: shift SR if appropriate
				voice.mod_tap:shift(1)
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
		params:add_group(string.format('voice %d', v), 11)
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
			controlspec = controlspec.new(-48, 48, 'lin', 1 / 10, 0, 'st'),
			action = function(value)
				voice.pitch_tap.next_bias = value / 12
				memory.transposition.dirty = true
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_pitch_scramble', v),
			name = string.format('voice %d pitch scramble', v),
			controlspec = controlspec.new(0, 16, 'lin', 0.1, 0),
			action = function(value)
				voice.pitch_tap.scramble = value
				dirty = true
				memory.pitch.dirty = true
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_pitch_noise', v),
			name = string.format('voice %d pitch noise', v),
			controlspec = controlspec.new(0, 16, 'lin', 1 / 120, 0),
			action = function(value)
				voice.pitch_tap.noise = value
				dirty = true
				memory.pitch.dirty = true
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
				if top_voice_index == v then
					pitch_register:sync_to(voice.pitch_tap)
				end
				dirty = true
				memory.transposition.dirty = true
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_mod_bias', v),
			name = string.format('voice %d mod bias', v),
			controlspec = controlspec.new(0, 16, 'lin', 0.1, 0),
			action = function(value)
				voice.mod_tap.next_bias = value
				dirty = true
				memory.mod.dirty = true
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_mod_scramble', v),
			name = string.format('voice %d mod scramble', v),
			controlspec = controlspec.new(0, 16, 'lin', 0.1, 0),
			action = function(value)
				voice.mod_tap.scramble = value
				dirty = true
				memory.mod.dirty = true
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_mod_noise', v),
			name = string.format('voice %d mod noise', v),
			controlspec = controlspec.new(0, 16, 'lin', 0.2, 0),
			action = function(value)
				voice.mod_tap.noise = value
				dirty = true
				memory.mod.dirty = true
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
				if top_voice_index == v then
					mod_register:sync_to(voice.mod_tap)
				end
				dirty = true
				memory.transposition.dirty = true
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
			if quantization_off() then
				scale:apply_edits()
				update_voices()
			end
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
					load_memory(data)
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
			data.pitch_loops = memory.pitch.slots
			data.masks = memory.mask.slots
			data.transpositions = memory.transposition.slots
			data.mod_loops = memory.mod.slots
			tab.save(data, data_file)
		end
	}
end

function load_memory(data)
	for s = 1, 16 do
		if data.pitch_loops ~= nil then
			memory.pitch:set(memory.pitch.slots[s], data.pitch_loops[s])
		end
		if data.masks ~= nil then
			memory.mask:set(memory.mask.slots[s], data.masks[s])
		end
		if data.transpositions ~= nil then
			memory.transposition:set(memory.transposition.slots[s], data.transpositions[s])
		end
		if data.mod_loops ~= nil then
			memory.mod:set(memory.mod.slots[s], data.mod_loops[s])
		end
	end
	memory.pitch.dirty = true
	memory.mask.dirty = true
	memory.transposition.dirty = true
	memory.mod.dirty = true
end

function init()

	-- DEBUG
	memory_metro:start()

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

	pitch_poll = poll.set('pitch_in_l', update_freq)
	pitch_poll.time = 1 / 10 -- was 8, is 10 OK?
	
	-- TODO: if memory file is missing (like when freshly installed), copy defaults from the code directory?
	params:set('restore_memory')
	memory.pitch:recall_slot(1)
	memory.mask:recall_slot(1)
	memory.transposition:recall_slot(1)
	memory.mod:recall_slot(1)

	pitch_poll:start()
	g.key = grid_key
	m.event = midi_event
	
	-- match encoder sensitivity used in norns menus
	norns.enc.accel(1, false)
	norns.enc.sens(1, 8)
	norns.enc.accel(2, false)
	norns.enc.sens(2, 4)
	norns.enc.accel(2, true)
	norns.enc.sens(3, 2)
	-- encoder 3's sensitivity changes based on selected field; update it to match initial edit field
	enc(2, 0)

	update_voices()

	dirty = true
	redraw_metro:start()
end

function key(n, z)
	if n == 1 then
		-- TODO: what should this actually do?
		held_keys.edit_alt = z == 1
	elseif n == 2 then
		-- press to switch from editing pitch to mod or vice versa; hold to edit both
		held_keys.edit_tap = z == 1
		if z == 1 then
			edit_tap = edit_tap % n_edit_taps + 1
		end
	elseif n == 3 then
		-- enable fine control
		held_keys.edit_fine = z == 1
	end
	blinkers.info:start()
	dirty = true
end

-- TODO: still left to control:
-- internal clock tempo?
-- clock enable?
-- write probability
-- record enable
function enc(n, d)
	if n == 1 then
		-- select voice
		local voice_index = util.clamp(top_voice_index + d, 1, n_voices)
		for v = 1, n_voices do
			voice_selector.selected[v] = v == voice_index
		end
		update_voice_order()
	elseif n == 2 then
		-- select field
		edit_field = util.clamp(edit_field + d, 1, n_edit_fields)
		-- disable acceleration when editing offsets
		if edit_field == edit_field_offset then
			norns.enc.accel(3, false)
		else
			norns.enc.accel(3, true)
		end
	elseif n == 3 then
		-- offset can only be changed by integer values, but for other fields, allow fine adjustment
		if edit_field ~= edit_field_offset and held_keys.edit_fine then
			d = d / 20
		end
		if edit_field == edit_field_direction then
			if held_keys.edit_tap or edit_tap == edit_tap_pitch then
				-- set pitch direction
				for v = 1, n_voices do
					if voice_selector:is_selected(v) then
						params:delta(string.format('voice_%d_pitch_direction', v), -d)
					end
				end
			end
			if held_keys.edit_tap or edit_tap == edit_tap_mod then
				-- set mod direction
				for v = 1, n_voices do
					if voice_selector:is_selected(v) then
						params:delta(string.format('voice_%d_mod_direction', v), -d)
					end
				end
			end
		elseif edit_field == edit_field_scramble then
			if held_keys.edit_tap or edit_tap == edit_tap_pitch then
				-- set pitch scramble
				for v = 1, n_voices do
					if voice_selector:is_selected(v) then
						params:delta(string.format('voice_%d_pitch_scramble', v), d)
					end
				end
			end
			if held_keys.edit_tap or edit_tap == edit_tap_mod then
				-- set mod scramble
				for v = 1, n_voices do
					if voice_selector:is_selected(v) then
						params:delta(string.format('voice_%d_mod_scramble', v), d)
					end
				end
			end
		elseif edit_field == edit_field_offset then
			if held_keys.edit_tap or edit_tap == edit_tap_pitch then
				-- shift pitch tap(s)
				for v = 1, n_voices do
					if voice_selector:is_selected(v) then
						local voice = voices[v]
						voice.pitch_tap:shift(-d)
					end
				end
				pitch_register:shift(-d)
				memory.pitch.dirty = true
			end
			if held_keys.edit_tap or edit_tap == edit_tap_mod then
				-- shift mod tap(s)
				for v = 1, n_voices do
					if voice_selector:is_selected(v) then
						local voice = voices[v]
						voice.mod_tap:shift(-d)
					end
				end
				mod_register:shift(-d)
				memory.mod.dirty = true
			end
		elseif edit_field == edit_field_noise then
			if held_keys.edit_tap or edit_tap == edit_tap_pitch then
				-- set pitch noise
				for v = 1, n_voices do
					if voice_selector:is_selected(v) then
						params:delta(string.format('voice_%d_pitch_noise', v), d)
					end
				end
			end
			if held_keys.edit_tap or edit_tap == edit_tap_mod then
				-- set mod noise
				for v = 1, n_voices do
					if voice_selector:is_selected(v) then
						params:delta(string.format('voice_%d_mod_noise', v), d)
					end
				end
			end
		elseif edit_field == edit_field_bias then
			if held_keys.edit_tap or edit_tap == edit_tap_pitch then
				-- transpose voice(s)
				-- find highest value (or lowest, if lowering)
				local sign = d < 0 and -1 or 1
				local abs_d = d * sign
				local max_transpose = -4 -- lowest possible transpose setting
				for v = 1, n_voices do
					if voice_selector:is_selected(v) then
						max_transpose = math.max(voices[v].pitch_tap.bias * sign, max_transpose)
					end
				end
				-- if increasing/decreasing by d would exceed [-4, 4], reduce d
				if max_transpose + abs_d > 4 then
					d = (4 - max_transpose) * sign
				end
				-- transpose 'em
				for v = 1, n_voices do
					if voice_selector:is_selected(v) then
						params:delta(string.format('voice_%d_transpose', v), d)
					end
				end
			end
			if held_keys.edit_tap or edit_tap == edit_tap_mod then
				-- set mod bias
				for v = 1, n_voices do
					if voice_selector:is_selected(v) then
						params:delta(string.format('voice_%d_mod_bias', v), d)
					end
				end
			end
		elseif edit_field == edit_field_length then
			if held_keys.edit_tap or edit_tap == edit_tap_pitch then
				-- set pitch length
				params:delta('pitch_loop_length', d)
			end
			if held_keys.edit_tap or edit_tap == edit_tap_mod then
				-- set mod length
				params:delta('mod_loop_length', d)
			end
		end
		if quantization_off() then
			update_voices()
		end
	end
	blinkers.info:start()
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

-- calculate coordinates and levels for each visible note
function calculate_voice_path(v)
	local voice = voices[v]
	local notes = screen_notes[v]
	local path = voice.path
	for n = 1, n_screen_notes do
		local note = notes[n]
		local point = path[n]
		note.x = (n - 1) * screen_note_width
		note.y = get_screen_note_y(scale:snap(point.pitch))
		note.gate = point.gate
		note.pitch_pos = point.pitch_pos
		note.mod_pos = point.mod_pos
	end
end

function draw_voice_path(v, level)
	local voice = voices[v]
	local notes = screen_notes[v]

	for n = 1, n_screen_notes do
		local note = notes[n]
		local level = 0
		for w = 1, n_recent_writes do
			local write = recent_writes[w]
			if write.level > 0 then
				if write.type == write_type_pitch and note.pitch_pos == pitch_register:clamp_loop_pos(write.pos) then
					level = write.level
				end
				if write.type == write_type_mod and note.mod_pos == mod_register:clamp_loop_pos(write.pos) then
					level = math.max(level, write.level)
				end
			end
		end
		note.level = level
	end

	-- draw background/outline
	screen.line_cap('square')
	screen.line_width(3)
	screen.level(0)
	for n = 1, n_screen_notes do
		local note = notes[n]
		local x = note.x + 0.5
		local y = note.y + 0.5
		local gate = voice.active and note.gate
		local prev_note = notes[n - 1] or note
		local prev_gate = voice.active and prev_note.gate
		-- draw connector, if this note and the previous note are active
		if prev_gate and gate then
			screen.line(x, y)
		else
			screen.move(x, y)
		end
		-- draw this note, if active; draw all notes for selected voices
		if gate or voice_selector:is_selected(v) then
			screen.line(x + screen_note_width, y)
			screen.stroke()
			screen.move(x + screen_note_width, y)
		end
	end
	screen.line_cap('butt')

	-- draw foreground/path
	screen.line_width(1)
	for n = 1, n_screen_notes do
		local note = notes[n]
		local x = note.x
		local y = note.y + 0.5
		local gate = voice.active and note.gate
		local note_level = note.level
		local prev_note = notes[n - 1] or note
		local prev_x = prev_note.x
		local prev_y = prev_note.y + 0.5
		local prev_gate = voice.active and prev_note.gate
		local prev_level = prev_note.level
		-- draw connector
		if prev_gate and gate then
			-- TODO: this is a slow point, apparently
			local connector_level = math.max(note_level, prev_level) / 4
			local min_y = math.min(prev_y, y)
			local max_y = math.max(prev_y, y)
			screen.move(x + 0.5, math.min(max_y, min_y + 0.5))
			screen.line(x + 0.5, math.max(min_y, max_y - 0.5))
			screen.level(math.ceil(led_blend(level, connector_level)))
			screen.stroke()
		else
			screen.move(x + 0.5, y)
		end
		-- draw this note, including dotted lines for inactive notes in selected voices
		if gate then
			-- solid line for active notes
			screen.move(x, y)
			screen.line(x + screen_note_width + 1, y)
			screen.level(math.ceil(led_blend(level, note_level)))
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
			screen.level(math.ceil(led_blend(level, note_level) / 3))
			screen.fill(0)
		end
	end
end

function draw_tap_equation(y, label, tap, multiplier, editing)
	local highlight_direction = editing and edit_field == edit_field_direction
	local highlight_scramble = editing and edit_field == edit_field_scramble
	local highlight_offset = editing and edit_field == edit_field_offset
	local highlight_noise = editing and edit_field == edit_field_noise
	local highlight_bias = editing and edit_field == edit_field_bias
	local highlight_length = editing and edit_field == edit_field_length

	local direction = tap.direction
	local scramble = tap.scramble * direction
	local offset = tap:get_offset()
	local noise = tap.noise * direction * multiplier
	local bias = tap.next_bias * multiplier
	local length = tap.shift_register.length

	screen.move(8, y)

	screen.level(3)
	screen.text(label .. '[')

	screen.level(highlight_direction and 15 or 3)
	if direction < 0 then
		screen.text('-t')
	else
		screen.text('t')
	end

	screen.level(highlight_scramble and 15 or 3)
	if highlight_scramble or scramble ~= 0 then
		screen.text(string.format('+%.1fk', scramble))
	end

	-- TODO: this way of notating offset no longer makes much sense -- it will always be 0 or length-1
	-- for the top voice. what should we do instead?
	screen.level(highlight_offset and 15 or 3)
	screen.text(string.format('%+d', offset))

	screen.level(3)
	screen.text(']')

	screen.level(highlight_noise and 15 or 3)
	if highlight_noise or noise ~= 0 then
		screen.text(string.format('+%.1fz', noise))
	end

	screen.level(highlight_bias and 15 or 3)
	if highlight_bias or bias ~= 0 then
		screen.text(string.format('%+.1f', bias))
	end

	screen.move(110, y)
	screen.level(3)
	screen.text('[')

	screen.level(highlight_length and 15 or 3)
	screen.text(string.format('%d', length))

	screen.level(3)
	screen.text(']')
end

function redraw()
	screen.clear()
	screen.stroke()
	screen.line_width(1)
	screen.font_face(1)
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
			if note.gate then
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

	if held_keys.edit_alt or blinkers.info.on then

		screen.rect(0, 47, 128, 17)
		screen.level(0)
		screen.fill()

		-- TODO: move this
		-- screen.move(0, 7)
		-- screen.text(string.format('P: %d%%', util.round(write_probability)))

		screen.move(0, 54)
		screen.level(3)
		screen.text(string.format('%d.', top_voice_index))

		draw_tap_equation(54, 'p', top_voice.pitch_tap, 12, held_keys.edit_tap or edit_tap == edit_tap_pitch)

		draw_tap_equation(62, 'g', top_voice.mod_tap, 1, held_keys.edit_tap or edit_tap == edit_tap_mod)

	end
	--]]

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
	if memory_metro ~= nil then
		memory_metro:stop()
	end
end
