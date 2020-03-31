local ShiftRegister = {}
ShiftRegister.__index = ShiftRegister
-- TODO: the main advantage this design (variable length loop within a larger ring buffer) provides
-- is that when the loop length is changed, the newly 'revealed' values will be recently
-- played/heard/recorded ones; and adjusting length from long -> short -> long will eventually
-- reveal old values that weren't part of the short loop.
-- 1. is that even all that good?
-- 2. can something similar be achieved without all this headache-inducing ring buffer math?
-- a couple options:
-- A. variable length ring buffer, with magic 'virtual' values inserted when loop length changes (??)
--    (virtual values would get locked in when they were played, but could change until then --
--    allowing gradual changes in loop length)
-- B. 'real' shift register of variable length; calling 'shift()' really actually shifts values
--    adjusting length would change how values were read (i % min(new_length, old_length) or
--    something), until next shift which would lock in the new length
ShiftRegister.buffer_size = 128

local function gcd(a, b)
	if b == 0 then
		return a
	else
		return gcd(b, a % b)
	end
end

local function lcm(a, b)
	return a * b / gcd(a, b)
end

ShiftRegister.new = function(length)
	local instance = setmetatable({}, ShiftRegister)
	instance.head = 1
	instance.buffer = {}
	for i = 1, instance.buffer_size do
		instance.buffer[i] = 0
	end
	instance:set_length(length)
	instance.dirty = false
	return instance
end

function ShiftRegister:set_length(length)
	self.length = length
	self.length_lcm = lcm(self.length, self.buffer_size)
end

function ShiftRegister:get_buffer_pos(pos)
	return (pos - 1) % self.buffer_size + 1
end

function ShiftRegister:get_buffer_offset_pos(offset)
	return (self.head + offset - 1) % self.buffer_size + 1
end

function ShiftRegister:clamp_loop_pos(pos)
	local start = self.head - self.length
	return (pos - start - 1) % self.length + start + 1
end

function ShiftRegister:clamp_loop_offset(offset)
	return (offset - 1) % self.length - self.length + 1
end

function ShiftRegister:get_loop_pos(pos)
	return self:get_buffer_pos(self:clamp_loop_pos(pos))
end

function ShiftRegister:get_loop_offset_pos(offset)
	return self:get_buffer_offset_pos(self:clamp_loop_offset(offset))
end

function ShiftRegister:shift(delta)
	-- constrain head to the least common multiple of loop length and buffer size, because we don't
	-- want it to increase infinitely but simply constraining to loop length or buffer size causes
	-- discontinuities (loop appears to jump) when head position is wrapped
	self.head = (self.head + delta - 1) % self.length_lcm + 1
	if delta > 0 then
		-- if shifting forward, copy the value from before the start of the loop to the end
		self:write_buffer_offset(0, self:read_buffer_offset(-self.length), true)
	elseif delta < 0 then
		-- if shifting backward, copy the value from after the end of the loop to the start
		self:write_buffer_offset(-self.length + 1, self:read_buffer_offset(1), true)
	end
	if self.edit_loop_insert_offset ~= nil then
		self.edit_loop_insert_offset = self.edit_loop_insert_offset - delta
		if self.edit_loop_insert_offset == 0 then
			self:apply_edit_loop()
		end
	end
end

function ShiftRegister:read_absolute(pos)
	return self.buffer[pos]
end

function ShiftRegister:read_loop(pos)
	return self:read_absolute(self:get_loop_pos(pos))
end

function ShiftRegister:read_loop_offset(offset)
	return self:read_absolute(self:get_loop_offset_pos(offset))
end

function ShiftRegister:read_buffer_offset(offset)
	return self:read_absolute(self:get_buffer_offset_pos(offset))
end

function ShiftRegister:write_absolute(pos, value, clean)
	if self.buffer[pos] == value then
		return
	end
	self.buffer[pos] = value
	-- slightly weird hack since we use this method internally for looping: sometimes we're writing to
	-- _preserve_ the loop contents, in which case this doesn't 'dirty' the loop
	if not clean then
		self.dirty = true
	end
end

function ShiftRegister:write_loop(pos, value, clean)
	self:write_absolute(self:get_buffer_pos(self:clamp_loop_pos(pos)), value, clean)
end

function ShiftRegister:write_loop_offset(offset, value, clean)
	self:write_absolute(self:get_loop_offset_pos(offset), value, clean)
end

function ShiftRegister:write_buffer_offset(offset, value, clean)
	self:write_absolute(self:get_buffer_offset_pos(offset), value, clean)
end

function ShiftRegister:write_head(value, clean)
	self:write_absolute(self.head, value, clean)
end

function ShiftRegister:set_edit_loop(offset, loop)
	-- prepare a new loop to replace the current one once we reach a certain offset
	self.edit_loop_insert_offset = offset
	self.edit_loop = loop
end

function ShiftRegister:apply_edit_loop()
	self.edit_loop_insert_offset = nil
	self:set_loop(0, self.edit_loop)
end

function ShiftRegister:set_loop(offset, loop)
	self:set_length(#loop)
	for i = 1, self.length do
		self:write_loop_offset(offset + i - 1, loop[i])
	end
	self.dirty = false -- assume the loop that's just been set has been saved somewhere
end

function ShiftRegister:get_loop(offset)
	local loop = {}
	for i = 1, self.length do
		loop[i] = self:read_loop_offset(offset + i - 1)
	end
	return loop
end

return ShiftRegister
