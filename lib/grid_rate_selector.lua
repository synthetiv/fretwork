local VoiceSliderBank = include 'lib/grid_voice_slider_bank'

local RateSelector = setmetatable({}, VoiceSliderBank)
RateSelector.__index = RateSelector

function RateSelector.new(x, y, width, height, n_voices, voices, type)
	local selector = setmetatable(VoiceSliderBank.new(x, y, width, height, n_voices, voices, 1, 15), RateSelector)
	local param = 'voice_%d_' .. type .. '_rate'
	selector.on_select = function(v, r)
		params:set(string.format(param, v), r)
	end
	return selector
end

-- TODO: draw fainter paths to center of grid, pulse with notes...
-- function RateSelector:draw(g)
-- end

return RateSelector
