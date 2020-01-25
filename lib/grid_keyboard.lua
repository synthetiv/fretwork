local Control = include 'lib/grid_control'

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

return Keyboard
