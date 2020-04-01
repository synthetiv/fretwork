local ShiftRegisterTap = include 'lib/shift_register_tap'

local ShiftRegisterVoice = {}
ShiftRegisterVoice.__index = ShiftRegisterVoice

ShiftRegisterVoice.new = function(pitch_pos, pitch_register, scale, mod_pos, mod_register)
	local voice = setmetatable({}, ShiftRegisterVoice)
	voice.detune = 0
	voice.transpose = 0
	voice.edit_transpose = 0
	voice.pitch_raw = 0
	voice.pitch_id = 1
	voice.pitch = 0
	voice.pitch_tap = ShiftRegisterTap.new(pitch_pos, pitch_register)
	voice.mod = 0
	voice.mod_tap = ShiftRegisterTap.new(mod_pos, mod_register)
	voice.scale = scale
	return voice
end

function ShiftRegisterVoice:apply_edits()
	self.transpose = self.edit_transpose
end

function ShiftRegisterVoice:update_values()
	self:apply_edits()
	self.pitch_raw, self.mod = self:get(0) -- unquantized
	self.pitch_id = self.scale:get_nearest_mask_pitch_id(self.pitch_raw)
	if self.pitch_id == -1 then
		self.pitch = self.pitch_raw + self.detune
		return
	end
	self.pitch = self.scale:get(self.pitch_id) + self.detune
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

function ShiftRegisterVoice:get(t)
	return self.pitch_tap:get(t) + self.transpose, self.mod_tap:get(t)
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

function ShiftRegisterVoice:get_path(start_offset, end_offset)
	local path = {}
	local length = end_offset - start_offset
	for n = 1, length do
		local pitch, mod = self:get(start_offset + n)
		path[n] = {
			pitch = pitch,
			mod = mod,
			pitch_pos = self.pitch_tap:get_pos(start_offset + n),
			mod_pos = self.mod_tap:get_pos(start_offset + n)
		}
	end
	return path
end

return ShiftRegisterVoice
