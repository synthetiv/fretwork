local RandomQueue = {}
RandomQueue.__index = RandomQueue

local random_queue_size = 128

RandomQueue.new = function()
	queue = setmetatable({}, RandomQueue)
	queue.index = 1
	queue.values = {}
	for i = 1, random_queue_size do
		queue:set(i)
	end
	return queue
end

function RandomQueue:get_index(i)
	local index = (self.index + i - 1) % random_queue_size + 1
	return index
end

function RandomQueue:set(i)
	self.values[self:get_index(i)] = math.random() * 2 - 1
end

function RandomQueue:get(i)
	return self.values[self:get_index(i)]
end

function RandomQueue:next()
	self.index = self.index + 1
	self:set(random_queue_size / 2) -- re-randomize an offscreen value
	return self:get(0)
end

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
	voice.random_queue = RandomQueue.new()
	return voice
end

function ShiftRegisterVoice:clock()
	local random = self.random_queue:next()
	self.note = self:get(0)
end

function ShiftRegisterVoice:get_offset(t)
	local random = self.random_queue:get(t)
	return t + util.round(random * self.scramble)
end

function ShiftRegisterVoice:get(t)
	return self.shift_register:read_loop_offset(self:get_offset(t)) + self.transpose
end

function ShiftRegisterVoice:get_path(start_offset, end_offset)
	local path = {}
	local length = end_offset - start_offset
	for n = 1, length do
		local offset = self.offset + start_offset + n
		path[n] = self:get(offset)
	end
	return path
end

return ShiftRegisterVoice
