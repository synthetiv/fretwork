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
		local top_tap = self.taps[top_voice_index]
		step = step - top_tap.tick / top_tap:get_step_length(0)
	end
	return step
end

function OffsetRoll:get_key_level(x, y, v, step)
	local level = (not self.hold and step == 0) and 2 or 0
	local tap = self.taps[v]
	local top_tap = self.taps[top_voice_index] -- TODO: avoid global state
	-- TODO: is this useful if taps' SRs aren't the same?
	local top_pos = top_tap.shift_register:wrap_loop_pos(top_tap.pos + top_tap.tick / top_tap:get_step_length(0))
	local pos = tap.shift_register:wrap_loop_pos(tap.pos + tap.tick / tap:get_step_length(0))
	local diff = pos - top_pos
	step = tap.shift_register:wrap_loop_pos(step)
	diff = math.abs((step - diff + 1) % tap.shift_register.loop_length - 1)
	diff = math.min(1, 2.5 - diff * 4)
	if diff > 0 then
		return math.ceil(led_blend(level, get_voice_control_level(v, 3) * math.abs(diff)))
	end
	return level
end

return OffsetRoll
