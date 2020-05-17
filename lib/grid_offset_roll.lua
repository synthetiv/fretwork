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
		step = step - top_voice.tick / top_voice:get_step_length(0) -- TODO: global
	end
	return step
end

function OffsetRoll:get_tap_pos(v)
	local tap = self.taps[v]
	local voice = self.voices[v]
	return tap.shift_register:wrap_loop_pos(tap.pos + voice.tick / voice:get_step_length(0))
end

function OffsetRoll:get_key_level(x, y, v, step)
	local level = (not self.hold and step == 0) and 2 or 0
	local tap = self.taps[v]
	local diff = self:get_tap_pos(v) - self:get_tap_pos(top_voice_index)
	step = tap.shift_register:wrap_loop_pos(step)
	diff = math.abs((step - diff + 1) % tap.shift_register.loop_length - 1)
	diff = math.min(1, 2.5 - diff * 4)
	if diff > 0 then
		return math.ceil(led_blend(level, get_voice_control_level(v, 3) * math.abs(diff)))
	end
	return level
end

function OffsetRoll:on_step_key(x, y, v, step)
	local tap = self.taps[v]
	local voice = self.voices[v]
	local top_tap = self.taps[top_voice_index]
	local new_pos = self:get_tap_pos(top_voice_index) + step
	tap.pos = math.floor(new_pos)
	voice.tick = math.floor((new_pos % 1) * voice:get_step_length(0) + 0.5)
end

return OffsetRoll
