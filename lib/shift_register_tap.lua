local ShiftRegisterTap = {}
ShiftRegisterTap.__index = ShiftRegisterTap

ShiftRegisterTap.new = function(pos, shift_register)
	local tap = setmetatable({}, ShiftRegisterTap)
	tap.value = 0
	tap.pos = pos
	tap.shift_register = shift_register
	tap.direction = 1
	return tap
end
	
function ShiftRegisterTap:get_pos(t)
	return t * self.direction + self.pos
end

function ShiftRegisterTap:get_loop_offset(t)
	return self.shift_register:clamp_loop_offset(t - self.shift_register.head)
end

function ShiftRegisterTap:get(t)
	local pos = self:get_pos(t)
	local value = self.shift_register:read_loop(pos)
	-- print('tap pos', pos)
	-- print('reg value', value)
	return value
end

function ShiftRegisterTap:update_value()
	self.value = self:get(0)
end

function ShiftRegisterTap:shift(d)
	self.pos = self.shift_register:clamp_loop_pos(self.pos + d * self.direction)
	self:update_value()
end

return ShiftRegisterTap
