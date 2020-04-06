local ShiftRegister = {}
ShiftRegister.__index = ShiftRegister

ShiftRegister.buffer_size = 128
ShiftRegister.half_buffer_size = ShiftRegister.buffer_size / 2

ShiftRegister.new = function(length)
	local instance = setmetatable({}, ShiftRegister)
	instance.start = 1
	instance.buffer = {}
	for i = 1, instance.buffer_size do
		instance.buffer[i] = 0
	end
	instance:set_length(length)
	instance.dirty = false
	return instance
end

--- change the length of the loop 
function ShiftRegister:set_length(length)
	-- set loop length
	self.length = length
	-- set half length, used for clamp_loop_offset_bipolar (for human-friendly readouts)
	self.half_length = math.floor(length / 2)
	-- set 'virtual buffer' size. because the virtual buffer is evenly divisible by both buffer size
	-- and loop length, for any two points A and B in the virtual buffer, the distance from A to B,
	-- and the distance from B to A wrapping across the end of the virtual buffer, are equal modulo
	-- the loop length. without this, clamp_loop_pos() doesn't work consistently.
	self.virtual_size = length * self.buffer_size
end

--- constrain an absolute position to [1, buffer_size]
function ShiftRegister:clamp_buffer_pos(pos)
	return (pos - 1) % self.buffer_size + 1
end

--- constrain an absolute position to [1, virtual_size]
function ShiftRegister:clamp_virtual_pos(pos)
	return (pos - 1) % self.virtual_size + 1
end

--- constrain an absolute position to [start, end]
-- note that if start + length > virtual_size, end < start
function ShiftRegister:clamp_loop_pos(pos)
	return self:clamp_virtual_pos((pos - self.start) % self.length + self.start)
end

--- constrain a relative offset to the range [-floor(length/2), ceil(length/2)]
-- TODO: do you really need this...?
function ShiftRegister:clamp_loop_offset_bipolar(offset)
	return (offset + self.half_length) % self.length - self.half_length
end

--- convert a relative offset from the start point to an absolute position [start, end]
function ShiftRegister:get_loop_offset_pos(offset)
	-- return self.start + self:clamp_loop_offset(offset)
	return self:clamp_loop_pos(self.start + offset)
end

--- move loop start + end points within the virtual buffer by `delta`
-- and replace loop contents with `next_loop`, if appropriate
function ShiftRegister:shift(delta)
	if delta > 0 then
		-- if shifting forward, copy the value from the start of the old loop to the end of the new
		local carry = self:read_offset(0)
		self.start = self:clamp_virtual_pos(self.start + delta)
		self.buffer[self:clamp_buffer_pos(self:get_loop_offset_pos(-1))] = carry -- write directly to avoid setting `self.dirty`
	elseif delta < 0 then
		-- if shifting backward, copy the value from the end of the old loop to the start of the new
		local carry = self:read_offset(-1)
		self.start = self:clamp_virtual_pos(self.start + delta)
		self.buffer[self:clamp_buffer_pos(self:get_loop_offset_pos(0))] = carry
	end
	-- if we have a new loop queued up, check whether it's time to replace the current loop yet
	if self.next_loop_insert_offset ~= nil then
		self.next_loop_insert_offset = (self.next_loop_insert_offset - delta) % self.length
		if self.next_loop_insert_offset == 0 then
			-- it's time, let's go
			self:apply_next_loop()
		end
	end
end

--- read from the loop at an absolute position
function ShiftRegister:read(pos)
	-- return self.buffer[self:clamp_buffer_pos(self:clamp_loop_pos(pos) % self.length)]
	return self.buffer[self:clamp_buffer_pos(self:clamp_loop_pos(pos))]
end

--- write to the loop at an absolute position
function ShiftRegister:write(pos, value)
	-- self.buffer[self:clamp_buffer_pos(self:clamp_loop_pos(pos) % self.length)] = value
	self.buffer[self:clamp_buffer_pos(self:clamp_loop_pos(pos))] = value
	self.dirty = true
end

--- read from the loop at an offset from the start point
function ShiftRegister:read_offset(offset)
	return self.buffer[self:clamp_buffer_pos(self:get_loop_offset_pos(offset))]
end

--- write to the loop at an offset from the start point
function ShiftRegister:write_offset(offset, value)
	self.buffer[self:clamp_buffer_pos(self:get_loop_offset_pos(offset))] = value
	self.dirty = true
end

--- return a table of the entire current loop contents, starting at offset
function ShiftRegister:get_loop(offset)
	local loop = {}
	for i = 1, self.length do
		loop[i] = self:read_offset(offset + i - 1)
	end
	return loop
end

--- set the loop contents and length to match the provided table of values
-- TODO: do you need the offset? you aren't currently using it
function ShiftRegister:set_loop(offset, loop)
	self:set_length(#loop)
	for i = 1, self.length do
		self:write_offset(offset + i - 1, loop[i])
	end
	self.dirty = false -- assume the loop that's just been set has been saved somewhere
end

--- prepare a new loop to replace the current one once the start point reaches `offset`
function ShiftRegister:set_next_loop(offset, loop)
	self.next_loop_insert_offset = offset
	self.next_loop = loop
end

--- replace the current loop with the queued 'next' loop
function ShiftRegister:apply_next_loop()
	-- clear insert offset so we don't do this again
	self.next_loop_insert_offset = nil
	self:set_loop(0, self.next_loop)
end

return ShiftRegister
