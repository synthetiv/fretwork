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
	local x = id % 16
	local y = math.floor(id / 16)
	return x, y
end

function Control.get_key_id(x, y)
	return x + y * 16
end

function Control:should_handle_key(x, y)
	return x >= self.x and x <= self.x2 and y >= self.y and y <= self.y2
end


local Keyboard = {}
setmetatable(Keyboard, Control)
Keyboard.__index = Keyboard

function Keyboard.new(x, y, width, height)
	local instance = Control.new(x, y, width, height)
	instance.scroll = 4
	instance.held_keys = {}
	instance.last_key = 0
	instance.gate = false
	setmetatable(instance, Keyboard)
	return instance
end

function Keyboard:get_key_note(x, y)
	-- TODO: update to return [-n, n] instead of [0, 2n]
	if not self:should_handle_key(x, y) then
		return nil
	end
	return x + 1 - self.x + (7 + self.scroll - y) * 5
end

function Keyboard:get_key_id_note(id)
	local x, y = self.get_key_id_coords(id)
	if not self:should_handle_key(x, y) then
		return nil
	end
	local note = self:get_key_note(x, y)
	return note
end

function Keyboard:get_last_note()
	return self:get_key_id_note(self.last_key)
end

function Keyboard:set_gate()
	self.gate = #self.held_keys > 0
end

function Keyboard:note(x, y, z)
	if not self:should_handle_key(x, y) then
		return
	end
	local key_id = self.get_key_id(x, y)
	if z == 1 then
		local n = self:get_key_note(x, y)
		table.insert(self.held_keys, key_id)
		self.last_key = key_id
	else
		if self.held_keys[#self.held_keys] == key_id then
			table.remove(self.held_keys)
			-- TODO: if scroll value has changed since previous key down, the key id and original note value won't match. we need to track both.
			if #self.held_keys > 0 then
				self.last_key = self.held_keys[#self.held_keys]
			end
		else
			for i = 1, #self.held_keys do
				if self.held_keys[i] == key_id then
					table.remove(self.held_keys, i)
				end
			end
		end
	end
	self:set_gate()
end

function Keyboard:reset()
	self.held_keys = {}
	self:set_gate()
end

function Keyboard:is_key_held(x, y)
	local key_id = self.get_key_id(x, y)
	for i = 1, #self.held_keys do
		if self.held_keys[i] == key_id then
			return true
		end
	end
	return false
end

function Keyboard:is_key_last(x, y)
	return self.get_key_id(x, y) == self.last_key
end


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


return {
	keyboard = Keyboard,
	multi_select = MultiSelect
}
