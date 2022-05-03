-- fretwork
--
-- shift register sequencer,
-- microtonal autoharp,
-- etc.

polysub = require 'polysub'
engine.name = 'PolySub'

musicutil = require 'musicutil'

Roll = include 'lib/grid_roll'
OffsetRoll = include 'lib/grid_offset_roll'
Keyboard = include 'lib/grid_keyboard'
RegisterSelector = include 'lib/grid_register_selector'
RateSelector = include 'lib/grid_rate_selector'
MemorySelector = include 'lib/grid_memory_selector'
Select = include 'lib/grid_select'
MultiSelect = include 'lib/grid_multi_select'
ShiftRegister = include 'lib/shift_register'
ShiftRegisterVoice = include 'lib/shift_register_voice'
VoiceParams = include 'lib/voice_params'
Scale = include 'lib/scale'
Blinker = include 'lib/blinker'

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
n_registers = 7
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
output_mode = output_mode_crow_4

voice_param_names = {
	rate = {
		rate = 'voice_%d_rate',
		jitter = 'voice_%d_jitter'
	},
	pitch = {
		loop_length = 'pitch_loop_%%d_length',
		register = 'voice_%d_pitch_register',
		detune = 'voice_%d_detune',
		transpose = 'voice_%d_transpose',
		retrograde = 'voice_%d_pitch_retrograde',
		inversion = 'voice_%d_pitch_inversion',
		scramble = 'voice_%d_pitch_scramble',
		noise = 'voice_%d_pitch_noise'
	},
	mod = {
		loop_length = 'mod_loop_%%d_length',
		register = 'voice_%d_mod_register',
		bias = 'voice_%d_bias',
		retrograde = 'voice_%d_mod_retrograde',
		inversion = 'voice_%d_mod_inversion',
		scramble = 'voice_%d_mod_scramble',
		noise = 'voice_%d_mod_noise'
	}
}

n_voices = 4
voices = {}
top_voice_index = 1
for v = 1, n_voices do
	local voice = ShiftRegisterVoice.new(v * -3, pitch_registers[1], scale, v * -4, mod_registers[1])
	voice.pitch_tap.on_write = function(pos)
		flash_write(voice.pitch_tap.shift_register, pos)
	end
	voice.mod_tap.on_write = function(pos)
		flash_write(voice.mod_tap.shift_register, pos)
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
	voice.params = VoiceParams.new(v, voice_param_names)
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
			bias_pitch_id = 0,
			noisy_bias_pitch_id = 0,
			gate = false,
			onset_level = 0,
			release_level = 0,
			highlight_level = 0
		}
	end
end

voice_selector = MultiSelect.new(1, 3, 1, 4)

g = grid.connect()
m = midi.connect()

