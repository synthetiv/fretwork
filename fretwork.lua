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

crow_slew_shapes = {
	'linear',
	'sine',
	'logarithmic',
	'exponential',
	'now',
	'wait',
	'over',
	'under',
	'rebound'
}

-- calculate pitch class values
et12 = {} -- 12TET
for p = 1, 12 do 
	et12[p] = p / 12
end
scale = Scale.new(et12, 12)

pitch_registers = {}
mod_registers = {}
n_registers = 4
for r = 1, n_registers do
	pitch_registers[r] = ShiftRegister.new(16)
	mod_registers[r] = ShiftRegister.new(16)
end

write_enable = true

clock_running = false
ticks_per_beat = 8
clock_coro = nil
clock.transport.start = function()
	clock_running = true
	if clock_coro ~= nil then
		clock.cancel(clock_coro) -- don't go into double time if clock 'reset' param is triggered
	end
	clock_coro = clock.run(clock_tick)
end
clock.transport.stop = function()
	clock_running = false
	clock.cancel(clock_coro)
end

output_mode_crow_2 = 1
output_mode_crow_4 = 2
output_mode_polysub = 3
output_mode_names = {
	'crow (2x cv/gate)',
	'crow (4x cv)',
	'polysub'
}
output_mode = output_mode_crow_2

n_voices = 4
voices = {}
top_voice_index = 1
for v = 1, n_voices do
	local voice = ShiftRegisterVoice.new(v * -3, pitch_registers[1], scale, v * -4, mod_registers[1])
	voice.pitch_tap.on_write = function(pos)
		flash_write(write_type_pitch, pos)
	end
	voice.mod_tap.on_write = function(pos)
		flash_write(write_type_mod, pos)
	end
	voice.on_shift = function()
		blinkers.play:start()
	end
	voice.note_on = function(pitch)
		note_on(v, pitch)
	end
	voice.note_off = function()
		note_off(v)
	end
	voices[v] = voice
end
top_voice = voices[top_voice_index]

flash_stage_sustain = 1
flash_stage_ghost = 2
flash_stage_release = 3
n_recent_voice_notes = 4
recent_voice_notes = {}
for v = 1, n_voices do
	recent_voice_notes[v] = {
		last = n_recent_voice_notes
	}
	for n = 1, n_recent_voice_notes do
		recent_voice_notes[v][n] = {
			pitch_id = 0,
			stage = flash_stage_release,
			onset_level = 0,
			release_level = 0
		}
	end
end

rate_divisions = {}
slowest_rate = 13
for r = 1, slowest_rate do
	if r == 1 then
		rate_divisions[r] = '-1'
		rate_divisions[slowest_rate * 2 - r] = '1'
	elseif r == slowest_rate then
		rate_divisions[r] = '0'
	else
		rate_divisions[r] = '-1/' .. r
		rate_divisions[slowest_rate * 2 - r] = '1/' .. r
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
	edit_dec = false,
	edit_inc = false,
	edit_fine = false
}

absolute_pitch_levels = {} -- used by pitch + mask keyboards
relative_pitch_levels = {} -- used by transpose keyboard
for n = 1, scale.n_values do
	absolute_pitch_levels[n] = 0
	relative_pitch_levels[n] = 0
end

view_octave = 0

pitch_keyboard = Keyboard.new(6, 1, 11, 8, scale)
mask_keyboard = Keyboard.new(6, 1, 11, 8, scale)
transpose_keyboard = Keyboard.new(6, 1, 11, 8, scale)
keyboards = { -- lookup array; indices match corresponding modes
	pitch_keyboard,
	mask_keyboard,
	transpose_keyboard
}
active_keyboard = pitch_keyboard

-- special stuff for transpose keyboard polyphony
transpose_keyboard.key_count = 0
transpose_keyboard.voice_usage = {}
for v = 1, n_voices do
	transpose_keyboard.voice_usage[v] = {
		last = 0,
		key_id = 0,
		free = true
	}
end

x0x_roll = X0XRoll.new(6, 1, 11, 8, n_voices, voices)

screen_note_width = 4
n_screen_notes = 128 / screen_note_width
screen_note_center = math.floor((n_screen_notes - 1) / 2 + 0.5)
-- initialize voice paths, which can persist between redraws
voice_paths = {}
for v = 1, n_voices do
	local voice_path = {}
	for n = 1, n_screen_notes do
		voice_path[n] = {
			pitch = 0,
			pitch_step = 0,
			pitch_pos = 0,
			mod = 0,
			mod_step = 0,
			mod_pos = 0,
			gate = false,
			connect = false,
			x = 0,
			x2 = 0,
			y = 0,
			y0 = 0,
			level = 0
		}
	end
	voice_path.length = 0
	voice_paths[v] = voice_path
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
edit_both_taps = true

