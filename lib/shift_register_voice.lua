-------
-- a ShiftRegisterVoice has two ShiftRegisterTaps, one for pitch and one for mod/gate. it can be
-- muted/unmuted and has callbacks for starting/stopping notes.
-- @classmod ShiftRegisterVoice
local ShiftRegisterVoice = {}
ShiftRegisterVoice.__index = ShiftRegisterVoice

local ShiftRegisterTap = include 'lib/shift_register_tap'
local RandomQueue = include 'lib/random_queue'

--- create a new ShiftRegisterVoice
-- @param pitch_pos initial position in pitch register
-- @param pitch_register a ShiftRegister to use for pitch values
-- @param scale pitch scale to use for quantization
-- @param mod_pos initial position in mod register
-- @param mod_register a ShiftRegister to use for gate values
ShiftRegisterVoice.new = function(pitch_pos, pitch_register, scale, mod_pos, mod_register)
	local voice = setmetatable({}, ShiftRegisterVoice)
	voice.path_dirty = true
	voice.active = true
	voice.next_active = true

	voice.detune = 0
	voice.pitch_id = -1
	voice.pitch = 0
	voice.bias_pitch_id = -1
	voice.noisy_bias_pitch_id = -1
	voice.next_bias_pitch_id = -1
	voice.pitch_tap = ShiftRegisterTap.new(pitch_pos, pitch_register, voice)
	voice.scale = scale

	voice.midi_note = 60 -- C
	voice.midi_bend = 8192 -- zero bend
	voice.last_midi_note = 60
	voice.midi_out_channel = 1
	voice.midi_out_bend_range = 2

	voice.mod = 0
	voice.mod_tap = ShiftRegisterTap.new(mod_pos, mod_register, voice)
	voice.gate = false

	voice.tick = 0
	voice.ticks_per_shift = 2
	voice.next_jitter = 0
	voice.jitter = 0
	voice.jitter_values = RandomQueue.new(139)

	voice.on_shift = function() end
	local on_tap_shift = function()
		voice:apply_edits()
		if not voice.skip_update then
			voice:update()
		end
		voice.on_shift()
	end
	voice.mod_tap.on_shift = on_tap_shift
	voice.pitch_tap.on_shift = on_tap_shift

	local note_on = function() end
	local note_off = function() end

	return voice
end

--- change the shift rate
-- @param ticks_per_shift the number of times `shift()` must be called for taps to shift
function ShiftRegisterVoice:set_rate(ticks_per_shift)
	-- maintain current fractional position as best you can
	self.tick = math.floor(self.tick * ticks_per_shift / self.ticks_per_shift)
	self.ticks_per_shift = ticks_per_shift
	self.path_dirty = true
end
	
--- get the length of a particular step in ticks
-- @param s steps from now
-- @return ticks per shift, potentially affected by jitter
function ShiftRegisterVoice:get_step_length(s)
	local jitter_amount = s > 0 and self.next_jitter or self.jitter
	local jitter = self.jitter_values:get(s) * jitter_amount + 1
	local rate = self.ticks_per_shift * math.max(0, jitter)
	return math.floor(rate + 0.5)
end

--- get the corresponding shift register step for a tick
-- @param t ticks from now
-- @return the difference between the current `pos` and `pos` `t` ticks from now
-- @return the remainder in ticks, after reducing `t` by step lengths
function ShiftRegisterVoice:get_tick_step(t)
	-- reduce `|t + tick|` by current + adjacent step lengths until reducing further would hit 0
	t = t + self.tick
	local step = 0
	local direction = t > 0 and 1 or -1
	-- if `t + tick` < 0, we've effectively already skipped the current step
	local step_length = t > 0 and self:get_step_length(0) or 1
	t = math.abs(t)
	while t >= step_length do
		t = t - step_length
		step = step + direction
		step_length = self:get_step_length(step)
	end
	if direction <= 0 then
		t = step_length - t - 1
	end
	return step, t
end