held_keys = {
	esc = false,
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

rate_selector = RateSelector.new(2, 1, 15, 7, n_voices, voices, 'rate')

pitch_register_selector = RegisterSelector.new(2, 1, 15, 7, n_voices, voices, n_registers, pitch_registers, 'pitch')
mod_register_selector = RegisterSelector.new(2, 1, 15, 7, n_voices, voices, n_registers, mod_registers, 'mod')

pitch_keyboard = Keyboard.new(2, 1, 15, 7, scale)
mask_keyboard = Keyboard.new(2, 1, 15, 7, scale)
transpose_keyboard = Keyboard.new(2, 1, 15, 7, scale)
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

pitch_offset_roll = OffsetRoll.new(2, 1, 15, 7, n_voices, voices, 'pitch')
mod_offset_roll = OffsetRoll.new(2, 1, 15, 7, n_voices, voices, 'mod')
gate_roll = Roll.new(2, 1, 15, 7, n_voices, voices, 'mod')

for v = 1, n_voices do
	local pitch_tap = voices[v].pitch_tap
	local on_pitch_shift = pitch_tap.on_shift
	local mod_tap = voices[v].mod_tap
	local on_mod_shift = mod_tap.on_shift
	pitch_tap.on_shift = function(d)
		on_pitch_shift(d)
		pitch_offset_roll:shift_voice(v, d)
	end
	mod_tap.on_shift = function(d)
		on_mod_shift(d)
		gate_roll:shift_voice(v, d)
		mod_offset_roll:shift_voice(v, d)
	end
end

grid_views = {
	rate_selector,
	nil, -- spacer
	pitch_offset_roll,
	pitch_register_selector,
	pitch_keyboard,
	mask_keyboard,
	transpose_keyboard,
	nil, -- spacer
	mod_offset_roll,
	mod_register_selector,
	gate_roll
}
n_grid_views = 11
grid_view_rate = 1
grid_view_pitch_offset = 3
grid_view_pitch_register = 4
grid_view_pitch = 5
grid_view_mask = 6
grid_view_transpose = 7
grid_view_mod_offset = 9
grid_view_mod_register = 10
grid_view_gate = 11

grid_view_selector = Select.new(3, 8, 11, 1)
memory_view = MemorySelector.new(2, 1, 15, 8)

grid_view_selector.on_select = function(option)
	if not held_keys.esc then
		grid_view = grid_views[option]
		dirty = true
	end
end

grid_view = grid_views[1]

screen_note_width = 4
n_screen_notes = 128 / screen_note_width
screen_note_center = math.floor((n_screen_notes - 1) / 2 + 0.5)
-- initialize voice paths, which can persist between redraws
voice_paths = {}
for v = 1, n_voices do
	local voice_path = {}
	for n = 1, n_screen_notes do
		voice_path[n] = {
			step = 0,
			pitch = 0,
			pitch_pos = 0,
			mod = 0,
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
recent_writes = {
	last = n_recent_writes
}
for w = 1, n_recent_writes do
	recent_writes[w] = {
		shift_register = 0,
		level = 0,
		pos = 0,
	}
end

n_edit_taps = 2
edit_tap_pitch = 1
edit_tap_mod = 2
edit_tap = edit_tap_pitch
edit_both_taps = true

n_edit_fields = 9
edit_field_multiply = 1
edit_field_direction = 2
edit_field_time = 3
edit_field_rate = 4
edit_field_jitter = 5
edit_field_scramble = 6
edit_field_noise = 7
edit_field_bias = 8
edit_field_length = 9
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

		pitch_offset_roll:smooth_hold_steps()
		gate_roll:smooth_hold_steps()
		mod_offset_roll:smooth_hold_steps()

		if not blink_slow and tick % 8 > 3 then
			blink_slow = true
			dirty = true
		elseif blink_slow and tick % 8 <= 3 then
			blink_slow = false
			dirty = true
		end

		for v = 1, n_voices do
			local voice = voices[v]
			local recent_notes = recent_voice_notes[v]
			local last_note = recent_notes.last
			-- calculate voice paths, if necessary
			if voices[v].path_dirty then
				calculate_voice_path(v)
			end
			-- fade recent voice notes
			for n = 1, n_recent_voice_notes do
				local note = recent_notes[n]
				-- always fade onset
				if note.onset_level > 0 then
					note.onset_level = note.onset_level - 1
					dirty = true
				end
				-- reset highlight level if selected, fade if not
				if n == last_note and voice_selector:is_selected(v) then
					if note.highlight_level ~= 1 then
						note.highlight_level = 1
						dirty = true
					end
				else
					if note.highlight_level > 0.06 then -- < 1/15
						note.highlight_level = note.highlight_level * 0.4
						dirty = true
					elseif note.highlight_level > 0 then
						note.highlight_level = 0
						dirty = true
					end
				end
				-- reset release level if selected, fade if not
				if n == last_note and note.gate then
					if note.release_level ~= 1 then
						note.release_level = 1
						dirty = true
					end
				else
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

function quantization_off()
	-- disable quantization if ctrl is held/locked or clock is paused
	return (held_keys.ctrl ~= held_keys.ctrl_lock) == clock_running
end

function flash_note(v)
	local voice = voices[v]
	local recent_notes = recent_voice_notes[v]
	local recent_note = recent_notes[recent_notes.last]
	if recent_note.pitch_id ~= voice.pitch_id or recent_note.bias_pitch_id ~= voice.bias_pitch_id or recent_note.noisy_bias_pitch_id ~= voice.noisy_bias_pitch_id then
		-- if note has changed, release current note and move to a new one
		recent_note.gate = false
		recent_notes.last = recent_notes.last % n_recent_voice_notes + 1
		recent_note = recent_notes[recent_notes.last]
		-- set pitch data
		recent_note.pitch_id = voice.pitch_id
		recent_note.bias_pitch_id = voice.bias_pitch_id
		recent_note.noisy_bias_pitch_id = voice.noisy_bias_pitch_id
		dirty = true
	end
	-- set levels
	if voice.gate ~= recent_note.gate then
		recent_note.gate = voice.gate
		recent_note.onset_level = voice.gate and 2 or 0
		dirty = true
	end
end

function midi_note(v)
	local voice = voices[v]
	local last_midi_note = voice.last_midi_note
	if voice.gate then
		m:pitchbend(math.floor(voice.midi_bend), voice.midi_out_channel)
		m:note_on(voice.midi_note, 100, voice.midi_out_channel)
		voice.last_midi_note = voice.midi_note
		if voice.midi_note ~= last_midi_note then
			m:note_off(last_midi_note, 0, voice.midi_out_channel)
		end
	else
		m:note_off(last_midi_note, 0, voice.midi_out_channel)
	end
end

function note_on(v, pitch)
	if output_mode == output_mode_crow_4 then
		crow.output[v].volts = pitch
		midi_note(v)
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
		midi_note(v)
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

function flash_write(shift_register, pos)
	recent_writes.last = recent_writes.last % n_recent_writes + 1
	local write = recent_writes[recent_writes.last]
	write.shift_register = shift_register
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

	g:all(0)

	-- view buttons
	if not held_keys.esc then
		grid_view_selector:draw(g, 7, 3)
		-- clear 'spacers'
		g:led(grid_view_rate + 3, 8, 0)
		g:led(grid_view_transpose + 3, 8, 0)
		-- darken non-unique views
		for v = grid_view_pitch_offset, grid_view_pitch_register do
			if not grid_view_selector:is_selected(v) then
				g:led(v + 2, 8, 2)
			end
		end
		for v = grid_view_mod_offset, grid_view_mod_register do
			if not grid_view_selector:is_selected(v) then
				g:led(v + 2, 8, 2)
			end
		end
	end

	-- shift + ctrl
	g:led(1, 7, held_keys.shift and 15 or 2)
	if held_keys.ctrl_lock then
		g:led(1, 8, held_keys.ctrl and 2 or 10)
	else
		g:led(1, 8, held_keys.ctrl and 15 or 2)
	end

	-- esc
	g:led(1, 1, held_keys.esc and 15 or 2)

	-- voice buttons
	for y = voice_selector.y, voice_selector.y2 do
		local v = voice_selector:get_key_option(voice_selector.x, y)
		local level = get_voice_control_level(v, 3)
		g:led(voice_selector.x, y, math.floor(math.min(15, level)))
	end

	-- calculate levels for keyboards
	if grid_view ~= nil and grid_view.get_key_pitch_id ~= nil then
		local low_pitch_id = grid_view:get_key_pitch_id(pitch_keyboard.x, pitch_keyboard.y2)
		local high_pitch_id = grid_view:get_key_pitch_id(pitch_keyboard.x2, pitch_keyboard.y)
		for n = low_pitch_id, high_pitch_id do
			absolute_pitch_levels[n] = 0
			relative_pitch_levels[n] = 0
		end
		for v = 1, n_voices do
			local voice = voices[v]
			local recent_notes = recent_voice_notes[v]
			local next_bias_pitch_id = voice.next_bias_pitch_id
			local show_next_bias = next_bias_pitch_id ~= voice.bias_pitch_id
			for n = 1, n_recent_voice_notes do
				local level = get_voice_note_level(v, recent_notes[n], 4)
				local note = recent_notes[n]
				local pitch_id = note.pitch_id
				local bias_pitch_id = note.bias_pitch_id
				local noisy_bias_pitch_id = note.noisy_bias_pitch_id
				if pitch_id >= low_pitch_id and pitch_id <= high_pitch_id then
					absolute_pitch_levels[pitch_id] = led_blend(absolute_pitch_levels[pitch_id], level)
				end
				-- TODO: it's hard to distinguish between highlighted and non-highlighted relative notes now, because they pile up
				if bias_pitch_id >= low_pitch_id and bias_pitch_id <= high_pitch_id then
					relative_pitch_levels[bias_pitch_id] = led_blend(relative_pitch_levels[bias_pitch_id], level)
				end
				if noisy_bias_pitch_id >= low_pitch_id and noisy_bias_pitch_id <= high_pitch_id then
					relative_pitch_levels[noisy_bias_pitch_id] = led_blend(relative_pitch_levels[noisy_bias_pitch_id], level * 0.75)
				end
			end
			if voice_selector:is_selected(v) and show_next_bias and next_bias_pitch_id >= low_pitch_id and next_bias_pitch_id <= high_pitch_id then
				relative_pitch_levels[next_bias_pitch_id] = led_blend(relative_pitch_levels[next_bias_pitch_id], 2)
			end
		end
	end

	if grid_view ~= nil then
		grid_view:draw(g)
	end

	-- transport
	local play_button_level = blinkers.play.on and 4 or 3
	if clock_running then
		play_button_level = play_button_level + 4
	end
	g:led(15, 8, play_button_level)
	local record_button_level = 3
	if blinkers.record.on then
		record_button_level = 8
	elseif write_enable then
		record_button_level = 7
	end
	g:led(16, 8, record_button_level)

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
	-- highlight octaves
	if (n - scale.center_pitch_id) % scale.length == 0 then
		level = math.max(level, 2)
	end
	return math.min(15, math.ceil(level))
end

-- TODO: views manage memory: get_state, set_state, store em in a table

function get_voice_note_level(v, note, type)
	local voice = voices[v]
	local level = 0
	if type == 1 then -- 2-5
		level = 2
		if voice.active then level = level + 1 end
		if voice.next_active then level = level + 1 end
		if voice_selector:is_selected(v) then level = level + 1 end
	elseif type == 2 then -- 2-7
		level = 2
		if voice.active then level = level + 1 end
		if voice.next_active then level = level + 2 end
		if voice_selector:is_selected(v) then level = level + 2 end
	elseif type == 3 then -- 3-15
		level = 3
		level = level + note.onset_level
		level = level + note.release_level * 3
		level = level + note.highlight_level * (v == top_voice_index and 7 or 4)
	elseif type == 4 then -- 0-15
		level = level + note.onset_level
		level = level + note.release_level * 4
		level = level + note.highlight_level * (v == top_voice_index and 9 or 4)
	end
	return math.min(15, math.ceil(level))
end

function get_voice_control_level(v, type)
	local level = 0
	local notes = recent_voice_notes[v]
	local last_note = notes[notes.last]
	return get_voice_note_level(v, last_note, type)
end

function gate_roll:get_key_level(x, y, v, step)
	local voice = voices[v]
	local gate = voice:get_step_gate(step)
	local tap = voice.mod_tap
	-- highlight any step whose loop position matches the current position of the tap
	local head = tap:check_step_identity(step, 0)
	if gate then
		return math.ceil(get_voice_control_level(v, head and 3 or 1))
	elseif head then
		return voice.active and 2 or 1
	else
		return 0
	end
end

function gate_roll:on_step_key(x, y, v, step)
	local voice = voices[v]
	voice:toggle_step_gate(step)
	flash_write(voice.mod_tap.shift_register, voice.mod_tap:get_step_pos(step))
	if quantization_off() then
		update_voices(false, true)
	end
end

function toggle_mask_class(pitch_id)
	scale:toggle_class(pitch_id)
	memory.mask.dirty = true
	if quantization_off() then
		scale:apply_edits()
		update_voices(true)
	end
end

function pitch_keyboard:note_key(x, y, z)
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

function mask_keyboard:note_key(x, y, z)
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

function transpose_keyboard:note_key(x, y, z)
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

function g.key(x, y, z)
	if grid_view ~= nil and grid_view:should_handle_key(x, y) then
		grid_view:key(x, y, z)
		if grid_view.is_octave_key ~= nil and grid_view:is_octave_key(x, y) then
			view_octave = grid_view.octave
			-- no need to recalculate voice pitch/gate, but we will need to redraw
			for v = 1, n_voices do
				voices[v].dirty = true
			end
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
	elseif grid_view_selector:should_handle_key(x, y) then
		-- ignore spacer keys
		if x == 4 or x == 10 then
			return
		end
		-- clear the current keyboard's held note stack, in order to prevent held notes from getting
		-- stuck when switching to a mode that doesn't call `keyboard:note()`
		if grid_view ~= nil then
			grid_view:reset()
		end
		grid_view_selector:key(x, y, z)
		-- update the new view's octave to match the previous view's
		if grid_view ~= nil and grid_view.octave ~= nil then
			grid_view.octave = view_octave
		end
	elseif x == 1 and y == 1 then
		-- esc key
		held_keys.esc = z == 1
		if held_keys.esc then
			grid_view = memory_view
		else
			grid_view = grid_views[grid_view_selector.selected]
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
	elseif x == 15 and y == 8 and z == 1 then
		-- play key
		if clock_running then
			clock.transport.stop()
		else
			clock.transport.start()
		end
	elseif x == 16 and y == 8 and z == 1 then
		-- record key
		write_enable = not write_enable
	end
	dirty = true
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

	params:add_group('loop lengths', n_registers * 2)
	for r = 1, n_registers do
		params:add{
			type = 'number',
			id = string.format('pitch_loop_%d_length', r),
			name = string.format('pitch loop %d', r),
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
			name = string.format('mod loop %d', r),
			min = 2,
			max = 128,
			default = 16,
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
		params:add_group(string.format('voice %d', v), 15)
		params:add{
			type = 'number',
			id = string.format('voice_%d_rate', v),
			name = string.format('voice %d rate', v),
			min = 1,
			max = 8,
			default = 4,
			action = function(value)
				voice:set_rate(value)
				rate_selector.sliders[v].selected = value
				dirty = true
				if quantization_off() then
					voice:update()
				end
			end
		}
		params:add{
			type = 'control',
			id = string.format('voice_%d_jitter', v),
			name = string.format('voice %d jitter', v),
			controlspec = controlspec.new(0, 8, 'lin', 0.1, 0),
			action = function(value)
				voice.next_jitter = value
				dirty = true
				if quantization_off() then
					voice:apply_edits()
					voice:update()
				end
			end
		}
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
				pitch_register_selector.sliders[v].selected = value
				if previous_register.sync_tap == pitch_tap then
					-- try to find another tap that uses this shift register, and sync it if we can
					local next_tap = nil
					for v2 = 1, n_voices do
						if next_tap == nil then
							local other_tap = voices[voice_selector.selection_order[v2]].pitch_tap
							if other_tap.shift_register == previous_register then
								next_tap = other_tap
							end
						end
					end
					if next_tap ~= nil then
						next_tap:sync()
					else
						previous_register.sync_tap = nil
					end
					-- sync this tap to the new shift register
					pitch_tap:sync()
				elseif pitch_tap.shift_register.sync_tap == nil then
					-- if this shift register has never been synced, sync it
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
				voice.next_bias_pitch_id = scale:get_nearest_pitch_id(pitch_tap.next_bias)
				dirty = true
				-- memory.transposition.dirty = true -- TODO
				if quantization_off() then
					pitch_tap:apply_edits()
					voice:update()
				end
			end
		}
		params:add{
			type = 'number',
			id = string.format('voice_%d_pitch_retrograde', v),
			name = string.format('voice %d pitch retrograde', v),
			min = 0,
			max = 1,
			default = 0,
			action = function(value)
				pitch_tap.direction = value * -2 + 1
				if pitch_tap:is_synced() then
					pitch_tap:sync() -- resync to set shift register direction
				end
				dirty = true
				if quantization_off() then
					voice:update()
				end
			end
		}
		params:add{
			type = 'number',
			id = string.format('voice_%d_pitch_inversion', v),
			name = string.format('voice %d pitch inversion', v),
			min = 0,
			max = 1,
			default = 0,
			action = function(value)
				pitch_tap.next_multiply = value * -2 + 1
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
				-- memory.pitch.dirty = true -- TODO
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
				-- memory.pitch.dirty = true -- TODO
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
				mod_register_selector.sliders[v].selected = value
				if previous_register.sync_tap == mod_tap then
					-- try to find another tap that uses this shift register, and sync it if we can
					local next_tap = nil
					for v2 = 1, n_voices do
						if next_tap == nil then
							local other_tap = voices[voice_selector.selection_order[v2]].mod_tap
							if other_tap.shift_register == previous_register then
								next_tap = other_tap
							end
						end
					end
					if next_tap ~= nil then
						next_tap:sync()
					else
						previous_register.sync_tap = nil
					end
					-- sync this tap to the new shift register
					mod_tap:sync()
				elseif mod_tap.shift_register.sync_tap == nil then
					-- if this shift register has never been synced, sync it
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
				-- memory.mod.dirty = true -- TODO
				if quantization_off() then
					mod_tap:apply_edits()
					voice:update()
				end
			end
		}
		params:add{
			type = 'number',
			id = string.format('voice_%d_mod_retrograde', v),
			name = string.format('voice %d mod retrograde', v),
			min = 0,
			max = 1,
			default = 0,
			action = function(value)
				mod_tap.direction = value * -2 + 1
				if mod_tap:is_synced() then
					mod_tap:sync() -- resync to set shift register direction
				end
				dirty = true
				if quantization_off() then
					voice:update()
				end
			end
		}
		params:add{
			type = 'number',
			id = string.format('voice_%d_mod_inversion', v),
			name = string.format('voice %d mod inversion', v),
			min = 0,
			max = 1,
			default = 0,
			action = function(value)
				mod_tap.next_multiply = value * -2 + 1
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
				-- memory.mod.dirty = true -- TODO
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
				-- memory.mod.dirty = true -- TODO
				if quantization_off() then
					mod_tap:apply_edits()
					voice:update()
				end
			end
		}
	end

	params:add_separator()

	params:add{
		type = 'option',
		id = 'output_mode',
		name = 'output mode',
		options = output_mode_names,
		default = output_mode_crow_4,
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

	params:add_group('crow', n_voices * 2)
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

	params:add_group('midi', n_voices * 2)
	for v = 1, n_voices do
		local voice = voices[v]
		params:add{
			type = 'number',
			id = string.format('voice_%d_out_channel', v),
			name = string.format('voice %d out channel', v),
			min = 1,
			max = 16,
			default = v,
			action = function(value)
				m:note_off(voice.last_midi_note, 0, voice.midi_out_channel) -- stop current note, if any
				voice.midi_out_channel = value
			end
		}
		params:add{
			type = 'number',
			id = string.format('voice_%d_out_bend_range', v),
			name = string.format('voice %d bend range', v),
			min = 1,
			max = 12,
			default = 2,
			action = function(value)
				voice.midi_out_bend_range = value
			end
		}
	end

	params:add_separator()

	-- TODO: set tuning root note (as scale degree, or in 12 equal?)
	params:add{
		type = 'file',
		id = 'tuning_file',
		name = 'tuning_file',
		path = '/home/we/dust/code/fretwork/lib/12tet.scl',
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

--[[
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
	--]]

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
	voice_selector:reset(true)

	-- TODO: if memory file is missing (like when freshly installed), copy defaults from the code directory?
	-- params:set('restore_memory')
	for v = 1, n_grid_views do
		local selector = memory_view.selectors[v]
		if selector ~= nil then
			selector:select(1)
		end
	end

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
			voice_param_delta('pitch_inversion', -d)
		end
		if edit_both_taps or edit_tap == edit_tap_mod then
			-- set mod +/-
			voice_param_delta('mod_inversion', -d)
		end
	elseif edit_field == edit_field_direction then
		if edit_both_taps or edit_tap == edit_tap_pitch then
			-- set pitch +/-
			voice_param_delta('pitch_retrograde', -d)
		end
		if edit_both_taps or edit_tap == edit_tap_mod then
			-- set mod +/-
			voice_param_delta('mod_retrograde', -d)
		end
	elseif edit_field == edit_field_rate then
		-- set voice rate/direction
		voice_param_delta('rate', d)
	elseif edit_field == edit_field_jitter then
		-- set voice jitter
		voice_param_delta('jitter', d)
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
						voice.pitch_tap:shift(-d)
						voice:update()
					end
				end
				-- memory.pitch.dirty = true -- TODO
			end
			if edit_both_taps or edit_tap == edit_tap_mod then
				-- shift mod tap(s)
				for v = 1, n_voices do
					if voice_selector:is_selected(v) then
						local voice = voices[v]
						voice.mod_tap:shift(-d)
						voice:update()
					end
				end
				-- memory.mod.dirty = true -- TODO
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
			params:delta(string.format('pitch_loop_%d_length', params:get(string.format('voice_%d_pitch_register', top_voice_index))), d)
		end
		if edit_both_taps or edit_tap == edit_tap_mod then
			-- set mod length
			params:delta(string.format('mod_loop_%d_length', params:get(string.format('voice_%d_mod_register', top_voice_index))), d)
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
		local step = voice:get_tick_step(tick)
		local pitch, pitch_noisy_bias, pitch_bias, pitch_pos = pitch_tap:get_step_value(step)
		local mod, mod_noisy_bias, mod_bias, mod_pos = mod_tap:get_step_value(step)
		local gate = voice.active and voice:mod_to_gate(mod)
		if n == 0 or step ~= note.step then
			local y = get_screen_note_y(scale:snap(pitch))
			local y0 = note.y or y
			local connect = n ~= 0 and gate and note.gate
			x = (t - 1) * screen_note_width
			-- set final x and y of previous note
			note.x2 = x
			-- fill in info for this note
			n = n + 1
			note = path[n]
			note.step = step
			note.pitch_pos = pitch_tap.shift_register:wrap_loop_pos(pitch_pos)
			note.pitch = pitch
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
	local prev_gate = false
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
		local note_edit_dim = ((has_pitch_edits and note.step <= 0) or (has_mod_edits and note.step <= 0)) and 1 or 0
		local note_level = 0
		-- set flash level, if this note was recently changed
		for w = 1, n_recent_writes do
			local write = recent_writes[w]
			if write.level > 0 then
				if write.shift_register == pitch_register and note.pitch_pos == pitch_register:wrap_loop_pos(write.pos) then
					note_level = math.max(note_level, write.level)
				elseif write.shift_register == mod_register and note.mod_pos == mod_register:wrap_loop_pos(write.pos) then
					note_level = math.max(note_level, write.level)
				end
			end
		end
		-- draw this note, including dotted lines for inactive notes in selected voices
		local outline_x = x
		-- if previous note was at the same `y` and its level was higher, don't redraw the leftmost
		-- pixel of this note over it
		if y0 == y and (prev_level > note_level or (prev_gate and not gate)) then
			x = x + 1
		end
		if gate then
			-- solid line for active notes
			local note_y = y + 0.5
			-- outline
			if y0 == y then
				if not prev_gate and gate then
					screen.move(outline_x - 1, note_y)
				else
					screen.move(outline_x, note_y)
				end
			elseif math.abs(y0 - y) == 1 then
				-- when y0 and y are within 1 pixel of one another, draw a partial outline to prevent
				-- overlap with the previous note
				screen.move(outline_x - 1, note_y + (y - y0) * 0.5)
				screen.line_rel(outline_x + 1, 0)
				screen.level(0)
				screen.line_width(2)
				screen.stroke()
				screen.move(outline_x + 1, note_y)
			else
				screen.move(outline_x - 1, note_y)
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
		prev_gate = gate
	end
end

function draw_tap_equation(y, label, voice, tap, unit_multiplier, editing)
	local highlight_multiply = editing and edit_field == edit_field_multiply
	local highlight_direction = editing and edit_field == edit_field_direction
	local highlight_time = editing and edit_field == edit_field_time
	local highlight_rate = edit_field == edit_field_rate
	local highlight_jitter = edit_field == edit_field_jitter
	local highlight_scramble = editing and edit_field == edit_field_scramble
	local highlight_noise = editing and edit_field == edit_field_noise
	local highlight_bias = editing and edit_field == edit_field_bias
	local highlight_length = editing and edit_field == edit_field_length

	local multiply = tap.next_multiply
	local direction = tap.direction
	local ticks_per_shift = voice.ticks_per_shift
	local jitter = voice.next_jitter
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

	screen.level(highlight_direction and 15 or 3)
	if direction < 0 then
		screen.text('-')
	elseif highlight_direction then
		screen.text('+')
	end

	screen.level(highlight_time and 15 or 3)
	screen.text('t')

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

		draw_tap_equation(54, 'p', top_voice, top_voice.pitch_tap, 12, edit_both_taps or edit_tap == edit_tap_pitch)

		draw_tap_equation(62, 'g', top_voice, top_voice.mod_tap, 1, edit_both_taps or edit_tap == edit_tap_mod)

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
