local Select = include 'lib/grid_select'

local MultiSelect = setmetatable({}, Select)

MultiSelect.__index = MultiSelect

function MultiSelect.new(x, y, width, height)
	local instance = setmetatable(Select.new(x, y, width, height), MultiSelect)
	instance.held = {}
	instance.selected = {}
	instance.n_selected = 0
	instance.selection_order = {}
	for i = 1, instance.count do
		instance.selection_order[i] = i
	end
	instance.next = 1
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
		self.selected[i] = selected == true
	end
	if selected then
		self.n_selected = self.count
	else
		self.n_selected = 0
	end
	self.next = 1
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
		return self.n_selected > 0
	end
	return self.selected[option]
end

function MultiSelect:reorder(new_option, new_index)
	local removed = false
	local added = false
	local previous = 1
	for i = 1, self.count do
		if added and removed then
			self.next = self.next + 1
			return
		end
		local option = self.selection_order[i]
		if i == new_index then
			if not removed and option == new_option then
				-- new order is the same as the old; we're done
				added = true
				removed = true
			else
				-- insert + remember previous value
				previous = option
				self.selection_order[i] = new_option
				added = true
			end
		elseif added then
			local match = self.selection_order[i] == new_option
			-- replace with previous
			self.selection_order[i] = previous
			previous = option
			if match then
				-- we're done
				removed = true
			end
		elseif removed or self.selection_order[i] == new_option then
			-- replace with next
			self.selection_order[i] = self.selection_order[i + 1]
			removed = true
		end
		i = i + 1
	end
	self.next = self.next + 1
end

function MultiSelect:select(option)
	self:reorder(option, self.next)
	self.selected[option] = true
	self.n_selected = self.n_selected + 1
	self.awaiting_double_click = true
	self.double_click_metro:start()
end

function MultiSelect:key(x, y, z)
	if not self:should_handle_key(x, y) then
		return
	end
	local other_held = self:is_held()
	local option = self:get_key_option(x, y)
	self.held[option] = z == 1
	if z == 1 then
		if self.awaiting_double_click and option == self.selection_order[1] then
			self:reset(true)
			return
		elseif not other_held then
			self:reset()
		elseif other_held and self:is_selected(option) then
			return
		end
		self:select(option)
	end
end

return MultiSelect
