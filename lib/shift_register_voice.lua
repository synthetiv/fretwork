local random_queue_size = 128

local ShiftRegisterVoice = {}
ShiftRegisterVoice.__index = ShiftRegisterVoice

ShiftRegisterVoice.new = function(offset, shift_register)
	local voice = setmetatable({}, ShiftRegisterVoice)
	voice.transpose = 0
	voice.note = 0
	voice.note_snapped = 0
	voice.offset = offset
	voice.shift_register = shift_register
	voice.scramble = 0
	voice.random_index = 1
	voice.random_queue = {}
	for i = 1, random_queue_size do
		voice:set_random(i)
	end
	return voice
end

function ShiftRegisterVoice:get_random_index(i)
	local index = (self.offset + self.random_index + i - 1) % random_queue_size + 1
	return index
end

function ShiftRegisterVoice:set_random(i)
	self.random_queue[self:get_random_index(i)] = math.random() * 2 - 1
end

function ShiftRegisterVoice:get_random(i)
	return self.random_queue[self:get_random_index(i)]
end

function ShiftRegisterVoice:next_random()
	self.random_index = self.random_index + 1
	self:set_random(self.offset + random_queue_size / 2)
	return self:get(0)
end

function ShiftRegisterVoice:clock()
	local random = self:next_random()
	self.note = self:get(0)
end

function ShiftRegisterVoice:get_offset(t)
	local random = self:get_random(t)
	return t + self.offset + util.round(random * self.scramble)
end

function ShiftRegisterVoice:get(t)
	return self.shift_register:read_loop_offset(self:get_offset(t)) + self.transpose
end

function ShiftRegisterVoice:get_path(start_offset, end_offset)
	local path = {}
	local length = end_offset - start_offset
	for n = 1, length do
		path[n] = {
			offset = self.shift_register:clamp_loop_offset(self:get_offset(start_offset + n)),
			value = self:get(start_offset + n)
		}
	end
	return path
end

return ShiftRegisterVoice
