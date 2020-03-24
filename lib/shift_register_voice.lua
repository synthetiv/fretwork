local random_queue_size = 127 -- prime, so SR loop and random queues are never in phase

local ShiftRegisterVoice = {}
ShiftRegisterVoice.__index = ShiftRegisterVoice

ShiftRegisterVoice.new = function(pos, shift_register)
	local voice = setmetatable({}, ShiftRegisterVoice)
	voice.transpose = 0
	voice.value = 0
	voice.value_quantized = 0
	voice.pos = pos
	voice.shift_register = shift_register
	voice.scramble = 0
	voice.direction = 1
	voice.random_index = 1
	voice.random_queue = {}
	for i = 1, random_queue_size do
		voice:set_random(i)
	end
	return voice
end

function ShiftRegisterVoice:get_random_index(i)
	local index = (self.random_index + i * self.direction - 1) % random_queue_size + 1
	return index
end

function ShiftRegisterVoice:set_random(i)
	self.random_queue[self:get_random_index(i)] = math.random() * 2 - 1
end

function ShiftRegisterVoice:get_random(i)
	return self.random_queue[self:get_random_index(i)]
end

function ShiftRegisterVoice:update_value()
	self.value = self:get(0)
end

function ShiftRegisterVoice:shift(d)
	self.random_index = (self.random_index + d * self.direction - 1) % random_queue_size + 1
	self.pos = self.shift_register:clamp_loop_pos(self.pos + d * self.direction)
	-- TODO: re-randomize a random value that isn't visible on screen
	-- (right now each voice just has a set of fixed random values, which is better than nothing but not ideal)
	self:update_value()
end

function ShiftRegisterVoice:get_pos(t)
	local random = self:get_random(t)
	return t * self.direction + self.pos + util.round(random * self.scramble)
end

function ShiftRegisterVoice:get(t)
	return self.shift_register:read_loop(self:get_pos(t)) + self.transpose
end

function ShiftRegisterVoice:get_path(start_offset, end_offset)
	local path = {}
	local length = end_offset - start_offset
	for n = 1, length do
		local pos = self:get_pos(start_offset + n)
		path[n] = {
			pos = pos,
			offset = self.shift_register:clamp_loop_offset(pos - self.shift_register.head),
			value = self:get(start_offset + n)
		}
	end
	return path
end

return ShiftRegisterVoice
