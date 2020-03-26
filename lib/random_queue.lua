local RandomQueue = {}
RandomQueue.__index = RandomQueue

RandomQueue.new = function(length)
	local queue = setmetatable({}, RandomQueue)
	queue.length = length
	queue.index = 1
	queue.values = {}
	for i = 1, queue.length do
		queue:set(i)
	end
	return queue
end

function RandomQueue:get_index(i)
	local index = (self.index + i - 1) % self.length + 1
	return index
end

function RandomQueue:set(i)
	self.values[self:get_index(i)] = math.random() * 2 - 1
end

function RandomQueue:get(i)
	return self.values[self:get_index(i)]
end

function RandomQueue:shift(d)
	-- TODO: re-randomize values that aren't currently "in use" (visible/audible)
	-- (right now each voice just has a set of fixed random values, which is better than nothing but not ideal)
	self.index = self:get_index(d)
end

return RandomQueue
