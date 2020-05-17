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
	tap.shift_register = shift_register
	tap.direction = 1
	tap.next_scramble = 0
	tap.scramble = 0
	tap.scramble_values = RandomQueue.new(131) -- prime length, so SR loop and random queues are rarely in phase
	tap.next_noise = 0
	tap.noise = 0
	tap.noise_values = RandomQueue.new(137)
	tap.next_bias = 0
	tap.bias = 0
	tap.next_multiply = 1
	tap.multiply = 1
	tap.next_value = nil
	tap.on_shift = function() end
	tap.on_write = function() end
	-- if this is the first tap created for this shift register, sync it (so SR always has a synced tap)
	if shift_register.sync_tap == nil then
		tap:sync()
	end
	return tap
end

--- get the past/present/future value of `pos`
-- @param s steps from now
-- @return the value of `pos` in `s` steps, potentially affected by scramble + jitter
function ShiftRegisterTap:get_step_pos(s)
	local scramble = s > 0 and self.next_scramble or self.scramble
	s = s * self.direction
	local scramble_offset = math.floor(self.scramble_values:get(s) * scramble + 0.5)
	return s + self.pos + scramble_offset
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

--- check whether this tap is synced to its shift register
-- @return true if synced, false if not
function ShiftRegisterTap:is_synced()
	return self.shift_register.sync_tap == self
end

--- shift tap position
-- @param d number of steps to shift by
function ShiftRegisterTap:shift(d)
	local synced = self:is_synced()
	local direction = d > 0 and self.direction or -self.direction
	for s = 1, math.abs(d) do
		if synced then
			self.shift_register:shift(direction)
		end
		self.scramble_values:shift(direction)
		self.noise_values:shift(direction)
		self.pos = self.shift_register:wrap_loop_pos(self.pos + direction)
		self:apply_edits()
		self.dirty = true
		self.on_shift(direction)
	end
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

--- sync this tap's shift register to this tap
function ShiftRegisterTap:sync()
	self.shift_register:sync_to_tap(self)
end

return ShiftRegisterTap
