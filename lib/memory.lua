local Memory = {}
Memory.__index = Memory

local n_memory_slots = 16

Memory.new = function()
	local mem = {}
	mem.n_slots = n_memory_slots
	mem.slots = {}
	for i = 1, n_memory_slots do
		mem.slots[i] = {}
	end
	-- TODO: multi selects for 'pattern chaining'... or maybe pattern_time
	mem.selector = Select.new(1, 3, 4, 4)
	mem.selector.on_select = function(s)
		if held_keys.shift then -- TODO: any way around this use of global state?
			mem:save(mem.slots[s], s)
		else
			mem:recall(mem.slots[s])
		end
		mem.dirty = false
	end
	return mem
end

function Memory:recall_slot(s)
	self:recall(self.slots[s])
	self.dirty = false
end

function Memory:draw(g)
	self.selector:draw(g)
end

return Memory
