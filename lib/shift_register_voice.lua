-------
-- a ShiftRegisterVoice has two ShiftRegisterTaps, one for pitch and one for mod/gate. it can be
-- muted/unmuted and has callbacks for starting/stopping notes.
-- @classmod ShiftRegisterVoice
local ShiftRegisterVoice = {}
ShiftRegisterVoice.__index = ShiftRegisterVoice

local ShiftRegisterTap = include 'lib/shift_register_tap'
local X0XRoll = include 'lib/grid_control'

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
	voice.pitch_tap = ShiftRegisterTap.new(pitch_pos, pitch_register, voice)
	voice.scale = scale

	voice.mod = 0
	voice.mod_tap = ShiftRegisterTap.new(mod_pos, mod_register, voice)
	voice.gate = false

	local on_shift = function()
		voice:apply_edits()
		if not voice.skip_update then
			voice:update()
		end
	end
	voice.mod_tap.on_shift = on_shift
	voice.pitch_tap.on_shift = on_shift

	local note_on = function() end
	local note_off = function() end

	return voice
end

--- convert a value in the mod register to a boolean gate value
-- @param mod value to convert
-- @return true if gate is high/open
function ShiftRegisterVoice:mod_to_gate(mod)
	return mod > 0.5
end

--- apply 'next' active state
function ShiftRegisterVoice:apply_edits()
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
		pitch_change = self.pitch ~= pitch
		self.pitch_id = pitch_id
		self.pitch = pitch
		self.noisy_bias_pitch_id = scale:get_nearest_pitch_id(noisy_bias)
		self.bias_pitch_id = scale:get_nearest_pitch_id(bias)
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
	-- TODO: separate callback for when pitch changes while gate is low... for drawing?
	if gate_change or pitch_change then
		if self.gate then
			self.note_on(self.pitch)
		else
			self.note_off()
		end
	end
end

--- shift taps
-- @param d ticks to shift
function ShiftRegisterVoice:shift(d)
	self.skip_update = true
	self.pitch_tap:shift(d)
	self.mod_tap:shift(d)
	self.skip_update = false
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
-- TODO: occasionally, thanks to a special coincidence of noise + bias values, this doesn't work...
-- @param s steps from now
function ShiftRegisterVoice:toggle_step_gate(s)
	self:set_step_gate(s, not self:get_step_gate(s))
end

return ShiftRegisterVoice
