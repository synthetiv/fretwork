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

function RateSelector:draw(g)
	local x_center = self.x_center
	for v = 1, self.n_voices do
		local active = voices[v].active
		local slider = self.sliders[v]
		local x_rate, y = slider:get_option_coords(slider.selected)
		for x = self.x, self.x2 do
			local level = 1
			if x == x_rate then
				level = get_voice_control_level(v, 3)
			elseif x < x_rate and x >= x_center then
				level = get_voice_control_level(v, 1)
			elseif x > x_rate and x <= x_center then
				level = get_voice_control_level(v, 1)
			end
			g:led(x, y, math.ceil(level))
		end
	end
end

return RateSelector
