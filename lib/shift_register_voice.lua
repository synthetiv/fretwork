local ShiftRegisterTap = include 'lib/shift_register_tap'
local X0XRoll = include 'lib/grid_control'

local function mod_to_gate(mod)
	return mod > 0.5
end

local ShiftRegisterVoice = {}
ShiftRegisterVoice.__index = ShiftRegisterVoice

ShiftRegisterVoice.new = function(pitch_pos, pitch_register, scale, mod_pos, mod_register)
	local voice = setmetatable({}, ShiftRegisterVoice)
	voice.active = true
	voice.next_active = true
	voice.sync = false
	voice.detune = 0
	voice.pitch_id = -1
	voice.pitch = 0
	voice.pitch_tap = ShiftRegisterTap.new(pitch_pos, pitch_register, voice)
	voice.scale = scale
	voice.mod = 0
	voice.mod_tap = ShiftRegisterTap.new(mod_pos, mod_register, voice)
	voice.gate = false
	return voice
end

function ShiftRegisterVoice:apply_edits()
	-- TODO: next_pitch
	self.active = self.next_active
	self.pitch_tap:apply_edits()
	self.mod_tap:apply_edits()
end

function ShiftRegisterVoice:update_values()
	self:apply_edits()
	local scale = self.scale
	local pitch = self.pitch_tap:get_step_value(0)
	local pitch_id = scale:get_nearest_mask_pitch_id(pitch)
	if pitch_id == -1 then
		pitch_id = scale:get_nearest_pitch_id(pitch)
	else
		pitch = scale.values[pitch_id]
	end
	self.pitch_id = pitch_id
	self.pitch = pitch + self.detune
	local mod = self.mod_tap:get_step_value(0)
	self.gate = mod_to_gate(mod)
	self.mod = mod
end

function ShiftRegisterVoice:shift(d)
	self.pitch_tap:shift(d)
	self.mod_tap:shift(d)
end

function ShiftRegisterVoice:get_step_gate(s)
	return mod_to_gate(self.mod_tap:get_step_value(s))
end

function ShiftRegisterVoice:get_tick_gate(t)
	return mod_to_gate(self.mod_tap:get_tick_value(t))
end

function ShiftRegisterVoice:set_step_gate(s, gate)
	self.mod_tap:set_step_value(s, gate and 1 or 0)
end

function ShiftRegisterVoice:set_tick_gate(t, gate)
	self.mod_tap:set_tick_value(t, gate and 1 or 0)
end

-- TODO: occasionally, thanks to a special coincidence of noise + bias values, this doesn't work...
function ShiftRegisterVoice:toggle_step_gate(s)
	self:set_step_gate(s, not self:get_step_gate(s))
end

function ShiftRegisterVoice:toggle_tick_gate(t)
	self:set_tick_gate(t, not self:get_tick_gate(t))
end

function ShiftRegisterVoice:initialize_path(length)
	local path = {}
	for n = 1, length do
		path[n] = {
			pitch = 0,
			pitch_pos = 0,
			mod = 0,
			mod_pos = 0,
			gate = false
		}
	end
	self.path = path
end

function ShiftRegisterVoice:update_path(start_offset, end_offset)
	local length = end_offset - start_offset
	local path = self.path
	local pitch_tap = self.pitch_tap
	local mod_tap = self.mod_tap
	for n = 1, length do
		local note = path[n]
		local offset = start_offset + n
		note.pitch = pitch_tap:get_tick_value(offset)
		note.pitch_pos = pitch_tap.shift_register:wrap_loop_pos(pitch_tap:get_tick_pos(offset))
		note.mod = mod_tap:get_tick_value(offset)
		note.mod_pos = mod_tap.shift_register:wrap_loop_pos(mod_tap:get_tick_pos(offset))
		note.gate = mod_to_gate(note.mod)
	end
	return path
end

return ShiftRegisterVoice
