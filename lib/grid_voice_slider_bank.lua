local VoiceControl = include 'lib/grid_voice_control'
local Select = include 'lib/grid_select'

local VoiceSliderBank = setmetatable({}, VoiceControl)
VoiceSliderBank.__index = VoiceSliderBank

function VoiceSliderBank.new(x, y, width, height, n_voices, voices, min, max)
	local bank = setmetatable(VoiceControl.new(x, y, width, height, n_voices, voices), VoiceSliderBank)
	local length = max - min + 1
	bank.sliders = {}
	for v = 1, n_voices do
		local slider = Select.new(2, bank.voice_ys[v], length, 1)
		slider.on_select = function(option)
			bank.on_select(v, option + min - 1)
		end
		bank.sliders[v] = slider
	end
	bank.on_select = function() end
	return bank
end

function VoiceSliderBank:key(x, y, z)
	for v = 1, self.n_voices do
		local slider = self.sliders[v]
		if slider:should_handle_key(x, y) then
			slider:key(x, y, z)
			return
		end
	end
end

function VoiceSliderBank:draw(g)
	for v = 1, self.n_voices do
		local active = voices[v].active
		local slider = self.sliders[v]
		slider:draw(g, math.ceil(get_voice_control_level(v, 3)), 2)
	end
end

function VoiceSliderBank:reset()
	-- TODO: ?
end

return VoiceSliderBank
