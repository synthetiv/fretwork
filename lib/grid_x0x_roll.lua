local Control = include 'lib/grid_control'

local X0XRoll = setmetatable({}, Control)
X0XRoll.__index = X0XRoll

function X0XRoll.new(x, y, width, height, shift_register)
	local roll = setmetatable(Control.new(x, y, width, height), X0XRoll)
	roll.shift_register = shift_register
	roll.offset = 0
	return roll
end

function X0XRoll:shift(d)
	self.offset = self.offset + d
end

function X0XRoll:get_offset(x)
	return x - self.x_center + self.offset
end

function X0XRoll:draw(g)
	for x = self.x, self.x2 do
		for y = self.y, self.y2 do
			local value = self.shift_register:read_loop(self:get_offset(x))
			local level = math.floor(10 * value / 5)
			local bar_height = math.floor(self.height * value / 5)
			if self.y2 - y > bar_height then
				level = 0
			end
			g:led(x, y, level)
		end
	end
end

function X0XRoll:key(x, y, z)
	if z ~= 1 then
		return
	end
	if not self:should_handle_key(x, y) then
		return
	end
	local offset = self:get_offset(x)
	local value = 5 * (self.y2 - y) / self.height
	self.shift_register:write_loop(offset, value)
end

return X0XRoll
