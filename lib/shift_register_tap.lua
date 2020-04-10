local RandomQueue = include 'lib/random_queue'

local ShiftRegisterTap = {}
ShiftRegisterTap.__index = ShiftRegisterTap

ShiftRegisterTap.new = function(offset, shift_register)
	local tap = setmetatable({}, ShiftRegisterTap)
	tap.pos = shift_register:get_loop_offset_pos(offset)
	tap.shift_register = shift_register
	tap.direction = 1
	tap.scramble = 0
	tap.scramble_values = RandomQueue.new(131) -- prime length, so SR loop and random queues are rarely in phase
	tap.noise = 0
	tap.noise_values = RandomQueue.new(137)
	tap.next_bias = 0
	tap.bias = 0
	return tap
end
	
function ShiftRegisterTap:get_pos(t)
	t = t * self.direction
	local scramble_offset = util.round(self.scramble_values:get(t) * self.scramble)
	return t + self.pos + scramble_offset
end

function ShiftRegisterTap:get(t)
	local pos = self:get_pos(t)
	local noise_value = self.noise_values:get(t * self.direction) * self.noise
	return self.shift_register:read(pos) + noise_value + self.bias
end

function ShiftRegisterTap:apply_edits()
	self.bias = self.next_bias
	if self.next_offset ~= nil then
		self.pos = self.shift_register:clamp_loop_pos(self.shift_register.start + self.next_offset)
		self.next_offset = nil
	end
end

function ShiftRegisterTap:shift(d)
	d = d * self.direction
	self.scramble_values:shift(d)
	self.noise_values:shift(d)
	self.pos = self.shift_register:clamp_loop_pos(self.pos + d)
	self:apply_edits()
end

function ShiftRegisterTap:set(t, value)
	local pos = self:get_pos(t)
	self.shift_register:write(pos, value - self.bias)
end

function ShiftRegisterTap:get_offset()
	return self.shift_register:clamp_loop_offset_bipolar(self.pos - self.shift_register.start)
end

return ShiftRegisterTap
