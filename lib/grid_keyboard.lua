local Control = include 'lib/grid_control'

local Keyboard = setmetatable({}, Control)
Keyboard.__index = Keyboard

local fourth_value = math.log(4/3) / math.log(2) -- for tuning rows to fourths
	
function Keyboard.new(x, y, width, height, scale)
	local instance = setmetatable(Control.new(x, y, width, height), Keyboard)
	instance.scale = scale
	instance.held_keys = {}
	instance.n_held_keys = 0
	instance.last_key = 0
	-- set offset interval per row, rather than calculating it dynamically, so that "open tunings" are possible
	instance.row_offsets = {}
	instance:tune()
	instance.octave = 0
	instance.held_octave_keys = {
		down = false,
		up = false
	}
	return instance
end

function Keyboard:tune()
	local root_value = self.scale.values[self.scale.center_pitch_id]
	local fourth_pitch_id = self.scale:get_nearest_pitch_id(root_value + fourth_value)
	local fourth = self.scale:get_class(fourth_pitch_id) - 1
	local half_scale = math.floor(self.scale.length / 2 + 0.5)
	for row = self.y, self.y2 do
		self.row_offsets[row] = self.scale.center_pitch_id + (self.y_center - row) * fourth + half_scale
	end
end

function Keyboard:get_key_pitch_id(x, y)
	if not self:should_handle_key(x, y) then
		return nil
	end
	return x - self.x_center + self.row_offsets[y] + self.octave * self.scale.length
end

function Keyboard:get_key_id_pitch_id(id)
	local x, y = self:get_key_id_coords(id)
	if not self:should_handle_key(x, y) then
		return nil
	end
	local pitch_id = self:get_key_pitch_id(x, y)
	return pitch_id
end

function Keyboard:get_last_pitch_id()
	return self:get_key_id_pitch_id(self.last_key)
end

function Keyboard:get_last_value()
	return self.scale.values[self:get_last_pitch_id()]
end

function Keyboard:key(x, y, z)
	if not self:should_handle_key(x, y) then
		return
	end
	if self:is_octave_key(x, y) then
		self:octave_key(x, y, z)
		return
	end
	self:note_key(x, y, z)
end

function Keyboard:note(x, y, z)
	if not self:should_handle_key(x, y) then
		return
	end
	local key_id = self:get_key_id(x, y)
	local held_keys = self.held_keys
	local n_held_keys = self.n_held_keys
	local last_key = self.last_key
	if z == 1 then
		-- key pressed: add this key to held_keys
		n_held_keys = n_held_keys + 1
		held_keys[n_held_keys] = key_id
		last_key = key_id
	else
		if held_keys[n_held_keys] == key_id then
			-- most recently held key released: remove it from held_keys
			held_keys[n_held_keys] = nil
			n_held_keys = n_held_keys - 1
			if n_held_keys > 0 then
				last_key = held_keys[n_held_keys]
			end
		else
			-- other key released: find it in held_keys, remove it, and shift other values down
			local found = false
			for i = 1, n_held_keys do
				if held_keys[i] == key_id then
					found = true
				end
				if found then
					held_keys[i] = held_keys[i + 1]
				end
			end
			-- decrement n_held_keys only after we've looped over all held_keys table values, and only if
			-- we found the key in held_keys (which won't be the case if a key was held while switching
			-- the active keyboard, or a key on the pitch keyboard was held before holding shift)
			if found then
				n_held_keys = n_held_keys - 1
			end
		end
	end
	self.n_held_keys = n_held_keys
	self.last_key = last_key
end

function Keyboard:reset()
	self.held_keys = {}
	self.n_held_keys = 0
	self.held_octave_keys.down = false
	self.held_octave_keys.up = false
end

function Keyboard:is_key_held(x, y)
	local key_id = self:get_key_id(x, y)
	local held_keys = self.held_keys
	for i = 1, self.n_held_keys do
		if held_keys[i] == key_id then
			return true
		end
	end
	return false
end

function Keyboard:is_key_last(x, y)
	return self:get_key_id(x, y) == self.last_key
end

function Keyboard:draw(g)
	for x = self.x, self.x2 do
		for y = self.y, self.y2 do
			if self:is_octave_key(x, y) then
				g:led(x, y, 0) -- clear space around octave keys
			else
				local n = self:get_key_pitch_id(x, y)
				g:led(x, y, self:get_key_level(x, y, n))
			end
		end
	end
	-- draw octave keys
	local down_level = self.held_octave_keys.down and 7 or 2
	local up_level = self.held_octave_keys.up and 7 or 2
	g:led(self.x2 - 1, self.y, math.min(15, math.max(0, down_level - math.min(self.octave, 0))))
	g:led(self.x2, self.y, math.min(15, math.max(0, up_level + math.max(self.octave, 0))))
end

function Keyboard:is_pitch_id_in_center_octave(pitch_id)
	local center_pitch_id = self.scale.center_pitch_id
	return pitch_id >= center_pitch_id and pitch_id <= center_pitch_id + scale.length
end

function Keyboard:is_octave_key(x, y)
	return y <= self.y + 1 and x >= self.x2 - 2
end

function Keyboard:octave_key(x, y, z)
	local d = 0
	if y == self.y then
		if x == self.x2 then
			self.held_octave_keys.up = z == 1
			d = 1
		elseif x == self.x2 - 1 then
			self.held_octave_keys.down = z == 1
			d = -1
		end
	end
	if self.held_octave_keys.up and self.held_octave_keys.down then
		self.octave = 0
	elseif z == 1 then
		self.octave = self.octave + d
	end
end

-- this method can be redefined on the fly
function Keyboard:get_key_level(x, y, n)
	return 0
end

return Keyboard
