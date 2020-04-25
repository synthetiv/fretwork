local RandomQueue = {}
RandomQueue.__index = RandomQueue

RandomQueue.new = function(length, range)
	local queue = setmetatable({}, RandomQueue)
	queue.length = length
	queue.range = range or 4
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

-- average of uniform random()s, for pseudo-gaussian noise
-- standard deviation = 0.5... I think
function RandomQueue:set(i)
	local rand = 0
	for i = 1, self.range do
		rand = rand + math.random()
	end
	rand = rand - self.range / 2
	self.values[self:get_index(i)] = rand
end

function RandomQueue:get(i)
	return self.values[self:get_index(i)]
end

function RandomQueue:shift(d)
	self.index = self:get_index(d)
end

return RandomQueue
