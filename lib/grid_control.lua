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
	return instance
end

function Control.get_key_id_coords(id)
	local x = (id - 1) % 16 + 1
	local y = math.floor((id - x) / 16)
	return x, y
end

function Control.get_key_id(x, y)
	return x + y * 16
end

function Control:should_handle_key(x, y)
	return x >= self.x and x <= self.x2 and y >= self.y and y <= self.y2
end

return Control
