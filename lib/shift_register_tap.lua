local RandomQueue = include 'lib/random_queue'

local ShiftRegisterTap = {}
ShiftRegisterTap.__index = ShiftRegisterTap

ShiftRegisterTap.new = function(pos, shift_register)
	local tap = setmetatable({}, ShiftRegisterTap)
	tap.pos = pos
	tap.shift_register = shift_register
	tap.direction = 1
	tap.scramble = 0
	tap.random_queue = RandomQueue.new(127) -- prime length, so SR loop and random queues are rarely in phase
	return tap
end
	
function ShiftRegisterTap:get_scramble_offset(t)
	t = t * self.direction
	return util.round(self.random_queue:get(t) * self.scramble)
end

function ShiftRegisterTap:get_pos(t)
	return t * self.direction + self.pos + self:get_scramble_offset(t)
end

function ShiftRegisterTap:get(t)
	local pos = self:get_pos(t)
	local value = self.shift_register:read_loop(pos)
	return value
end

function ShiftRegisterTap:shift(d)
	d = d * self.direction
	self.random_queue:shift(d)
	self.pos = self.shift_register:clamp_loop_pos(self.pos + d)
end

function ShiftRegisterTap:get_loop_offset(t)
	t = t * self.direction
	return self.shift_register:clamp_loop_offset(t - self.shift_register.head)
end

return ShiftRegisterTap
