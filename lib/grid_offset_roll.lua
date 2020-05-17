local Roll = include 'lib/grid_roll'

local OffsetRoll = setmetatable({}, Roll)
OffsetRoll.__index = OffsetRoll

function OffsetRoll.new(x, y, width, height, n_voices, voices, type)
	local roll = setmetatable(Roll.new(x, y, width, height, n_voices, voices, type), OffsetRoll)
	return roll
end

-- TODO: this is... very confusing-looking
-- TODO: jump to offset with key, shift + key sets scramble
-- TODO: shift with taps...?

-- TODO: draw based on difference between actual (wrapped) positions, then draw scramble

function OffsetRoll:get_key_level(x, y, v, step)
	local tap = self.taps[v]
	local top_tap = self.taps[top_voice_index] -- TODO: avoid global state
	-- TODO: is this useful if taps' SRs aren't the same?
	local top_pos = top_tap.shift_register:wrap_loop_pos(top_tap.pos + top_tap.tick / top_tap:get_step_length(0))
	local pos = tap.shift_register:wrap_loop_pos(tap.pos + tap.tick / tap:get_step_length(0))
	local diff = pos - top_pos
	local half_length = tap.shift_register.loop_length / 2
	diff = math.floor((diff + half_length) % tap.shift_register.loop_length - half_length + 0.5)
	if step == diff then
		return math.ceil(get_voice_control_level(v, 3))
	end
	return 2
end

return OffsetRoll
