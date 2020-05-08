local VoiceSliderBank = include 'lib/grid_voice_slider_bank'

local RegisterSelector = setmetatable({}, VoiceSliderBank)
RegisterSelector.__index = RegisterSelector

function RegisterSelector.new(x, y, width, height, n_voices, voices, type)
	local selector = setmetatable(VoiceSliderBank.new(x, y, width, height, n_voices, voices, 1, n_registers), RegisterSelector)
	local param = 'voice_%d_' .. type .. '_register'
	selector.on_select = function(v, r)
		params:set(string.format(param, v), r)
	end
	return selector
end

-- TODO: draw in center of grid, with toggles for inversion
-- function RegisterSelector:draw(g)
-- end

return RegisterSelector
