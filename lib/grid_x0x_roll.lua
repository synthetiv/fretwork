local Control = include 'lib/grid_control'

local X0XRoll = setmetatable({}, Control)
X0XRoll.__index = X0XRoll

function X0XRoll.new(x, y, width, height, n_voices, voices)
	local roll = setmetatable(Control.new(x, y, width, height), X0XRoll)
	roll.n_voices = n_voices
	roll.voices = voices
	roll.hold = false
	roll.hold_distance = 0
	roll.x_left = roll.x2 - 2
	roll.x_hold = roll.x2 - 1
	roll.x_right = roll.x2
	roll.held_keys = {
		left = false,
		right = false
	}
	roll.voice_ys = {}
	roll.y_voices = {}
	local voice_y_base = math.ceil((roll.height - n_voices) / 2)
	for v = 1, n_voices do
		local y = voice_y_base + v
		roll.voice_ys[v] = y
		roll.y_voices[y] = v
	end
	return roll
end

function X0XRoll:get_offset(x)
	return x - self.x_center + self.hold_distance
end

function X0XRoll:set_hold(state)
	self.hold = state
end

function X0XRoll:toggle_hold()
	self:set_hold(not self.hold)
end

function X0XRoll:shift(d)
	self.hold_distance = self.hold_distance + d
end

function X0XRoll:draw_voice(g, v)
	local y = self.voice_ys[v]
	for x = self.x, self.x2 do
		local offset = self:get_offset(x)
		local value = self.voices[v]:get_mod(offset)
		local level = self:get_key_level(x, y, v, offset, value)
		g:led(x, y, level)
	end
end

function X0XRoll:smooth_hold_distance()
	-- if exiting hold state, smooth hold distance each frame
	if not self.hold and self.hold_distance ~= 0 then
		self.hold_distance = util.round(self.hold_distance / 3)
		dirty = true
	end
end

function X0XRoll:draw(g)
	-- clear margins and draw head indicator
	for x = self.x, self.x2 do
		local offset = self:get_offset(x)
		for y = self.y, self.y2 do
			if offset == 0 then
				g:led(x, y, 2)
			else
				g:led(x, y, 0)
			end
		end
	end
	-- voice values
	for v = 1, self.n_voices do
		self:draw_voice(g, v)
	end
	-- left/hold/right keys
	g:led(self.x_left, self.y2, self.held_keys.left and 7 or 2)
	g:led(self.x_hold, self.y2, self.hold and 2 or 7)
	g:led(self.x_right, self.y2, self.held_keys.right and 7 or 2)
end

function X0XRoll:key(x, y, z)
	if not self:should_handle_key(x, y) then
		return
	end
	if y == self.y2 and x == self.x_hold and z == 1 then
		self:toggle_hold()
	elseif y == self.y2 and x == self.x_left then
		self.held_keys.left = z == 1
		if z == 1 then
			self:set_hold(true)
			self:shift(-1)
		end
	elseif y == self.y2 and x == self.x_right then
		self.held_keys.right = z == 1
		if z == 1 then
			self:set_hold(true)
			self:shift(1)
		end
	elseif z == 1 then
		local v = self.y_voices[y]
		if v ~= nil then
			self.voices[v]:toggle_mod(self:get_offset(x))
		end
	end
end

return X0XRoll
