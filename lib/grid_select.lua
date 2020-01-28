local Control = include 'lib/grid_control'

local Select = {}
setmetatable(Select, Control)
Select.__index = Select

function Select.new(x, y, width, height)
	local instance = Control.new(x, y, width, height)
	setmetatable(instance, Select)
	instance.count = width * height
	instance.selected = 1
	return instance
end

function Select:get_key_option(x, y)
	return self:get_key_id(x, y) + 1
end

function Select:get_option_coords(option)
	return self:get_key_id_coords(option - 1)
end

function Select:has_option(option)
	return option >= 1 and option <= self.count
end

function Select:is_selected(option)
	return self.selected == option
end

function Select:key(x, y, z)
	if not self:should_handle_key(x, y) then
		return
	end
	if z == 1 then
		local option = self:get_key_option(x, y)
		self.selected = option
	end
end

function Select:draw(g, level_on, level_off)
	for option = 1, self.count do
		local x, y = self:get_option_coords(option)
		g:led(x, y, self:is_selected(option) and level_on or level_off)
	end
end

return Select
