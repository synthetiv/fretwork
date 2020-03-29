local Control = {}
Control.__index = Control

function Control.new(x, y, width, height)
	local instance = {}
	instance.x = x
	instance.y = y
	instance.width = width
	instance.height = height
	instance.x2 = x + width - 1
	instance.y2 = y + height - 1
	instance.x_center = x + math.floor((width - 0.5) / 2)
	instance.y_center = y + math.floor((height - 0.5) / 2)
	return instance
end

function Control:get_key_id_coords(id)
	local x = id % self.width
	local y = math.floor((id - x) / self.width)
	return self.x + x, self.y + y
end

function Control:get_key_id(x, y)
	return (x - self.x) + (y - self.y) * self.width
end

function Control:should_handle_key(x, y)
	return x >= self.x and x <= self.x2 and y >= self.y and y <= self.y2
end

return Control
