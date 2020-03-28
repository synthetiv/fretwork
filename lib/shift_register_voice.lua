local ShiftRegisterTap = include 'lib/shift_register_tap'

local ShiftRegisterVoice = {}
ShiftRegisterVoice.__index = ShiftRegisterVoice

ShiftRegisterVoice.new = function(pos, shift_register, scale)
	local voice = setmetatable({}, ShiftRegisterVoice)
	voice.transpose = 0
	voice.edit_transpose = 0
	voice.value_raw = 0
	voice.pitch_id = 1
	voice.value = 0
	voice.tap = ShiftRegisterTap.new(pos, shift_register)
	voice.scale = scale
	return voice
end

function ShiftRegisterVoice:apply_edits()
	self.transpose = self.edit_transpose
end

function ShiftRegisterVoice:update_value()
	self:apply_edits()
	self.value_raw = self:get(0) -- unquantized
	self.pitch_id = self.scale:get_nearest_mask_pitch_id(self.value_raw)
	if self.pitch_id == -1 then
		self.value = self.value_raw
		return
	end
	self.value = self.scale:get(self.pitch_id)
end

function ShiftRegisterVoice:shift(d)
	self.tap:shift(d)
end

function ShiftRegisterVoice:get(t)
	return self.tap:get(t) + self.transpose
end

function ShiftRegisterVoice:set(t, value)
	self.tap:set(t, value - self.transpose)
	if t == 0 then
		self:update_value()
	end
end

function ShiftRegisterVoice:get_path(start_offset, end_offset)
	local path = {}
	local length = end_offset - start_offset
	for n = 1, length do
		local pos = self.tap:get_pos(start_offset + n)
		path[n] = {
			pos = pos,
			offset = self.tap:get_loop_offset(pos),
			value = self:get(start_offset + n)
		}
	end
	return path
end

return ShiftRegisterVoice
