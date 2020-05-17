local VoiceControl = include 'lib/grid_voice_control'

local Roll = setmetatable({}, VoiceControl)
Roll.__index = Roll

function Roll.new(x, y, width, height, n_voices, voices, type)
	local roll = setmetatable(VoiceControl.new(x, y, width, height, n_voices, voices, type), Roll)
	roll.hold = false
	roll.x_left = roll.x2 - 2
	roll.x_hold = roll.x2 - 1
	roll.x_right = roll.x2
	roll.held_keys = {
		left = false,
		right = false
	}
	roll.voice_hold_steps = {}
	for v = 1, n_voices do
		roll.voice_hold_steps[v] = 0
	end
	return roll
end

function Roll:get_voice_step(v, x)
	return x - self.x_center + math.floor(self.voice_hold_steps[v] + 0.5)
end

function Roll:shift_voice(v, d)
	if self.hold then
		self.voice_hold_steps[v] = self.voice_hold_steps[v] - d
	end
end

function Roll:shift_all(d)
	if not self.hold then
		return
	end
	for v = 1, self.n_voices do
		self:shift_voice(v, d)
	end
end

function Roll:draw_voice(g, v)
	local y = self.voice_ys[v]
	local voice = self.voices[v]
	for x = self.x, self.x2 do
		local step = self:get_voice_step(v, x)
		local level = self:get_key_level(x, y, v, step)
		g:led(x, y, level)
	end
end

function Roll:smooth_hold_steps()
	-- if exiting hold state, smooth hold distance each frame
	local hold_steps = self.voice_hold_steps
	if not self.hold then
		for v = 1, self.n_voices do
			if hold_steps[v] ~= 0 then
				if math.abs(hold_steps[v]) < 0.3 then
					hold_steps[v] = 0
				else
					hold_steps[v] = hold_steps[v] * 0.3
				end
				dirty = true
			end
		end
	end
end

function Roll:draw(g)
	-- clear margins and draw head indicator
	for x = self.x, self.x2 do
		local first_voice_step = self:get_voice_step(1, x)
		local last_voice_step = self:get_voice_step(self.n_voices, x)
		local head_indicator_level = not self.hold and 2 or 0
		for y = self.y, self.y2 do
			if y < self.voice_ys[1] then
				g:led(x, y, first_voice_step == 0 and head_indicator_level or 0)
			elseif y > self.voice_ys[self.n_voices] then
				g:led(x, y, last_voice_step == 0 and head_indicator_level or 0)
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
	g:led(self.x_left, self.y, self.held_keys.left and 7 or 2)
	g:led(self.x_hold, self.y, self.hold and 2 or 7)
	g:led(self.x_right, self.y, self.held_keys.right and 7 or 2)
end

function Roll:key(x, y, z)
	if y == self.y and x == self.x_hold and z == 1 then
		self.hold = not self.hold
	elseif y == self.y and x == self.x_left then
		self.held_keys.left = z == 1
		if z == 1 then
			self.hold = true
			self:shift_all(1)
		end
	elseif y == self.y and x == self.x_right then
		self.held_keys.right = z == 1
		if z == 1 then
			self.hold = true
			self:shift_all(-1)
		end
	elseif z == 1 then
		local v = self.y_voices[y]
		if v ~= nil then
			self:on_step_key(x, y, v, self:get_voice_step(v, x))
		end
	end
end

function Roll:reset()
	-- TODO: remove hold, do something so that it's not necessary to call smooth_hold_steps()?
	self.held_keys.left = false
	self.held_keys.right = false
end

return Roll
