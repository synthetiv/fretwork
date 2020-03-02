local ShiftRegister = {}
ShiftRegister.__index = ShiftRegister
ShiftRegister.buffer_size = 32 -- TODO: increase

ShiftRegister.new = function(length)
	local instance = setmetatable({}, ShiftRegister)
	instance.head = 1
	instance.buffer = {}
	for i = 1, instance.buffer_size do
		instance.buffer[i] = 0
	end
	instance.length = length
	instance.dirty = false
	return instance
end

function ShiftRegister:get_buffer_pos(offset)
	return (self.head + offset - 1) % self.buffer_size + 1
end

function ShiftRegister:clamp_loop_offset(offset)
	return (offset - 1) % self.length - self.length + 1
end

function ShiftRegister:get_loop_pos(offset)
	return self:get_buffer_pos(self:clamp_loop_offset(offset))
end

function ShiftRegister:shift(delta)
	-- TODO: wouldn't mind understanding better _why_ this works the way it does
	if delta > 0 then
		self:write_buffer_offset(0, self:read_buffer_offset(-self.length), true)
	end
	self.head = self:get_buffer_pos(delta)
	if delta < 0 then
		self:write_buffer_offset(-self.length, self:read_buffer_offset(0), true)
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
	offset = self:clamp_loop_offset(offset)
	self.length = self.length + 1
	-- replace values before the offset with later values
	self:shift_range(-self.length, offset - 1, 1)
end

function ShiftRegister:delete(offset)
	-- refuse to delete if the loop size is already at the minimum
	if self.length <= 2 then
		return
	end
	offset = self:clamp_loop_offset(offset)
	self.length = self.length - 1
	-- replace the offset value and everything before it with earlier values
	self:shift_range(-self.length, offset, -1)
end

function ShiftRegister:set_loop(offset, loop)
	self.length = #loop
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
