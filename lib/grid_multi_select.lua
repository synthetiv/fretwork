local Select = include 'lib/grid_select'

local MultiSelect = {}
setmetatable(MultiSelect, Select)
MultiSelect.__index = MultiSelect

function MultiSelect.new(x, y, width, height)
	local instance = Select.new(x, y, width, height)
	setmetatable(instance, MultiSelect)
	instance.held = {}
	instance.selected = {}
	instance:reset()
	return instance
end

function MultiSelect:reset(selected)
	for i = 1, self.count do
		self.held[i] = false
		self.selected[i] = selected == true
	end
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

return MultiSelect