n_edit_fields = 8
edit_field_multiply = 1
edit_field_time = 2
edit_field_rate = 3
edit_field_jitter = 4
edit_field_scramble = 5
edit_field_noise = 6
edit_field_bias = 7
edit_field_length = 8
edit_field = edit_field_time

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

		x0x_roll:smooth_hold_steps()

		if not blink_slow and tick % 8 > 3 then
			blink_slow = true
			dirty = true
		elseif blink_slow and tick % 8 <= 3 then
			blink_slow = false
			dirty = true
		end

		for v = 1, n_voices do
			-- calculate voice paths, if necessary
			if voices[v].path_dirty then
				calculate_voice_path(v)
			end
			-- fade recent voice notes
			for n = 1, n_recent_voice_notes do
				local note = recent_voice_notes[v][n]
				if note.onset_level > 0 then
					note.onset_level = note.onset_level - 1
					dirty = true
				end
				if note.stage == flash_stage_ghost then
					if note.release_level > 0.4 then -- 6/15
						note.release_level = note.release_level * 0.4
						dirty = true
					end
				elseif note.stage == flash_stage_release then
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

		if dirty then
			grid_redraw()
			redraw()
			dirty = false
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
	return (held_keys.ctrl ~= held_keys.ctrl_lock) == clock_running
end

function flash_note(v)
	local voice = voices[v]
	local recent_notes = recent_voice_notes[v]
	local recent_note = recent_notes[recent_notes.last]
	-- if gate is low and this voice isn't selected, just release the last note
	if not voice.gate and not voice_selector:is_selected(v) then
		recent_note.stage = flash_stage_release
		return
	end
	-- if gate is high or this voice is selected, check whether the pitch has changed
	if recent_note.pitch_id == voice.pitch_id and recent_note.bias_pitch_id == voice.bias_pitch_id and recent_note.noisy_bias_pitch_id == voice.noisy_bias_pitch_id then
		if voice.gate then
			-- if gate is high and was high before, stay in sustain stage
			if recent_note.stage == flash_stage_sustain then
				return
			end
		elseif voice_selector:is_selected(v) then
			-- if gate is low but the voice is selected, move to ghost stage (dim sustain)
			recent_note.stage = flash_stage_ghost
			return
		end
	end
	recent_note.stage = flash_stage_release
	-- update the new one
	recent_notes.last = recent_notes.last % n_recent_voice_notes + 1
	recent_note = recent_notes[recent_notes.last]
	-- set pitch data
	recent_note.pitch_id = voice.pitch_id
	recent_note.bias_pitch_id = voice.bias_pitch_id
	recent_note.noisy_bias_pitch_id = voice.noisy_bias_pitch_id
	-- set levels
	recent_note.stage = voice.gate and flash_stage_sustain or flash_stage_ghost
	recent_note.release_level = voice.gate and 1 or 0.4
	recent_note.onset_level = voice.gate and 2 or 0
	dirty = true
end

function note_on(v, pitch)
	if output_mode == output_mode_crow_4 then
		crow.output[v].volts = pitch
	elseif output_mode == output_mode_crow_2 then
		if v < 3 then
			crow.output[(v - 1) * 2 + 1].volts = pitch
			crow.output[(v - 1) * 2 + 2].volts = 5
		end
	elseif output_mode == output_mode_polysub then
		engine.start(v - 1, musicutil.note_num_to_freq(60 + pitch * 12))
	end
	flash_note(v)
end

function note_off(v)
	if output_mode == output_mode_crow_4 then
	elseif output_mode == output_mode_crow_2 then
		if v < 3 then
			crow.output[(v - 1) * 2 + 2].volts = 0
		end
	elseif output_mode == output_mode_polysub then
		engine.stop(v - 1)
	end
	flash_note(v)
end

function update_voices(force_pitch_update, force_mod_update)
	for v = 1, n_voices do
		voices[v]:update(force_pitch_update, force_mod_update)
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
			local tap = voices[v].pitch_tap
			tap.next_value = pitch
		end
	end
	if quantization_off() then
		for v = 1, n_voices do
			local voice = voices[v]
			voice.pitch_tap:apply_edits()
			voice:update(true)
		end
	end
	blinkers.record:start()
end

function shift(d)
	if write_enable and pitch_keyboard.n_held_keys > 0 then
		write(pitch_keyboard:get_last_value())
	end
	scale:apply_edits() -- TODO: maintain separate scales per voice, so changes can be quantized separately
	for v = 1, n_voices do
		local voice = voices[v]
		voice:shift(d)
	end
	-- silently update loop length params, as they may have changed after shift
	-- TODO: avoid doing this more than necessary
	for r = 1, n_registers do
		params:set(string.format('pitch_loop_%d_length', r), pitch_registers[r].loop_length, true)
		params:set(string.format('mod_loop_%d_length', r), mod_registers[r].loop_length, true)
	end
	dirty = true
end

function advance()
	shift(1)
end

function rewind()
	shift(-1)
end

function clock_tick()
	while true do
		clock.sync(1 / ticks_per_beat)
		advance()
	end
end

