local Control = include 'lib/grid_control'

local X0XRoll = setmetatable({}, Control)
X0XRoll.__index = X0XRoll

function X0XRoll.new(x, y, width, height, voice)
	local roll = setmetatable(Control.new(x, y, width, height), X0XRoll)
	roll.voice = voice
	roll.tap = voice.mod_tap
	roll.hold = false
	roll.held_pos = 0
	return roll
end

function X0XRoll:get_offset(x)
	local offset = x - self.x_center
	if self.hold then
		offset = offset - self.tap.pos + self.held_pos
	end
	return self.tap.shift_register:clamp_loop_offset(offset)
end

function X0XRoll:set_hold(state)
	if state and not self.hold then
		self.held_pos = self.tap.pos
	end
	self.hold = state
end

function X0XRoll:toggle_hold()
	self:set_hold(not self.hold)
end

function X0XRoll:shift(d)
	self:set_hold(true)
	self.held_pos = self.held_pos + d
end

function X0XRoll:draw(g, head_level_on, head_level_off, level_on, level_off)
	-- TODO: animate 'catching up' with taps after hold is released
	for x = self.x, self.x2 do
		local offset = self:get_offset(x)
		local mod = self.voice:get_mod(offset)
		local level = level_off
		if mod > 0 then
			if offset == 0 then
				level = head_level_on
			else
				level = level_on
			end
		elseif offset == 0 then
			level = head_level_off
		end
		g:led(x, self.y, level)
	end
end

function X0XRoll:key(x, y, z)
	if z ~= 1 then
		return
	end
	if not self:should_handle_key(x, y) then
		return
	end
	self.voice:toggle_mod(self:get_offset(x))
end

return X0XRoll
