local ShiftRegisterTap = include 'lib/shift_register_tap'
local X0XRoll = include 'lib/grid_control'

local ShiftRegisterVoice = {}
ShiftRegisterVoice.__index = ShiftRegisterVoice

ShiftRegisterVoice.new = function(pitch_pos, pitch_register, scale, mod_pos, mod_register)
	local voice = setmetatable({}, ShiftRegisterVoice)
	voice.active = true
	voice.next_active = true
	voice.detune = 0
	voice.transpose = 0
	voice.next_transpose = 0
	voice.pitch_id = -1
	voice.pitch = 0
	voice.pitch_tap = ShiftRegisterTap.new(pitch_pos, pitch_register)
	voice.scale = scale
	voice.mod = 0
	voice.mod_tap = ShiftRegisterTap.new(mod_pos, mod_register)
	return voice
end

function ShiftRegisterVoice:apply_edits()
	self.active = self.next_active
	self.transpose = self.next_transpose
	self.pitch_tap:apply_edits()
	self.mod_tap:apply_edits()
end

function ShiftRegisterVoice:update_values()
	self:apply_edits()
	local scale = self.scale
	local pitch = self:get_pitch(0)
	local pitch_id = scale:get_nearest_mask_pitch_id(pitch)
	if pitch_id == -1 then
		pitch_id = scale:get_nearest_pitch_id(pitch)
	else
		pitch = scale:get(pitch_id)
	end
	self.pitch_id = pitch_id
	self.pitch = pitch + self.detune
	self.mod = self:get_mod(0)
end

function ShiftRegisterVoice:shift_pitch(d)
	self.pitch_tap:shift(d)
end

function ShiftRegisterVoice:shift_mod(d)
	self.mod_tap:shift(d)
end

function ShiftRegisterVoice:shift(d)
	self:shift_pitch(d)
	self:shift_mod(d)
end

function ShiftRegisterVoice:get_pitch(t)
	return self.pitch_tap:get(t) + self.transpose
end

function ShiftRegisterVoice:get_mod(t)
	return self.mod_tap:get(t)
end

function ShiftRegisterVoice:set_pitch(t, pitch)
	self.pitch_tap:set(t, pitch - self.transpose)
	if t == 0 then
		self:update_values()
	end
end

function ShiftRegisterVoice:set_mod(t, mod)
	self.mod_tap:set(t, mod)
	if t == 0 then
		self:update_values()
	end
end

function ShiftRegisterVoice:toggle_mod(t)
	self:set_mod(t, self:get_mod(t) > 0 and 0 or 1)
	if t == 0 then
		self:update_values()
	end
end

function ShiftRegisterVoice:initialize_path(length)
	local path = {}
	for n = 1, length do
		path[n] = {
			pitch = 0,
			pitch_pos = 0,
			mod = 0,
			mod_pos = 0
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
		note.pitch = self:get_pitch(offset)
		note.pitch_pos = pitch_tap:get_pos(offset)
		note.mod = self:get_mod(offset)
		note.mod_pos = mod_tap:get_pos(offset)
	end
	return path
end

return ShiftRegisterVoice