function update_top_voice()
	top_voice_index = voice_selector.selection_order[1]
	top_voice = voices[top_voice_index]
	top_voice.pitch_tap:sync()
	top_voice.mod_tap:sync()
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
				level = math.max(level, (memory.pitch.dirty or top_voice.pitch_tap.shift_register.dirty) and blink_slow and 8 or 7)
			end
			if memory_selector:is_selected(memory_mask) and mask_selector:is_selected(mask_selector:get_key_option(x, y)) then
				level = math.max(level, memory.mask.dirty and blink_slow and 8 or 7)
			end
			if memory_selector:is_selected(memory_transposition) and transposition_selector:is_selected(transposition_selector:get_key_option(x, y)) then
				level = math.max(level, memory.transposition.dirty and blink_slow and 8 or 7)
			end
			if memory_selector:is_selected(memory_mod_loop) and mod_loop_selector:is_selected(mod_loop_selector:get_key_option(x, y)) then
				level = math.max(level, (memory.mod.dirty or top_voice.mod_tap.shift_register.dirty) and blink_slow and 8 or 7)
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
			local onset_scale = 0.5
			if v == top_voice_index then
				voice_level = 13
				onset_scale = 1
			elseif voice_selector:is_selected(v) then
				voice_level = 6
			end
			for n = 1, n_recent_voice_notes do
				local note = recent_notes[n]
				local pitch_id = note.pitch_id
				local bias_pitch_id = note.bias_pitch_id
				local noisy_bias_pitch_id = note.noisy_bias_pitch_id
				local release_level = note.release_level * voice_level
				local onset_level = note.onset_level * onset_scale
				local level = release_level + onset_level
				if release_level > 0 or note.onset_level > 0 then
					absolute_pitch_levels[pitch_id] = led_blend(absolute_pitch_levels[pitch_id], level)
					if bias_pitch_id == noisy_bias_pitch_id then
						relative_pitch_levels[bias_pitch_id] = led_blend(relative_pitch_levels[bias_pitch_id], release_level * 1.25)
					else
						relative_pitch_levels[bias_pitch_id] = led_blend(relative_pitch_levels[bias_pitch_id], level)
						relative_pitch_levels[noisy_bias_pitch_id] = led_blend(relative_pitch_levels[noisy_bias_pitch_id], level * 0.75)
					end
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
	local play_button_level = blinkers.play.on and 4 or 3
	if clock_running then
		play_button_level = play_button_level + 4
	end
	g:led(3, 7, play_button_level)
	local record_button_level = 3
	if blinkers.record.on then
		record_button_level = 8
	elseif write_enable then
		record_button_level = 7
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
	return math.min(15, math.ceil(level))
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
	return math.min(15, math.ceil(level))
end

function transpose_keyboard:get_key_level(x, y, n)
	local level = relative_pitch_levels[n]
	-- TODO: do something to show the full noise range (not just the current noise value)
	-- TODO: show 'next's
	-- highlight octaves
	if (n - scale.center_pitch_id) % scale.length == 0 then
		level = math.max(level, 2)
	end
	return math.min(15, math.ceil(level))
end

function x0x_roll:get_key_level(x, y, v, step, gate)
	local tap = voices[v].mod_tap
	-- highlight any step whose loop position matches the current position of the tap
	local head = tap:check_step_identity(step, 0)
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
		update_voices(true)
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
			write(self:get_last_value())
		end
	end
end

function mask_keyboard:key(x, y, z)
	if z == 1 then
		toggle_mask_class(self:get_key_pitch_id(x, y))
	end
end

function transpose_keyboard:get_next_voice_index(key_id)
	self.key_count = self.key_count + 1
	local free_voice_index = nil
	local free_voice_last_used = self.key_count
	local steal_voice_index = nil
	local steal_voice_last_used = self.key_count
	local next_voice_index = nil
	for n = 1, n_voices do
		local v = voice_selector.selection_order[n]
		if voice_selector:is_selected(v) then
			local voice_usage = self.voice_usage[v]
			if voice_usage.free and voice_usage.last < free_voice_last_used then
				free_voice_index = v
				free_voice_last_used = voice_usage.last
			elseif voice_usage.last < steal_voice_last_used then
				steal_voice_index = v
				steal_voice_last_used = voice_usage.last
			end
		end
	end
	local next_voice_index = free_voice_index or steal_voice_index
	local usage = self.voice_usage[next_voice_index]
	usage.last = self.key_count
	usage.free = false
	usage.key_id = key_id
	return next_voice_index
end

function transpose_keyboard:free_key_voice(key_id)
	for v = 1, n_voices do
		local voice_usage = self.voice_usage[v]
		if voice_usage.key_id == key_id then
			voice_usage.free = true
		end
	end
end

function transpose_keyboard:key(x, y, z)
	-- TODO: what's up with stuck/unresponsive keys?
	-- this refers to two issues, maybe related but maybe not:
	-- 1. voices don't always update immediately after transposing, even when quantization is off
	-- 2. transpose keys appear to be ignored when delta is very low (like less than a quarter tone)
	self:note(x, y, z)
	local key_id = self:get_key_id(x, y)
	if z == 0 then
		self:free_key_voice(key_id)
	else
		local v = self:get_next_voice_index(key_id)
		if held_keys.shift then
			-- adjust noise (random transposition)
			local delta = self:get_last_value() - voices[v].pitch_tap.next_bias
			params:set(string.format('voice_%d_pitch_noise', v), math.abs(delta) * 12)
		else
			-- adjust bias (fixed transposition)
			params:set(string.format('voice_%d_transpose', v), self:get_last_value() * 12)
		end
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
		-- no need to recalculate voice pitch/gate, but we will need to redraw
		for v = 1, n_voices do
			voices[v].dirty = true
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
				local v = voice_selector:get_key_option(x, y)
				local voice = voices[v]
				voice.next_active = not voice.active
				if quantization_off() then
					voice:apply_edits()
					voices[v]:update(false, true)
				end
			end
		else
			voice_selector:key(x, y, z)
			update_top_voice()
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
		if clock_running then
			clock.transport.stop()
		else
			clock.transport.start()
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
			end
		end
	end
