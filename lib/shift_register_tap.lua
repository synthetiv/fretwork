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
	tap.next_scramble = 0
	tap.scramble = 0
	tap.scramble_values = RandomQueue.new(131) -- prime length, so SR loop and random queues are rarely in phase
	tap.next_noise = 0
	tap.noise = 0
	tap.noise_values = RandomQueue.new(137)
	tap.next_jitter = 0
	tap.jitter = 0
	tap.jitter_values = RandomQueue.new(139)
	tap.next_bias = 0
	tap.bias = 0
	tap.next_multiply = 1
	tap.multiply = 1
	tap.next_value = nil
	tap.on_shift = function() end
	tap.on_write = function() end
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
	self.dirty = true
end
	
--- get the length of a particular step in ticks
-- @param s steps from now
-- @return ticks per shift, potentially affected by jitter
function ShiftRegisterTap:get_step_length(s)
	local jitter_amount = s > 0 and self.next_jitter or self.jitter
	local jitter = self.jitter_values:get(s * self.direction) * jitter_amount + 1
	local rate = self.ticks_per_shift * math.max(0, jitter)
	return math.floor(rate + 0.5)
end

--- get the corresponding shift register step for a tick
-- @param t ticks from now
-- @return the difference between the current `pos` and `pos` `t` ticks from now
-- @return the remainder in ticks, after reducing `t` by step lengths
function ShiftRegisterTap:get_tick_step(t)
	-- `slowest_rate` ticks/shift won't be shifted by clock, so future == past == present
	if self.ticks_per_shift == slowest_rate then
		return 0, self.tick
	end
	-- reduce `|t + tick|` by current + adjacent step lengths until reducing further would hit 0
	t = t + self.tick
	local step = 0
	local direction = t > 0 and 1 or -1
	-- if `t + tick` < 0, we've effectively already skipped the current step
	local step_length = t > 0 and self:get_step_length(0) or 1
	t = math.abs(t)
	while t >= step_length do
		t = t - step_length
		step = step + direction
		step_length = self:get_step_length(step)
	end
	if direction <= 0 then
		t = step_length - t - 1
	end
	return step * self.direction, t
end

--- get the past/present/future value of `pos`
-- @param s steps from now
-- @return the value of `pos` in `s` steps, potentially affected by scramble + jitter
function ShiftRegisterTap:get_step_pos(s)
	local scramble = s > 0 and self.next_scramble or self.scramble
	local scramble_offset = math.floor(self.scramble_values:get(s) * scramble + 0.5)
	return s + self.pos + scramble_offset
end

--- get the past/present/future value of `pos`, by tick
-- @param t ticks from now
-- @return the value of `pos` in `t` ticks, potentially affected by scramble + jitter
-- @return the step `t` ticks from now, potentially affected by scramble + jitter
function ShiftRegisterTap:get_tick_pos(t)
	local step = self:get_tick_step(t)
	return self:get_step_pos(step), step
end

--- get a past/present/future shift register value
-- @param s steps from now
-- @return a value from the shift register, potentially offset by bias + noise
-- @return bias + noise
-- @return bias
-- @return the position in the buffer at step `s`
function ShiftRegisterTap:get_step_value(s)
	local pos = self:get_step_pos(s)
	local bias = s > 0 and self.next_bias or self.bias
	local multiply = s > 0 and self.next_multiply or self.multiply
	local noise_amount = s > 0 and self.next_noise or self.noise
	local noisy_bias = self.noise_values:get(pos - self.pos) * noise_amount + bias
	return self.shift_register:read(pos) * multiply + noisy_bias, noisy_bias, bias, pos
end

--- get a past/present/future shift register value, by tick
-- @param t ticks from now
-- @return a value from the shift register, potentially offset by bias + noise
-- @return bias + noise
-- @return bias
-- @return the position in the buffer at step `s`
-- @return the step `t` ticks from now
function ShiftRegisterTap:get_tick_value(t)
	local pos, step = self:get_tick_pos(t)
	return self:get_step_value(step), pos, step
end

--- set a past/present/future shift register value, by step
-- @param t steps from now
-- @param value new value, will be offset by -(bias + noise) and written to scrambled/jittered index
function ShiftRegisterTap:set_step_value(s, value)
	local pos = self:get_step_pos(s)
	local bias = s > 0 and self.next_bias or self.bias
	local multiply = s > 0 and self.next_multiply or self.multiply
	local noise_amount = s > 0 and self.next_noise or self.noise
	local noisy_bias = self.noise_values:get(pos - self.pos) * noise_amount + bias
	self.shift_register:write(pos, (value - noisy_bias) / multiply)
	self.on_write(pos)
	self.dirty = true
end

--- set a past/present/future shift register value, by tick
-- @param t ticks from now
-- @param value new value, will be offset by -(bias + noise) and written to scrambled/jittered index
function ShiftRegisterTap:set_tick_value(t, value)
	self:set_step_value(self:get_tick_step(t), value)
end

--- apply the 'next' bias and offset values (this makes quantization of changes possible)
function ShiftRegisterTap:apply_edits()
	if self.next_jitter ~= self.jitter then
		self.jitter = self.next_jitter
		self.dirty = true
	end
	if self.next_scramble ~= self.scramble then
		self.scramble = self.next_scramble
		self.dirty = true
	end
	if self.next_noise ~= self.noise then
		self.noise = self.next_noise
		self.dirty = true
	end
	if self.next_bias ~= self.bias then
		self.bias = self.next_bias
		self.dirty = true
	end
	if self.next_multiply ~= self.multiply then
		self.multiply = self.next_multiply
		self.dirty = true
	end
	if self.next_offset ~= nil then
		self.pos = self.shift_register:wrap_loop_pos(self.shift_register.loop_start + self.next_offset)
		self.next_offset = nil
		self.dirty = true
	end
	if self.next_value ~= nil then
		self:set_step_value(0, self.next_value)
		self.next_value = nil
		self.dirty = true
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
	local synced = self.shift_register.sync_tap == self
	local direction = d > 0 and self.direction or -self.direction
	local steps, new_tick = self:get_tick_step(d)
	for s = 1, math.abs(steps) do
		if synced then
			self.shift_register:shift(direction)
		end
		self.scramble_values:shift(direction)
		self.noise_values:shift(direction)
		self.jitter_values:shift(direction)
		self.pos = self.shift_register:wrap_loop_pos(self.pos + direction)
		self:apply_edits()
		self.dirty = true
		self.on_shift(direction)
	end
	self.tick = new_tick
	self.dirty = true
end

--- check whether two steps correspond to the same position in the loop
-- @param a step A
-- @param b step B
-- @return true if loop positions match
function ShiftRegisterTap:check_step_identity(a, b)
	a = self.shift_register:wrap_loop_pos(self:get_step_pos(a))
	b = self.shift_register:wrap_loop_pos(self:get_step_pos(b))
	return a == b
end

return ShiftRegisterTap
