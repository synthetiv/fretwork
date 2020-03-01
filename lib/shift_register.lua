local ShiftRegister = {}
ShiftRegister.__index = ShiftRegister
ShiftRegister.buffer_size = 32

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

function ShiftRegister:get_buffer_pos(offset)
	return (self.head + offset - 1) % self.buffer_size + 1
end

function ShiftRegister:clamp_loop_offset(offset)
	return (offset - self.start_offset) % self.length + self.start_offset
end

function ShiftRegister:get_loop_pos(offset)
	return self:get_buffer_pos(self:clamp_loop_offset(offset))
end

function ShiftRegister:shift(delta)
	-- TODO: wouldn't mind understanding better _why_ this works the way it does
	if delta > 0 then
		self:write_buffer_offset(self.end_offset + 1, self:read_buffer_offset(self.start_offset), true)
	end
	self.head = self:get_buffer_pos(delta)
	if delta < 0 then
		self:write_buffer_offset(self.start_offset, self:read_buffer_offset(self.end_offset + 1), true)
	end
end

function ShiftRegister:read_absolute(pos)
	return self.buffer[pos]
end

function ShiftRegister:read_loop_offset(offset)
	return self:read_absolute(self:get_loop_pos(offset))
end

function ShiftRegister:read_buffer_offset(offset)
	return self:read_absolute(self:get_buffer_pos(offset))
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

function ShiftRegister:write_loop_offset(offset, value, clean)
	self:write_absolute(self:get_loop_pos(offset), value, clean)
end

function ShiftRegister:write_buffer_offset(offset, value, clean)
	self:write_absolute(self:get_buffer_pos(offset), value, clean)
end

function ShiftRegister:write_head(value, clean)
	self:write_absolute(self.head, value, clean)
end

function ShiftRegister:shift_range(min, max, delta)
	if delta > 0 then
		for offset = min, max do
			self:write_buffer_offset(offset, self:read_buffer_offset(offset + delta))
		end
	elseif delta < 0 then
		for offset = max, min, -1 do
			self:write_buffer_offset(offset, self:read_buffer_offset(offset + delta))
		end
	end
end

function ShiftRegister:insert(offset)
	-- TODO: this is destructive when start/end offsets are at max, but could be made less so by increasing buffer size. is that worth it / interesting?
	-- keep track of which offset set_length() changes
	local old_start_offset = self.start_offset
	local old_end_offset = self.end_offset
	self:set_length(self.length + 1)
	if offset <= 0 then
		-- replace values before the offset with later values
		self:shift_range(self.buffer_size / -2, offset - 1, 1)
		-- if loop end has moved, then it has a garbage value -- replace with shifted value from before loop start
		if self.end_offset > old_end_offset then
			self:write_buffer_offset(self.end_offset, self:read_buffer_offset(self.start_offset - 1))
		end
	else
		-- replace values after the offset with earlier values
		self:shift_range(offset + 1, self.buffer_size / 2, -1)
		-- if loop start has moved, then it has a garbage value -- replace with shifted value from after loop end
		if self.start_offset < old_start_offset then
			self:write_buffer_offset(self.start_offset, self:read_buffer_offset(self.end_offset + 1))
		end
	end
end

function ShiftRegister:delete(offset)
	-- refuse to delete if the loop size is already at the minimum
	if self.length <= 2 then
		return
	end
	local old_start_offset = self.start_offset
	local old_end_offset = self.end_offset
	self:set_length(self.length - 1)
	if offset <= 0 then
		-- replace the offset value and everything before it with earlier values
		self:shift_range(self.buffer_size / -2, offset, -1)
		-- if loop start hasn't moved, then it has a garbage value -- replace with old loop end value
		if self.start_offset == old_start_offset then
			self:write_buffer_offset(self.start_offset, self:read_buffer_offset(self.end_offset + 1))
		end
	else
		-- replace the offset value and everything after it with later values
		self:shift_range(offset, self.buffer_size / 2, 1)
		-- if loop end hasn't moved, then it has a garbage value -- replace with old loop start value
		if self.end_offset == old_end_offset then
			self:write_buffer_offset(self.end_offset, self:read_buffer_offset(self.start_offset - 1))
		end
	end
end

-- TODO: maybe (?) don't bother with the symmetry thing
function ShiftRegister:set_length(length)
	if length < 2 or length > self.buffer_size or length == self.length then
		return
	end
	self.start_offset = math.ceil(length / -2) + 1
	self.end_offset = self.start_offset + length - 1
	self.length = length
	self.dirty = true
end

function ShiftRegister:set_loop(offset, loop)
	self:set_length(#loop)
	for i = 1, self.length do
		self:write_loop_offset(offset + i - 1, loop[i])
	end
	self.dirty = true
end

function ShiftRegister:get_loop(offset)
	local loop = {}
	for i = 1, self.length do
		loop[i] = self:read_loop_offset(offset + i - 1)
	end
	return loop
end

return ShiftRegister