end

function crow_setup()
	crow.clear()
	params:bang()
end

function add_params()

	params:add_separator()

	params:add{
		type = 'number',
		id = 'ticks_per_beat',
		name = 'ticks/beat',
		min = 1,
		max = 16,
		default = 8,
		action = function(value)
			ticks_per_beat = value
		end
	}

	for r = 1, n_registers do
		params:add{
			type = 'number',
			id = string.format('pitch_loop_%d_length', r),
			name = string.format('pitch loop %d length', r),
			min = 2,
			max = 128,
			default = 16,
			action = function(value)
				pitch_registers[r]:set_length(value)
				if quantization_off() then
					update_voices(true)
				end
				blinkers.info:start()
			end
		}
		params:add{
			type = 'number',
			id = string.format('mod_loop_%d_length', r),
			name = string.format('mod loop %d length', r),
			min = 2,
			max = 128,
			default = 18,
			action = function(value)
				mod_registers[r]:set_length(value)
				if quantization_off() then
					update_voices(false, true)
				end
				blinkers.info:start()
			end
		}
	end
	
	params:add_separator()
	
	for v = 1, n_voices do
		local voice = voices[v]
		local pitch_tap = voice.pitch_tap
		local mod_tap = voice.mod_tap
		params:add_group(string.format('voice %d', v), 17)
		params:add{
			type = 'number',
			id = string.format('voice_%d_pitch_register', v),
			name = string.format('voice %d pitch register', v),
			min = 1,
			max = n_registers,
			default = 1,
			action = function(value)
				local previous_register = pitch_tap.shift_register
				pitch_tap.shift_register = pitch_registers[value]
				if top_voice_index == v then
					-- TODO: un-sync previous pitch register
					pitch_tap:sync()
				end
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_detune', v),
			name = string.format('voice %d detune', v),
			controlspec = controlspec.new(-50, 50, 'lin', 0.5, (v - 2.5) * 2, 'cents'),
			action = function(value)
				voice.detune = value / 1200
				voice:update(true)
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_transpose', v),
			name = string.format('voice %d transpose', v),
			controlspec = controlspec.new(-48, 48, 'lin', 1 / 10, 0, 'st'),
			action = function(value)
				pitch_tap.next_bias = value / 12
				dirty = true
				memory.transposition.dirty = true
				if quantization_off() then
					pitch_tap:apply_edits()
					voice:update()
				end
			end
		}
		params:add{
			type = 'option',
			id = string.format('voice_%d_pitch_multiply', v),
			name = string.format('voice %d pitch multiply', v),
			options = { '-1', '1' },
			default = 2,
			action = function(value)
				pitch_tap.next_multiply = value == 2 and 1 or -1
				dirty = true
				if quantization_off() then
					pitch_tap:apply_edits()
					voice:update()
				end
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_pitch_scramble', v),
			name = string.format('voice %d pitch scramble', v),
			controlspec = controlspec.new(0, 16, 'lin', 0.1, 0),
			action = function(value)
				pitch_tap.next_scramble = value
				dirty = true
				memory.pitch.dirty = true
				if quantization_off() then
					pitch_tap:apply_edits()
					voice:update()
				end
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_pitch_noise', v),
			name = string.format('voice %d pitch noise', v),
			controlspec = controlspec.new(0, 48, 'lin', 1 / 10, 0, 'st'),
			action = function(value)
				pitch_tap.next_noise = value / 12
				dirty = true
				memory.pitch.dirty = true
				if quantization_off() then
					pitch_tap:apply_edits()
					voice:update()
				end
			end
		}
		params:add{
			type = 'option',
			id = string.format('voice_%d_pitch_rate', v),
			name = string.format('voice %d pitch rate', v),
			options = rate_divisions,
			default = 22,
			action = function(value)
				local direction = value < slowest_rate and -1 or 1
				local ticks_per_shift = slowest_rate - math.abs(slowest_rate - value)
				pitch_tap:set_rate(direction, ticks_per_shift)
				if top_voice_index == v then
					-- resync in case direction has changed
					top_voice.pitch_tap:sync()
				end
				dirty = true
				memory.transposition.dirty = true
				if quantization_off() then
					voice:update()
				end
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_pitch_jitter', v),
			name = string.format('voice %d pitch jitter', v),
			controlspec = controlspec.new(0, 8, 'lin', 0.1, 0),
			action = function(value)
				pitch_tap.next_jitter = value
				dirty = true
				memory.pitch.dirty = true
				if quantization_off() then
					pitch_tap:apply_edits()
					voice:update()
				end
			end
		}
		params:add{
			type = 'number',
			id = string.format('voice_%d_mod_register', v),
			name = string.format('voice %d mod register', v),
			min = 1,
			max = n_registers,
			default = 1,
			action = function(value)
				local previous_register = mod_tap.shift_register
				mod_tap.shift_register = mod_registers[value]
				if top_voice_index == v then
					-- TODO: un-sync previous mod register
					mod_tap:sync()
				end
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_mod_bias', v),
			name = string.format('voice %d mod bias', v),
			controlspec = controlspec.new(-16, 16, 'lin', 0.1, 0),
			action = function(value)
				mod_tap.next_bias = value
				dirty = true
				memory.mod.dirty = true
				if quantization_off() then
					mod_tap:apply_edits()
					voice:update()
				end
			end
		}
		params:add{
			type = 'option',
			id = string.format('voice_%d_mod_multiply', v),
			name = string.format('voice %d mod multiply', v),
			options = { '-1', '1' },
			default = 2,
			action = function(value)
				mod_tap.next_multiply = value == 2 and 1 or -1
				dirty = true
				if quantization_off() then
					mod_tap:apply_edits()
					voice:update()
				end
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_mod_scramble', v),
			name = string.format('voice %d mod scramble', v),
			controlspec = controlspec.new(0, 16, 'lin', 0.1, 0),
			action = function(value)
				mod_tap.next_scramble = value
				dirty = true
				memory.mod.dirty = true
				if quantization_off() then
					mod_tap:apply_edits()
					voice:update()
				end
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_mod_noise', v),
			name = string.format('voice %d mod noise', v),
			controlspec = controlspec.new(0, 16, 'lin', 0.2, 0),
			action = function(value)
				mod_tap.next_noise = value
				dirty = true
				memory.mod.dirty = true
				if quantization_off() then
					mod_tap:apply_edits()
					voice:update()
				end
			end
		}
		params:add{
			type = 'option',
			id = string.format('voice_%d_mod_rate', v),
			name = string.format('voice %d mod rate', v),
			options = rate_divisions,
			default = 22,
			action = function(value)
				local direction = value < slowest_rate and -1 or 1
				local ticks_per_shift = slowest_rate - math.abs(slowest_rate - value)
				mod_tap:set_rate(direction, ticks_per_shift)
				if top_voice_index == v then
					-- resync in case direction has changed
					top_voice.mod_tap:sync()
				end
				dirty = true
				memory.transposition.dirty = true
				if quantization_off() then
					voice:update()
				end
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_mod_jitter', v),
			name = string.format('voice %d mod jitter', v),
			controlspec = controlspec.new(0, 8, 'lin', 0.1, 0),
			action = function(value)
				mod_tap.next_jitter = value
				dirty = true
				memory.mod.dirty = true
				if quantization_off() then
					mod_tap:apply_edits()
					voice:update()
				end
			end
		}
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

	params:add{
		type = 'option',
		id = 'output_mode',
		name = 'output mode',
		options = output_mode_names,
		default = output_mode_crow_2,
		action = function(value)
			-- kill notes
			if output_mode ~= output_mode_polysub then
				for v = 1, n_voices do
					engine.stop(v - 1)
				end
			elseif output_mode == output_mode_crow_2 then
				crow.output[2].volts = 0
				crow.output[4].volts = 0
			end
			output_mode = value
			-- TODO: initialize slew shapes for crow gates?
		end
	}

	params:add_group('polysub', 19)
	polysub.params()

	params:add_group('crow', 8)
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
		params:add{
			type = 'option',
			id = string.format('voice_%d_slew_shape', v),
			name = string.format('voice %d slew shape', v),
			options = crow_slew_shapes,
			default = 2, -- sine
			action = function(value)
				crow.output[v].shape = crow_slew_shapes[value]
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
				update_voices(true)
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

	-- TODO: if memory file is missing (like when freshly installed), copy defaults from the code directory?
	params:set('restore_memory')
	memory.pitch:recall_slot(1)
	memory.mask:recall_slot(1)
	memory.transposition:recall_slot(1)
	memory.mod:recall_slot(1)

	g.key = grid_key
	m.event = midi_event
	
	-- match encoder sensitivity used in norns menus
	norns.enc.accel(1, false)
	norns.enc.sens(1, 8)
	norns.enc.accel(2, false)
	norns.enc.sens(2, 4)
	norns.enc.accel(2, true)
	norns.enc.accel(3, true)
	-- encoder 3's sensitivity changes based on selected field; update it to match initial edit field
	enc(2, 0)

	update_voices()

	dirty = true
	redraw_metro:start()

	clock.transport.start()
end

function key(n, z)
	if n == 1 then
		held_keys.edit_alt = z == 1
		held_keys.edit_fine = false -- reset so it doesn't get stuck when holding both K3 and K1
	elseif n == 2 then
		if held_keys.edit_alt then
			held_keys.edit_dec = z == 1
			if z == 1 then
				-- reset or decrement edit field
				edit_field_delta(held_keys.edit_inc and 'reset' or -1)
			end
		elseif z == 1 then
			-- switch between editing pitch only / mod only / both
			edit_both_taps = not edit_both_taps
			if not edit_both_taps then
				edit_tap = edit_tap % n_edit_taps + 1
			end
		end
	elseif n == 3 then
		if held_keys.edit_alt then
			held_keys.edit_inc = z == 1
			if z == 1 then
				-- reset or increment edit field
				edit_field_delta(held_keys.edit_dec and 'reset' or 1)
			end
		else
			-- enable fine control
			held_keys.edit_fine = z == 1
		end
	end
	blinkers.info:start()
	dirty = true
end

function voice_param_delta(id, d)
	for v = 1, n_voices do
		if voice_selector:is_selected(v) then
			local param = params:lookup_param(string.format('voice_%d_%s', v, id))
			if d == 'reset' then
				param:set_default()
			else
				param:delta(d)
			end
		end
	end
end

-- TODO: offer control over internal clock tempo?
function enc(n, d)
	if n == 1 then
		-- select voice
		local v = util.clamp(top_voice_index + d, 1, n_voices)
		voice_selector:reset()
		voice_selector:select(v)
		update_top_voice()
	elseif n == 2 then
		-- select field
		edit_field = util.clamp(edit_field + d, 1, n_edit_fields)
		-- tweak encoder 3 response for the selected param
		if edit_field == edit_field_time then
			norns.enc.sens(3, 4)
		elseif edit_field == edit_field_rate then
			norns.enc.sens(3, 8)
		else
			norns.enc.sens(3, 2)
		end
	elseif n == 3 then
		-- offset can only be changed by integer values, but for other fields, allow fine adjustment
		if edit_field ~= edit_field_time and held_keys.edit_fine then
			d = d / 20
		end
		edit_field_delta(d)
	end
	blinkers.info:start()
	dirty = true
end

function edit_field_delta(d)
	local reset = d == 'reset'
	if edit_field == edit_field_multiply then
		if edit_both_taps or edit_tap == edit_tap_pitch then
			-- set pitch +/-
			voice_param_delta('pitch_multiply', d)
		end
		if edit_both_taps or edit_tap == edit_tap_mod then
			-- set mod +/-
			voice_param_delta('mod_multiply', d)
		end
	elseif edit_field == edit_field_rate then
		if edit_both_taps or edit_tap == edit_tap_pitch then
			-- set pitch rate/direction
			voice_param_delta('pitch_rate', d)
		end
		if edit_both_taps or edit_tap == edit_tap_mod then
			-- set mod rate/direction
			voice_param_delta('mod_rate', d)
		end
	elseif edit_field == edit_field_jitter then
		if edit_both_taps or edit_tap == edit_tap_pitch then
			-- set pitch jitter
			voice_param_delta('pitch_jitter', d)
		end
		if edit_both_taps or edit_tap == edit_tap_mod then
			-- set mod jitter
			voice_param_delta('mod_jitter', d)
		end
	elseif edit_field == edit_field_scramble then
		if edit_both_taps or edit_tap == edit_tap_pitch then
			-- set pitch scramble
			voice_param_delta('pitch_scramble', d)
		end
		if edit_both_taps or edit_tap == edit_tap_mod then
			-- set mod scramble
			voice_param_delta('mod_scramble', d)
		end
	elseif edit_field == edit_field_time then
		if d ~= 'reset' then -- TODO: sync selected taps to top on reset
			if edit_both_taps or edit_tap == edit_tap_pitch then
				-- shift pitch tap(s)
				for v = 1, n_voices do
					if voice_selector:is_selected(v) then
						local voice = voices[v]
						voice.pitch_tap:shift(-d, true)
						voice:update()
					end
				end
				memory.pitch.dirty = true
			end
			if edit_both_taps or edit_tap == edit_tap_mod then
				-- shift mod tap(s)
				for v = 1, n_voices do
					if voice_selector:is_selected(v) then
						local voice = voices[v]
						voice.mod_tap:shift(-d, true)
						voice:update()
					end
				end
				memory.mod.dirty = true
			end
		end
	elseif edit_field == edit_field_noise then
		if edit_both_taps or edit_tap == edit_tap_pitch then
			-- set pitch noise
			voice_param_delta('pitch_noise', d)
		end
		if edit_both_taps or edit_tap == edit_tap_mod then
			-- set mod noise
			voice_param_delta('mod_noise', d)
		end
	elseif edit_field == edit_field_bias then
		if edit_both_taps or edit_tap == edit_tap_pitch then
			-- transpose voice(s)
			if d ~= 'reset' then
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
			end
			-- transpose 'em
			voice_param_delta('transpose', d)
		end
		if edit_both_taps or edit_tap == edit_tap_mod then
			-- set mod bias
			voice_param_delta('mod_bias', d)
		end
	elseif edit_field == edit_field_length then
		if edit_both_taps or edit_tap == edit_tap_pitch then
			-- set pitch length
			params:delta('pitch_loop_length', d)
		end
		if edit_both_taps or edit_tap == edit_tap_mod then
			-- set mod length
			params:delta('mod_loop_length', d)
		end
	end
end

function get_screen_offset_x(offset)
	return screen_note_width * (screen_note_center + offset)
end

function get_screen_note_y(value)
	if value == nil then
		return -1
	end
	return math.floor(32 + (view_octave - value) * 12 + 0.5)
end

-- calculate coordinates and levels for each visible note
function calculate_voice_path(v)
	local voice = voices[v]
	local pitch_tap = voice.pitch_tap
	local mod_tap = voice.mod_tap
	local path = voice_paths[v]
	local n = 0
	local note = path[1]
	local x = 0
	for t = 1, n_screen_notes do
		local tick = t - screen_note_center
		local pitch, pitch_pos, pitch_step = pitch_tap:get_tick_value(tick)
		local mod, mod_pos, mod_step = mod_tap:get_tick_value(tick)
		local gate = voice.active and voice:mod_to_gate(mod)
		if n == 0 or pitch_step ~= note.pitch_step or mod_step ~= note.mod_step then
			local y = get_screen_note_y(scale:snap(pitch))
			local y0 = note.y or y
			local connect = n ~= 0 and gate and note.gate
			x = (t - 1) * screen_note_width
			-- set final x and y of previous note
			note.x2 = x
			-- fill in info for this note
			n = n + 1
			note = path[n]
			note.pitch_step = pitch_step
			note.pitch_pos = pitch_tap.shift_register:wrap_loop_pos(pitch_pos)
			note.pitch = pitch
			note.mod_step = mod_step
			note.mod_pos = mod_tap.shift_register:wrap_loop_pos(mod_pos)
			note.mod = mod
			note.gate = gate
			note.connect = connect
			note.x = x
			note.y = y
			note.y0 = y0
		end
		if tick == 0 then
			-- set center values, to draw over the head indicator
			path.y_center = note.y
			path.gate_center = note.gate
		end
	end
	-- set final values for last note
	note.x2 = 128
	path.length = n
	voice.path_dirty = false
	dirty = true
end

function draw_voice_path(v, level)
	local voice = voices[v]
	local path = voice_paths[v]
	local prev_level = 0
	local pitch_tap = voice.pitch_tap
	local pitch_register = pitch_tap.shift_register
	local mod_tap = voice.mod_tap
	local mod_register = mod_tap.shift_register
	local has_pitch_edits = pitch_tap.next_jitter ~= pitch_tap.jitter or pitch_tap.next_scramble ~= pitch_tap.scramble or pitch_tap.next_noise ~= pitch_tap.noise or pitch_tap.next_bias ~= pitch_tap.bias or pitch_tap.next_multiply ~= pitch_tap.next_multiply
	local has_mod_edits = mod_tap.next_jitter ~= mod_tap.jitter or mod_tap.next_scramble ~= mod_tap.scramble or mod_tap.next_noise ~= mod_tap.noise or mod_tap.next_bias ~= mod_tap.bias or mod_tap.next_multiply ~= mod_tap.next_multiply
	for n = 1, path.length do
		local note = path[n]
		local x = note.x
		local x2 = note.x2
		local y = note.y
		local y0 = note.y0
		local gate = note.gate
		local note_edit_dim = ((has_pitch_edits and note.pitch_step <= 0) or (has_mod_edits and note.mod_step <= 0)) and 1 or 0
		local note_level = 0
		-- set flash level, if this note was recently changed
		-- TODO: only flash when written register matches this voice's register
		for w = 1, n_recent_writes do
			local write = recent_writes[w]
			if write.level > 0 then
				if write.type == write_type_pitch and note.pitch_pos == pitch_register:wrap_loop_pos(write.pos) then
					note_level = math.max(note_level, write.level)
				elseif write.type == write_type_mod and note.mod_pos == mod_register:wrap_loop_pos(write.pos) then
					note_level = math.max(note_level, write.level)
				end
			end
		end
		-- if previous note was at the same `y` and its level was higher, don't redraw the leftmost
		-- pixel of this note over it
		if y0 == y and prev_level > note_level then
			x = x + 1
		end
		-- draw this note, including dotted lines for inactive notes in selected voices
		if gate then
			-- solid line for active notes
			local note_y = y + 0.5
			-- outline
			if y0 == y then
				screen.move(x, note_y)
			elseif math.abs(y0 - y) == 1 then
				-- when y0 and y are within 1 pixel of one another, draw a partial outline to prevent
				-- overlap with the previous note
				screen.move(x - 1, note_y + (y - y0) * 0.5)
				screen.line_rel(x + 1, 0)
				screen.level(0)
				screen.line_width(2)
				screen.stroke()
			else
				screen.move(x - 1, note_y)
			end
			screen.line(x2 + 2, note_y)
			screen.level(0)
			screen.line_width(3)
			screen.stroke()
			-- center
			screen.move(x, note_y)
			screen.line(x2 + 1, note_y)
			screen.level(math.ceil(led_blend(level - note_edit_dim, note_level)))
			screen.line_width(1)
			screen.stroke()
		elseif voice_selector:is_selected(v) or note_level > 0 then
			-- dotted line for inactive notes
			for dot_x = x, note.x2 do
				if dot_x % 2 == 0 then
					screen.pixel(dot_x, y)
				end
			end
			screen.level(math.ceil(led_blend((level - note_edit_dim) / 3, note_level)))
			screen.fill()
		end
		-- draw connector from previous note, if any
		if note.connect then
			local connector_length = math.abs(y - y0) - 1
			if connector_length > 0 then
				local connector_x = x + 0.5
				local connector_y = math.min(y, y0) + 1
				-- outline
				screen.move(connector_x, connector_y)
				screen.line_rel(0, connector_length)
				screen.level(0)
				screen.line_width(3)
				screen.stroke()
				-- center
				screen.move(connector_x, connector_y)
				screen.line_rel(0, connector_length)
				screen.level(math.ceil(led_blend(level, math.max(note_level, prev_level) / 4)))
				screen.line_width(1)
				screen.stroke()
			end
		end
		-- save flash level to compare with next note
		prev_level = note_level
	end
end

function draw_tap_equation(y, label, tap, unit_multiplier, editing)
	local highlight_multiply = editing and edit_field == edit_field_multiply
	local highlight_time = editing and edit_field == edit_field_time
	local highlight_rate = editing and edit_field == edit_field_rate
	local highlight_jitter = editing and edit_field == edit_field_jitter
	local highlight_scramble = editing and edit_field == edit_field_scramble
	local highlight_noise = editing and edit_field == edit_field_noise
	local highlight_bias = editing and edit_field == edit_field_bias
	local highlight_length = editing and edit_field == edit_field_length

	local multiply = tap.next_multiply
	local direction = tap.direction
	local ticks_per_shift = tap.ticks_per_shift
	local jitter = tap.next_jitter
	local scramble = tap.next_scramble * direction
	local noise = tap.next_noise * direction * unit_multiplier
	local bias = tap.next_bias * unit_multiplier
	local loop_length = tap.shift_register.loop_length

	screen.move(8, y)

	if highlight_multiply or multiply ~= 1 then
		screen.level(highlight_multiply and 15 or 3)
		screen.text(multiply == -1 and '-' or '+')
	end

	screen.level(3)
	screen.text(label .. '[')

	screen.level(highlight_time and 15 or 3)
	if direction < 0 then
		screen.text('-t')
	else
		screen.text('t')
	end

	screen.level(3)

	if highlight_rate or highlight_jitter or ticks_per_shift ~= 1 or jitter ~= 0 then
		screen.text('/')

		if highlight_jitter or jitter ~= 0 then
			screen.text('(')
		end

		screen.level(highlight_rate and 15 or 3)
		if ticks_per_shift == slowest_rate then
			screen.text('inf')
		else
			screen.text(string.format('%d', ticks_per_shift))
		end

		if highlight_jitter or jitter ~= 0 then
			screen.level(highlight_jitter and 15 or 3)
			screen.text(string.format('%+.1fy', jitter))
			screen.level(3)
			screen.text(')')
		end
	end

	screen.level(highlight_scramble and 15 or 3)
	if highlight_scramble or scramble ~= 0 then
		screen.text(string.format('+%.1fk', scramble))
	end

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
	screen.text(string.format('%d', loop_length))

	screen.level(3)
	screen.text(']')
end

function redraw()
	screen.clear()

	-- draw paths
	for i = n_voices, 1, -1 do
		local v = voice_selector.selection_order[i]
		local level = voices[v].active and 1 or 0
		if i == 1 then
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
	for i = n_voices, 1, -1 do
		local v = voice_selector.selection_order[i]
		local path = voice_paths[v]
		if path.gate_center then
			screen.move(62.5, path.y_center - 1)
			screen.line(62.5, path.y_center + 2)
			screen.level(0)
			screen.stroke()
			screen.pixel(62, path.y_center)
			screen.level(15)
			screen.fill()
		end
	end

	if held_keys.edit_alt or blinkers.info.on then

		screen.font_face(1)
		screen.font_size(8)

		screen.rect(0, 47, 128, 17)
		screen.level(0)
		screen.fill()

		screen.move(0, 54)
		screen.level(3)
		screen.text(string.format('%d.', top_voice_index))

		draw_tap_equation(54, 'p', top_voice.pitch_tap, 12, edit_both_taps or edit_tap == edit_tap_pitch)

		draw_tap_equation(62, 'g', top_voice.mod_tap, 1, edit_both_taps or edit_tap == edit_tap_mod)

	end

	-- DEBUG: draw minibuffer, loop region, head
	--[[
	local pitch_register = top_voice.pitch_tap.shift_register
	screen.move(0, 1)
	screen.line_rel(pitch_register.buffer_size, 0)
	screen.level(1)
	screen.stroke()
	for offset = 1, pitch_register.loop_length do
		local pos = pitch_register:wrap_buffer_pos(pitch_register:get_loop_offset_pos(offset))
		screen.pixel(pos - 1, 0)
		screen.level(7)
		for v = 1, n_voices do
			if voice_selector:is_selected(v) and pos == pitch_register:wrap_buffer_pos(pitch_register:wrap_loop_pos(voices[v].pitch_tap.pos)) then
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
	for i, blinker in ipairs(blinkers) do
		blinker:stop()
	end
end
