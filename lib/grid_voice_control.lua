local Control = include 'lib/grid_control'

local VoiceControl = setmetatable({}, Control)
VoiceControl.__index = VoiceControl

function VoiceControl.new(x, y, width, height, n_voices, voices, type)
	local control = setmetatable(Control.new(x, y, width, height), VoiceControl)
	control.n_voices = n_voices
	control.voices = voices
	control.voice_ys = {}
	control.y_voices = {}
	control.voice_params = {}
	control.taps = {}
	local voice_y_base = math.ceil((control.height - n_voices) / 2)
	for v = 1, n_voices do
		local y = voice_y_base + v
		control.voice_ys[v] = y
		control.y_voices[y] = v
		control.voice_params[v] = voices[v].params[type]
		control.taps[v] = voices[v][type .. '_tap']
	end
	return control
end

return VoiceControl