--- convert a value in the mod register to a boolean gate value
-- @param mod value to convert
-- @return true if gate is high/open
function ShiftRegisterVoice:mod_to_gate(mod)
	return mod > 0
end

--- apply 'next' state
function ShiftRegisterVoice:apply_edits()
	if self.next_jitter ~= self.jitter then
		self.jitter = self.next_jitter
		self.path_dirty = true
	end
	if self.next_active ~= self.active then
		self.active = self.next_active
		self.path_dirty = true
	end
end

--- if taps have changed, update path_dirty + saved pitch/gate values and call note callbacks
-- @param force_pitch_update force pitch update regardless of tap dirty state
-- @param force_mod_update force mod update regardless of tap dirty state
function ShiftRegisterVoice:update(force_pitch_update, force_mod_update)
	local pitch_tap = self.pitch_tap
	local pitch_change = false

	local mod_tap = self.mod_tap
	local gate_change = false

	-- calculate and update pitch
	if force_pitch_update or pitch_tap.dirty then
		local scale = self.scale
		local pitch, noisy_bias, bias = pitch_tap:get_step_value(0)
		local pitch_id = scale:get_nearest_mask_pitch_id(pitch)
		if pitch_id == -1 then
			pitch_id = scale:get_nearest_pitch_id(pitch)
		else
			pitch = scale.values[pitch_id]
		end
		pitch = pitch + self.detune
		local midi_note = math.floor(pitch * 12 + 0.5)
		local midi_bend = (8191 / self.midi_out_bend_range) * (pitch - midi_note / 12) + 8192 -- TODO: isn't that asymmetrical...???
		midi_note = midi_note + 60
		local noisy_bias_pitch_id = scale:get_nearest_pitch_id(noisy_bias)
		local bias_pitch_id = scale:get_nearest_pitch_id(bias)
		pitch_change = (self.pitch ~= pitch or self.noisy_bias_pitch_id ~= noisy_bias_pitch_id or self.bias_pitch_id ~= bias_pitch_id)
		self.pitch_id = pitch_id
		self.pitch = pitch
		self.noisy_bias_pitch_id = scale:get_nearest_pitch_id(noisy_bias)
		self.bias_pitch_id = scale:get_nearest_pitch_id(bias)
		self.midi_note = midi_note
		self.midi_bend = midi_bend
		pitch_tap.dirty = false
		self.path_dirty = true
	end

	-- calculate and update gate
	if force_mod_update or mod_tap.dirty then
		local mod = mod_tap:get_step_value(0)
		local gate = self:mod_to_gate(mod) and self.active
		gate_change = self.gate ~= gate
		self.gate = gate
		self.mod = mod
		mod_tap.dirty = false
		self.path_dirty = true
	end

	-- if current gate has changed, or gate is high and current pitch has changed, update output
	if gate_change or pitch_change then
		if self.gate then
			self.note_on(self.pitch)
		else
			self.note_off()
		end
	end
end

--- change `tick`, which may or may not change `pos`
-- @param d number of ticks to shift by
function ShiftRegisterVoice:shift(d)
	self.skip_update = true
	local steps, new_tick = self:get_tick_step(d)
	for s = 1, math.abs(steps) do
		self.jitter_values:shift(d)
		self.pitch_tap:shift(d)
		self.mod_tap:shift(d)
	end
	self.skip_update = false
	self.tick = new_tick
	self.path_dirty = true
	self:update()
end

--- get past/present/future gate state
-- @param s steps from now
function ShiftRegisterVoice:get_step_gate(s)
	return self:mod_to_gate(self.mod_tap:get_step_value(s))
end

--- set past/present/future gate state
-- @param s steps from now
-- @param gate new state
function ShiftRegisterVoice:set_step_gate(s, gate)
	self.mod_tap:set_step_value(s, gate and 1 or 0)
end

--- toggle past/present/future gate state
-- @param s steps from now
function ShiftRegisterVoice:toggle_step_gate(s)
	self:set_step_gate(s, not self:get_step_gate(s))
end

return ShiftRegisterVoice
