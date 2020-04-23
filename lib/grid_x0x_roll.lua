local Control = include 'lib/grid_control'

local X0XRoll = setmetatable({}, Control)
X0XRoll.__index = X0XRoll

function X0XRoll.new(x, y, width, height, n_voices, voices)
	local roll = setmetatable(Control.new(x, y, width, height), X0XRoll)
	roll.n_voices = n_voices
	roll.voices = voices
	roll.hold = false
	roll.x_left = roll.x2 - 2
	roll.x_hold = roll.x2 - 1
	roll.x_right = roll.x2
	roll.held_keys = {
		left = false,
		right = false
	}
	roll.voice_hold_steps = {}
	roll.voice_ys = {}
	roll.y_voices = {}
	local voice_y_base = math.ceil((roll.height - n_voices) / 2)
	for v = 1, n_voices do
		local y = voice_y_base + v
		roll.voice_hold_steps[v] = 0
		roll.voice_ys[v] = y
		roll.y_voices[y] = v
		local on_shift = roll.voices[v].mod_tap.on_shift
		roll.voices[v].mod_tap.on_shift = function(d)
			on_shift(d)
			roll:shift_voice(v, -d)
		end
	end
	return roll
end

function X0XRoll:get_voice_step(v, x)
	return x - self.x_center + self.voice_hold_steps[v]
end

function X0XRoll:shift_voice(v, d)
	self.voice_hold_steps[v] = self.voice_hold_steps[v] + d
end

function X0XRoll:shift_all(d)
	for v = 1, self.n_voices do
		self:shift_voice(v, d)
	end
end

function X0XRoll:draw_voice(g, v)
	local y = self.voice_ys[v]
	local voice = self.voices[v]
	for x = self.x, self.x2 do
		local step = self:get_voice_step(v, x)
		local value = voice:get_step_gate(step)
		local level = self:get_key_level(x, y, v, step, value)
		g:led(x, y, level)
	end
end

function X0XRoll:smooth_hold_steps()
	-- if exiting hold state, smooth hold distance each frame
	local hold_steps = self.voice_hold_steps
	if not self.hold then
		for v = 1, self.n_voices do
			if hold_steps[v] ~= 0 then
				hold_steps[v] = math.floor(hold_steps[v] * 0.3)
				dirty = true
			end
		end
	end
end

function X0XRoll:draw(g)
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
	g:led(self.x_left, self.y2, self.held_keys.left and 7 or 2)
	g:led(self.x_hold, self.y2, self.hold and 2 or 7)
	g:led(self.x_right, self.y2, self.held_keys.right and 7 or 2)
end

function X0XRoll:key(x, y, z)
	if not self:should_handle_key(x, y) then
		return
	end
	if y == self.y2 and x == self.x_hold and z == 1 then
		self.hold = not self.hold
	elseif y == self.y2 and x == self.x_left then
		self.held_keys.left = z == 1
		if z == 1 then
			self.hold = true
			self:shift_all(-1)
		end
	elseif y == self.y2 and x == self.x_right then
		self.held_keys.right = z == 1
		if z == 1 then
			self.hold = true
			self:shift_all(1)
		end
	elseif z == 1 then
		local v = self.y_voices[y]
		if v ~= nil then
			local voice = self.voices[v]
			local step = self:get_voice_step(v, x)
			voice:toggle_step_gate(step)
			flash_write(write_type_mod, voice.mod_tap:get_step_pos(step))
		end
	end
end

return X0XRoll
