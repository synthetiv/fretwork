local Roll = include 'lib/grid_roll'

local OffsetRoll = setmetatable({}, Roll)
OffsetRoll.__index = OffsetRoll

function OffsetRoll.new(x, y, width, height, n_voices, voices, type)
	local roll = setmetatable(Roll.new(x, y, width, height, n_voices, voices, type), OffsetRoll)
	return roll
end

-- TODO: jump to offset with key, shift + key sets scramble
-- TODO: shift with taps...?
-- TODO: draw based on difference between actual (wrapped) positions, then draw scramble

function OffsetRoll:get_voice_step(v, x)
	local step = x - self.x_center + self.voice_hold_steps[top_voice_index]
	if self.hold then
		step = step - taps[v].direction * top_voice.tick / top_voice:get_step_length(0) -- TODO: global
	end
	return step
end

function OffsetRoll:get_tap_pos(v)
	local tap = self.taps[v]
	local voice = self.voices[v]
	-- TODO: this still gets pretty weird when top voice rate is high and tap is retrograde, especially(?) when other voices have jitter
	return tap.shift_register:wrap_loop_pos(tap.pos + tap.direction * voice.tick / voice:get_step_length(0))
end

function OffsetRoll:draw_voice(g, v)
	local y = self.voice_ys[v]
	local voice = self.voices[v]
	local tap = self.taps[v]
	local pos = self:get_tap_pos(v)
	local diff = pos - self:get_tap_pos(top_voice_index)
	local scramble = tap.pos - tap:get_step_pos(0)
	for x = self.x, self.x2 do
		local level = (not self.hold and x == self.x_center) and 2 or 0
		local step = tap.shift_register:wrap_loop_pos(self:get_voice_step(v, x))
		local step_diff = math.abs((step - diff + 1) % tap.shift_register.loop_length - 1)
		step_diff = math.min(1, 2.5 - step_diff * 4)
		if step_diff > 0 then
			level = math.ceil(led_blend(level, get_voice_control_level(v, 3) * math.abs(step_diff)))
		end
		local scramble_diff = math.abs((step - diff - scramble + 1) % tap.shift_register.loop_length - 1)
		scramble_diff = math.min(1, 2.5 - scramble_diff * 4)
		if scramble_diff > 0 then
			level = math.ceil(led_blend(level, get_voice_control_level(v, 3) * math.abs(scramble_diff) * 0.5))
		end
		g:led(x, y, level)
	end
end

function OffsetRoll:on_step_key(x, y, v, step)
	local tap = self.taps[v]
	local voice = self.voices[v]
	if held_keys.shift then
		self.voice_params[v].scramble = math.abs(step)
	else
		local new_pos = self:get_tap_pos(top_voice_index) + step
		tap.pos = math.floor(new_pos)
		voice.tick = math.floor((new_pos % 1) * voice:get_step_length(0) + 0.5)
	end
end

function OffsetRoll:get_state()
	local state = {}
	local top_pos = self:get_tap_pos(top_voice_index)
	for v = 1, self.n_voices do
		local voice_state = {}
		local voice_params = self.voice_params[v]
		local tap = self.taps[v]
		voice_state.offset = self:get_tap_pos(v) - top_pos
		voice_state.scramble = voice_params.scramble
		state[v] = voice_state
	end
	return state
end

function OffsetRoll:set_state(state)
	local top_pos = self:get_tap_pos(top_voice_index)
	for v = 1, self.n_voices do
		local params = self.voice_params[v]
		local tap = self.taps[v]
		local voice = self.voices[v]
		local new_offset = state[v].offset
		tap.pos = math.floor(top_pos + new_offset)
		tap.tick = math.floor((new_offset % 1) * voice:get_step_length(0) + 0.5)
		params.scramble = state[v].scramble
	end
end

return OffsetRoll
