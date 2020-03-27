local ShiftRegisterTap = include 'lib/shift_register_tap'

local ShiftRegisterVoice = {}
ShiftRegisterVoice.__index = ShiftRegisterVoice

ShiftRegisterVoice.new = function(pos, shift_register, scale)
	local voice = setmetatable({}, ShiftRegisterVoice)
	voice.transpose = 0
	voice.value_raw = 0
	voice.pitch = 1
	voice.value = 0
	voice.tap = ShiftRegisterTap.new(pos, shift_register)
	voice.scale = scale
	return voice
end

function ShiftRegisterVoice:update_value()
	self.value_raw = self:get(0) -- unquantized
	self.pitch = self.scale:get_nearest_mask_pitch(self.value_raw)
	self.value = self.scale:get(self.pitch)
end

function ShiftRegisterVoice:shift(d)
	self.tap:shift(d)
	self:update_value()
end

function ShiftRegisterVoice:get(t)
	return self.tap:get(t) + self.transpose
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
