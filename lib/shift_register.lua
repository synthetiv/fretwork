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
	instance.cursor = 0
	instance:set_length(length)
	instance.head = 1
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
		self:write_buffer_offset(self.end_offset + 1, self:read_buffer_offset(self.start_offset))
	end
	self.head = self:get_buffer_pos(delta)
	if delta < 0 then
		self:write_buffer_offset(self.start_offset, self:read_buffer_offset(self.end_offset + 1))
	end
	self:move_cursor(delta * -1)
	for i = 1, self.n_read_heads do
		self.read_heads[i]:move()
	end
end

function ShiftRegister:move_cursor(delta)
	self.cursor = self:clamp_loop_offset(self.cursor + delta)
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

function ShiftRegister:read_cursor()
	return self:read_loop_offset(self.cursor)
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

-- TODO: insert/delete (changing loop length)
function ShiftRegister:write_cursor(value)
	self:write_loop_offset(self.cursor, value)
end

function ShiftRegister:set_length(length)
	self.start_offset = math.ceil(length / -2) + 1
	self.end_offset = self.start_offset + length - 1
	self.length = length
	-- constrain cursor to new length
	self:move_cursor(0)
end

function ShiftRegister:set_contents(memory)
	-- TODO: do better
	self.memory = memory
	self.length = #memory
	-- constrain cursor & head to new length
	self.head = self:get_loop_pos(0)
	self:move_cursor(0)
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
