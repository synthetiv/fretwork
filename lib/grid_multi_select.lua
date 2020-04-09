local Select = include 'lib/grid_select'

local MultiSelect = setmetatable({}, Select)

MultiSelect.__index = MultiSelect

function MultiSelect.new(x, y, width, height)
	local instance = setmetatable(Select.new(x, y, width, height), MultiSelect)
	instance.held = {}
	instance.selected = {}
	instance.awaiting_double_click = false
	instance.double_click_metro = metro.init{
		time = 0.2,
		event = function()
			instance.awaiting_double_click = false
		end,
		count = 1
	}
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
	return self.selected[option]
end

function MultiSelect:key(x, y, z)
	if not self:should_handle_key(x, y) then
		return
	end
	local option = self:get_key_option(x, y)
	if z == 1 then
		if self:is_selected(option) and self.awaiting_double_click then
			self:reset(true)
			return
		elseif not self:is_held() then
			self:reset()
		end
		self.selected[option] = true
		self.awaiting_double_click = true
		self.double_click_metro:start()
	end
	self.held[option] = z == 1
end

return MultiSelect
