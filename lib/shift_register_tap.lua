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
	
--- scale a time offset in ticks to a number of shift register 'steps'
-- @param t ticks from now
-- @return the difference between the current `pos` and `pos` `t` ticks from now
function ShiftRegisterTap:get_offset(t)
	-- `slowest_rate` ticks/shift won't be shifted by clock, so future == past == present
	if t == 0 or self.ticks_per_shift == slowest_rate then
		return 0
	end
	-- TODO: this seems brutish, can't you do a nice calculus here or something instead?
	local offset = 0
	local tick = self.tick
	local increment = t > 0 and 1 or -1
	local rate = self:get_rate(offset)
	while t ~= 0 do
		t = t - increment
		tick = tick + increment
		if tick >= rate then
			offset = offset + self.direction
			rate = self:get_rate(offset)
			tick = 0
		elseif tick < 0 then
			offset = offset - self.direction
			rate = self:get_rate(offset)
			tick = rate - 1
		end
	end
	return offset
end

-- TODO: this has a tendency to slow things down rather than speed them up...
-- it should also probably be possible to completely skip a step? maybe?
-- or maybe I should just make it additive rather than exponential
function ShiftRegisterTap:get_rate(o)
	local jitter = self.jitter_values:get(o * self.direction) * self.jitter
	local rate = self.ticks_per_shift + jitter
	return math.max(1, math.floor(rate + 0.5))
end

--- get the past/present/future value of `pos`
-- @param t ticks from now
-- @return the value of `pos` in `t` ticks, potentially scrambled if `scramble` > 0
function ShiftRegisterTap:get_pos(t)
	t = self:get_offset(t)
	local scramble_offset = util.round(self.scramble_values:get(t) * self.scramble)
	return t + self.pos + scramble_offset
end

--- get a past/present/future shift register value
-- @param t ticks from now
-- @return a value from the shift register, offset by bias + noise, if applicable
function ShiftRegisterTap:get(t)
	local pos = self:get_pos(t)
	local noise_value = self.noise_values:get(self:get_offset(t)) * self.noise
	return self.shift_register:read(pos) + noise_value + self.bias
end

--- apply the 'next' bias and offset values (this makes quantization of changes possible)
function ShiftRegisterTap:apply_edits()
	self.bias = self.next_bias
	if self.next_offset ~= nil then
		self.pos = self.shift_register:wrap_loop_pos(self.shift_register.loop_start + self.next_offset)
		self.next_offset = nil
	end
end

--- change `tick` and/or `pos`
-- @param d number of ticks to shift by
-- @param manual true if tap should always shift, even if it's 'stopped' (i.e. `ticks_per_shift` ==
-- `slowest_rate`); will be true when shift triggered by an encoder, false when triggered by clock
function ShiftRegisterTap:shift(d, manual)
	-- don't shift automatically if `slowest_rate` ticks/shift
	if not manual and self.ticks_per_shift == slowest_rate then
		return
	end
	local rate = self:get_rate(0)
	self.tick = self.tick + d
	d = math.floor(self.tick / rate) * self.direction
	if d ~= 0 then
		if self.shift_register.sync_tap == self then
			self.shift_register:shift(d)
		end
		self.scramble_values:shift(d)
		self.noise_values:shift(d)
		self.jitter_values:shift(d)
		self.pos = self.shift_register:wrap_loop_pos(self.pos + d)
		self:apply_edits()
	end
	self.tick = self.tick % rate
end

--- set a past/present/future shift register value
-- @param t ticks from now
-- @param value new value, will be offset by -(bias + noise) and written to scrambled index
function ShiftRegisterTap:set(t, value)
	local pos = self:get_pos(t)
	local noise_value = self.noise_values:get(self:get_offset(t)) * self.noise
	self.shift_register:write(pos, value - self.bias - noise_value)
end

return ShiftRegisterTap
