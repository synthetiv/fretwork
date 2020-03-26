local ShiftRegisterTap = include 'lib/shift_register_tap'
local RandomQueue = include 'lib/random_queue'

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
	voice.scramble = 0
	voice.random_queue = RandomQueue.new(127) -- prime length, so SR loop and random queues are rarely in phase
	return voice
end

function ShiftRegisterVoice:update_value()
	self.value_raw = self.tap:get(0) -- unquantized
	self.pitch = self.scale:get_nearest_mask_pitch(self.value_raw)
	self.value = self.scale:get(self.pitch)
end

function ShiftRegisterVoice:shift(d)
	self.random_queue:shift(d)
	self.tap:shift(d)
	self:update_value()
end

function ShiftRegisterVoice:get_pos(t)
	return t + self.pos + util.round(self.random_queue:get(t) * self.scramble)
end

function ShiftRegisterVoice:get(t)
	return self.tap:get(self:get_pos(t)) + self.transpose
end

function ShiftRegisterVoice:get_path(start_offset, end_offset)
	local path = {}
	local length = end_offset - start_offset
	for n = 1, length do
		local pos = self:get_pos(start_offset + n)
		path[n] = {
			pos = pos,
			offset = self.tap:get_loop_offset(pos),
			value = self:get(start_offset + n)
		}
	end
	return path
end

return ShiftRegisterVoice
