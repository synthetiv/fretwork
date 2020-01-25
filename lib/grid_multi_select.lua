local Control = include 'lib/grid_control'

local MultiSelect = {}
setmetatable(MultiSelect, Control)
MultiSelect.__index = MultiSelect

function MultiSelect.new(x, y, height)
	local instance = Control.new(x, y, 1, height)
	instance.count = height
	instance.held = {}
	instance.selected = {}
	setmetatable(instance, MultiSelect)
	instance:reset()
	return instance
end

function MultiSelect:reset(selected)
	for i = 1, self.count do
		self.held[i] = false
		self.selected[i] = selected == true
	end
end

function MultiSelect:get_key_option(x, y)
	if not self:should_handle_key(x, y) then
		return 0
	end
	return y - self.y + 1
end

function MultiSelect:has_option(option)
	return option >= 1 and option <= self.count
end

function MultiSelect:is_held(option)
	if option == nil then
		for i = 1, self.count do
			if self.held[i] then
				return true
			end
		end
		return false
	end
	if not self:has_option(option) then
		return false
	end
	return self.held[option]
end

function MultiSelect:is_selected(option)
	if option == nil then
		for i = 1, self.count do
			if self:is_selected(i) then
				return true
			end
		end
		return false
	end
	if not self:has_option(option) then
		return false
	end
	return self.selected[option]
end

function MultiSelect:key(x, y, z)
	if not self:should_handle_key(x, y) then
		return
	end
	-- TODO: does this tap & hold selection method make sense, or would it feel more normal to select
	-- multiples using shift?
	local option = self:get_key_option(x, y)
	if z == 1 then
		if not self:is_held() then
			self:reset()
		end
		self.selected[option] = true
	end
	self.held[option] = z == 1
end

function MultiSelect:get_option_y(option)
	return self.y + option - 1
end

function MultiSelect:draw(g)
	for option = 1, self.count do
		g:led(self.x, self:get_option_y(option), self:is_selected(option) and 10 or 5)
	end
end

return MultiSelect
