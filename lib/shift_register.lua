-------
-- ShiftRegister implements series of `loop_length` values which can be read/written using
-- arbitrarily large positive or negative indices, as if they repeated infinitely.
-- `shift()` moves the loop start and end points, pushing the value that was previously at the start
-- of the loop onto the end of the loop, or vice versa.
-- `loop_length` can be changed at runtime, and increasing it will reintroduce values into the loop
-- that were previously pushed off the start or end.
-- @classmod ShiftRegister
local ShiftRegister = {}
ShiftRegister.__index = ShiftRegister

--- the size of the internal ring buffer used to store values
ShiftRegister.buffer_size = 128

--- create a new shift register
-- @param length loop length
-- @return the new shift register
ShiftRegister.new = function(length)
	local instance = setmetatable({}, ShiftRegister)
	instance.loop_start = 1 -- start point on an (effectively) infinite timeline
	instance.loop_length = length
	instance.buffer = {}
	for i = 1, instance.buffer_size do
		instance.buffer[i] = 0
	end
	instance.dirty = false
	instance.sync_tap = nil -- will be set when a new tap is created
	return instance
end

--- change the length of the loop 
-- @param new_length the new length
function ShiftRegister:set_length(new_length)
	if self.sync_tap.direction > 0 then
		-- when direction is positive, sync tap should be locked at the end of the loop, so move the
		-- start point instead of the end point
		self.loop_start = self.loop_start + self.loop_length - new_length
	end
	self.loop_length = new_length
	self.dirty = true
end

--- constrain a virtual index to a valid buffer index
-- @param pos an index in the virtual infinite buffer/timeline
-- @return a buffer index in the range [1, buffer_size]
function ShiftRegister:wrap_buffer_pos(pos)
	return (pos - 1) % self.buffer_size + 1
end

--- constrain a virtual index to the range between the loop points
-- @param pos an index in the virtual infinite buffer/timeline
-- @return a virtual index in the range [loop_start, loop_start + loop_length)
function ShiftRegister:wrap_loop_pos(pos)
	return (pos - self.loop_start) % self.loop_length + self.loop_start
end

--- convert a relative offset to a virtual index
-- @param offset an offset (positive or negative) from the loop start point
-- @return a virtual index in the range [loop_start, loop_start + loop_length)
function ShiftRegister:get_loop_offset_pos(offset)
	return self:wrap_loop_pos(self.loop_start + offset)
end

--- set the tap to which the shift register should sync, and sync to it
-- SR will immediately shift enough that the sync tap is placed at the loop end (if direction > 0)
-- or loop start (direction < 0), and then shift along with the sync tap whenever it shifts
-- @param tap a ShiftRegisterTap belonging to this shift register
function ShiftRegister:sync_to_tap(tap)
	local direction = tap.direction
	self.sync_tap = tap

	local delta = tap.pos - self.loop_start
	if direction > 0 then
		-- when direction is forward, we want the synced tap to be at the end of the loop -- which we
		-- can achieve by shifting one more step than is needed to line it up with the start
		delta = delta + 1
	end
	-- never shift by more than loop_length * direction
	-- (math.abs() is used here because shift() always shifts in the appropriate direction)
	delta = math.abs(delta % (self.loop_length * direction))

	-- shift until we've reached the correct position
	for s = 1, delta do
		self:shift(direction)
	end
end

--- move loop start + end points within the virtual buffer by +/-1
-- and replace loop contents with `next_loop`, if appropriate
-- @param delta amount to shift: -1 or +1
function ShiftRegister:shift(delta)

	-- if shifting forward, copy the value from the start of the old loop to the end of the new;
	-- if shifting backward, copy from old end to new start
	local copy_from = delta > 0 and 0 or -1
	local copy_to = delta > 0 and -1 or 0
	-- get value to copy
	local copy_value = self:read_offset(copy_from)
	-- move
	self.loop_start = self.loop_start + delta
	-- write directly to buffer to avoid setting `self.dirty`
	self.buffer[self:wrap_buffer_pos(self:get_loop_offset_pos(copy_to))] = copy_value

	-- if we have a new loop queued up, check whether it's time to replace the current loop yet
	if self.next_loop_insert_offset ~= nil then
		self.next_loop_insert_offset = (self.next_loop_insert_offset - delta) % self.loop_length
		if self.next_loop_insert_offset == 0 then
			-- it's time, let's go
			self:apply_next_loop()
		end
	end
end

--- read from the loop
-- @param pos a virtual index
-- @return a value from the loop
function ShiftRegister:read(pos)
	return self.buffer[self:wrap_buffer_pos(self:wrap_loop_pos(pos))]
end

--- write to the loop
-- @param pos a virtual index
-- @param value the new value
function ShiftRegister:write(pos, value)
	self.buffer[self:wrap_buffer_pos(self:wrap_loop_pos(pos))] = value
	self.dirty = true
end

--- read from the loop at an offset
-- @param offset offset from the loop start point
function ShiftRegister:read_offset(offset)
	return self.buffer[self:wrap_buffer_pos(self:get_loop_offset_pos(offset))]
end

--- write to the loop at an offset
-- @param offset offset from the loop start point
-- @param value the new value
function ShiftRegister:write_offset(offset, value)
	self.buffer[self:wrap_buffer_pos(self:get_loop_offset_pos(offset))] = value
	self.dirty = true
end

--- return a table of the entire current loop contents
-- @param offset an offset from the loop start point
-- @return a table of values, with the value found at `offset` at index 1, the value at `offset + 1`
-- at index 2, etc.
function ShiftRegister:get_loop(offset)
	local loop = {}
	for i = 1, self.loop_length do
		loop[i] = self:read_offset(offset + i - 1)
	end
	return loop
end

--- set the loop contents and length to match the provided table of values
-- @param offset an offset from the loop start point
-- @param loop a table of values to match the loop to
function ShiftRegister:set_loop(offset, loop)
	self:set_length(#loop)
	for i = 1, self.loop_length do
		self:write_offset(offset + i - 1, loop[i])
	end
	self.dirty = false -- assume the loop that's just been set has been saved somewhere
end

--- prepare a new loop to replace the current one at a defined point in time
-- @param offset when start point reaches this offset, the new loop will replace the current one
-- @param loop a table of values to match the loop to
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
