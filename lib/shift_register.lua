local ReadHead = {}
ReadHead.__index = ReadHead

ReadHead.new = function(offset, parent)
	local instance = {}
	setmetatable(instance, ReadHead)
	instance.offset = offset
	instance.offset_min = offset
	instance.offset_random = 0
	instance.parent = parent
	instance.pos = 1
	instance.active = false
	return instance
end

function ReadHead:move()
	local offset_random = math.min(self.offset_random, self.offset_min * -1)
	if offset_random > 0 then
		self.offset = self.offset_min + math.random(0, offset_random)
	else
		self.offset = self.offset_min
	end
	self.pos = self.parent:get_loop_pos(self.offset)
end


local ShiftRegister = {}
ShiftRegister.__index = ShiftRegister
ShiftRegister.n_read_heads = 4
ShiftRegister.buffer_size = 32

ShiftRegister.new = function(length)
	local instance = {}
	setmetatable(instance, ShiftRegister)
	instance.length = length
	instance.head = 1
	instance.cursor = 1
	instance.buffer = {}
	instance.read_heads = {}
	for i = 1, instance.buffer_size do
		instance.buffer[i] = 0
	end
	for i = 1, instance.n_read_heads do
		instance.read_heads[i] = ReadHead.new(i * 3, instance)
	end
	return instance
end

function ShiftRegister:get_loop_pos(offset)
	offset = offset % self.length
	-- TODO: is it better to return to the old paradigm where the loop ENDS at the head instead of starting there? can the loop be made to surround the head? would that even be good?
	return self:get_buffer_pos(offset)
end

function ShiftRegister:get_buffer_pos(offset)
	return (self.head + offset - 1) % self.buffer_size + 1
end

function ShiftRegister:shift(delta)
	-- TODO: wouldn't mind understanding better _why_ this works the way it does
	if delta > 0 then
		self:write_buffer_offset(self.length, self:read_head())
	end
	self.head = self:get_buffer_pos(delta)
	if delta < 0 then
		self:write_head(self:read_buffer_offset(self.length))
	end
	for i = 1, self.n_read_heads do
		self.read_heads[i]:move()
	end
end

function ShiftRegister:move_cursor(delta)
	self.cursor = self:get_loop_pos(self.cursor - self.head + delta)
end

function ShiftRegister:read_absolute(pos)
	return self.buffer[pos]
end

function ShiftRegister:read_head(head)
	if head == nil or head < 1 then
		return self:read_absolute(self.head)
	end
	return self:read_absolute(self.read_heads[head].pos)
end

function ShiftRegister:read_loop_offset(offset)
	return self:read_absolute(self:get_loop_pos(offset))
end

function ShiftRegister:read_buffer_offset(offset)
	return self:read_absolute(self:get_buffer_pos(offset))
end

function ShiftRegister:write_absolute(pos, value)
	self.buffer[pos] = value
end

function ShiftRegister:write_loop_offset(offset, value)
	self:write_absolute(self:get_loop_pos(offset), value)
end

function ShiftRegister:write_buffer_offset(offset, value)
	self:write_absolute(self:get_buffer_pos(offset), value)
end

function ShiftRegister:write_head(value)
	self:write_absolute(self.head, value)
end

function ShiftRegister:set_length(length)
	-- TODO: how do I make it feel/look as though the head is in the middle of the loop when adjusting length?
	self.length = length
end

function ShiftRegister:set_contents(memory)
	-- TODO: do better
	self.memory = memory
	self.length = #memory
	-- constrain cursor & head to new length
	self.cursor = self:get_loop_pos(self.cursor - self.head)
	self.head = self:get_loop_pos(0)
end

function ShiftRegister:get_contents()
	-- TODO: do better
	local memory = {}
	for i = 1, self.length do
		memory[i] = self:read_loop_offset(i - 1)
	end
	return memory
end

return ShiftRegister
