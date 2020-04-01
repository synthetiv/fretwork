local Blinker = {}
Blinker.__index = Blinker

Blinker.new = function(time)
	local blinker = setmetatable({}, Blinker)
	blinker.metro = metro.init{
		time = time,
		count = 1,
		event = function()
			blinker.on = false
			dirty = true
		end
	}
	blinker.on = false
	return blinker
end

function Blinker:start()
	self.on = true
	-- self.metro:stop()
	self.metro:start()
end

function Blinker:stop()
	self.on = false
	self.metro:stop()
end

return Blinker
