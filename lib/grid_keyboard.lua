local Control = include 'lib/grid_control'

local Keyboard = {}
setmetatable(Keyboard, Control)
Keyboard.__index = Keyboard

function Keyboard.new(x, y, width, height, scale)
	local instance = Control.new(x, y, width, height)
	instance.scale = scale
	instance.octave = 0
	instance.held_keys = {}
	instance.last_key = 0
	instance.gate = false
	-- set offset interval per row, rather than calculating it dynamically, so that "open tunings" are possible
	instance.row_offsets = {}
	for row = 1, height do
		instance.row_offsets[row] = (11 - row) * 5
	end
	-- this method can be redefined on the fly
	instance.get_key_level = function(x, y, n)
		return instance:is_white_key(n) and 2 or 0
	end
	setmetatable(instance, Keyboard)
	return instance
end

function Keyboard:get_key_note(x, y)
	-- TODO: update to return [-n, n] instead of [0, 2n]
	if not self:should_handle_key(x, y) then
		return nil
	end
	return x + 1 - self.x + self.row_offsets[y] + self.octave * self.scale.length
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

function Keyboard:draw(g)
	for x = self.x, self.x2 do
		for y = self.y, self.y2 do
			local n = self:get_key_note(x, y)
			g:led(x, y, self.get_key_level(x, y, n))
		end
	end
end

-- TODO: obviously this won't be accurate for non-12TET scales
function Keyboard:is_white_key(n)
	local pitch = (n - 1) % 12 + 1
	return (pitch == 2 or pitch == 4 or pitch == 5 or pitch == 7 or pitch == 9 or pitch == 11 or pitch == 12)
end

return Keyboard
