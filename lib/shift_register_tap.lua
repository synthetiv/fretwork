-------
-- a ShiftRegisterTap reads/writes to/from a ShiftRegister. it can be moved (or held static) either
-- along with or independently from its shift register, and read/write operations can be 'scrambled'
-- (index offset by a randomized amount), values offset by a constant 'bias' or random 'noise'.
-- @classmod ShiftRegisterTap
local ShiftRegisterTap = {}
ShiftRegisterTap.__index = ShiftRegisterTap

local RandomQueue = include 'lib/random_queue'

--- create a new ShiftRegisterTap
-- @param offset initial offset from loop start point
-- @param shift_register the ShiftRegister to read/write
ShiftRegisterTap.new = function(offset, shift_register, voice)
	local tap = setmetatable({}, ShiftRegisterTap)
	tap.pos = shift_register:get_loop_offset_pos(offset)
	tap.tick = 0
	tap.ticks_per_shift = 2
	tap.shift_register = shift_register
	tap.direction = 1
	tap.scramble = 0
	-- TODO: is there another way to handle noise/scramble that would:
	-- 1. handle loop length changes better? i.e. if you change the SR length and a note moves from
	-- point A on the screen to point B, the corresponding scramble/noise values move with it so that
	-- the voice path doesn't twitch & jump around?
	-- 2. really never repeat?
	tap.scramble_values = RandomQueue.new(131) -- prime length, so SR loop and random queues are rarely in phase
	tap.noise = 0 -- TODO: `next_noise`, quantization
	tap.noise_values = RandomQueue.new(137)
	tap.jitter = 0
	tap.jitter_values = RandomQueue.new(139)
	tap.next_bias = 0
	tap.bias = 0
	-- if this is the first tap created for this shift register, sync it (so SR always has a synced tap)
	if shift_register.sync_tap == nil then
		shift_register.sync_tap = tap
	end
	return tap
end

--- change the shift rate
-- @param direction shift direction, -1 or +1
-- @param ticks_per_shift the number of times `shift()` must be called for `pos` to change by +/-1
function ShiftRegisterTap:set_rate(direction, ticks_per_shift)
	-- maintain current fractional position as best you can
	self.tick = math.floor(self.tick * ticks_per_shift / self.ticks_per_shift)
	self.ticks_per_shift = ticks_per_shift
	self.direction = direction
end
	
--- get the length of a particular step in ticks
-- @param s steps from now
-- @return ticks per shift, potentially affected by jitter
function ShiftRegisterTap:get_step_length(s)
	local jitter = self.jitter_values:get(s * self.direction) * self.jitter
	local rate = self.ticks_per_shift * math.pow(2, jitter)
	return math.floor(rate + 0.5)
end

--- get the corresponding shift register step for a tick
-- @param t ticks from now
-- @return the difference between the current `pos` and `pos` `t` ticks from now
function ShiftRegisterTap:get_tick_step(t)
	-- `slowest_rate` ticks/shift won't be shifted by clock, so future == past == present
	if t == 0 or self.ticks_per_shift == slowest_rate then
		return 0
	end
	-- reduce `|t|` by adjacent step lengths (including the current one, which we may be partway
	-- through) until reducing further would hit 0
	local step = 0
	local step_length = 0
	local direction = 0
	if t > 0 then
		step_length = self:get_step_length(0) - self.tick
		direction = 1
	else
		step_length = self.tick + 1
		direction = -1
	end
	t = math.abs(t)
	while t >= step_length do
		step = step + direction
		t = t - step_length
		step_length = self:get_step_length(step)
	end
	return step
end

--- get the past/present/future value of `pos`
-- @param s steps from now
-- @return the value of `pos` in `s` steps, potentially affected by scramble
function ShiftRegisterTap:get_step_pos(s)
	local scramble_offset = util.round(self.scramble_values:get(s) * self.scramble)
	return s + self.pos + scramble_offset
end

--- get the past/present/future value of `pos`, by tick
-- @param t ticks from now
-- @return the value of `pos` in `s` steps, potentially affected by scramble
function ShiftRegisterTap:get_tick_pos(t)
	return self:get_step_pos(self:get_tick_step(t))
end

--- get a past/present/future shift register value
-- @param s steps from now
-- @return a value from the shift register, potentially offset by bias + noise
function ShiftRegisterTap:get_step_value(s)
	local noise_value = self.noise_values:get(s) * self.noise
	return self.shift_register:read(self:get_step_pos(s)) + noise_value + self.bias
end

--- get a past/present/future shift register value, by tick
-- @param t ticks from now
-- @return a value from the shift register, potentially offset by bias + noise
function ShiftRegisterTap:get_tick_value(t)
	return self:get_step_value(self:get_tick_step(t))
end

--- set a past/present/future shift register value, by step
-- @param t steps from now
-- @param value new value, will be offset by -(bias + noise) and written to scrambled/jittered index
function ShiftRegisterTap:set_step_value(s, value)
	local pos = self:get_step_pos(s)
	local noise_value = self.noise_values:get(s) * self.noise
	self.shift_register:write(pos, value - self.bias - noise_value)
end

--- set a past/present/future shift register value, by tick
-- @param t ticks from now
-- @param value new value, will be offset by -(bias + noise) and written to scrambled/jittered index
function ShiftRegisterTap:set_tick_value(t, value)
	self:set_step_value(self:get_tick_step(t), value)
end

--- apply the 'next' bias and offset values (this makes quantization of changes possible)
function ShiftRegisterTap:apply_edits()
	self.bias = self.next_bias
	if self.next_offset ~= nil then
		self.pos = self.shift_register:wrap_loop_pos(self.shift_register.loop_start + self.next_offset)
		self.next_offset = nil
	end
end

--- change `tick`, which may or may not change `pos`
-- @param d number of ticks to shift by
-- @param manual true if tap should always shift, even if it's 'stopped' (i.e. `ticks_per_shift` ==
-- `slowest_rate`); will be true when shift triggered by an encoder, false when triggered by clock
function ShiftRegisterTap:shift(d, manual)
	-- don't shift automatically if `slowest_rate` ticks/shift
	if not manual and self.ticks_per_shift == slowest_rate then
		return
	end
	local tick = self.tick + d
	local step_length = self:get_step_length(0)
	local synced = self.shift_register.sync_tap == self
	local direction = d > 0 and self.direction or -self.direction
	-- step as many times as we need to in order to get `tick` below the current step length
	-- note: this loop could, theoretically, repeat many times if jitter amount was very high and many
	-- jitter values in a row were < 0 (thus setting many steps' lengths to 0 ticks)
	while tick >= step_length do
		if synced then
			self.shift_register:shift(direction)
		end
		self.scramble_values:shift(direction)
		self.noise_values:shift(direction)
		self.jitter_values:shift(direction)
		self.pos = self.shift_register:wrap_loop_pos(self.pos + direction)
		self:apply_edits()
		tick = tick - step_length
		step_length = self:get_step_length(0)
	end
	self.tick = tick
end

return ShiftRegisterTap
