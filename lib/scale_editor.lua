local read_scala_file = include 'lib/scala'
local Ratio = include 'lib/ratio'

local ScaleEditor = {}
ScaleEditor.__index = ScaleEditor

function ScaleEditor.new(scale)
	local editor = setmetatable({}, ScaleEditor)
	editor.scale = scale
	editor.ratios = {}
	editor.span = Ratio.new(2)
	editor.root = Ratio.new()
	editor.pitches = {}
	editor.held_keys = {
		ctrl = false,
		lctrl = false,
		rctrl = false,
		shift = false,
		lshift = false,
		rshift = false,
		alt = false,
		lalt = false,
		ralt = false,
		numlock = false,
		plus = false
	}
	editor.class = 0
	editor.ratio = nil
	editor.input = ''
	editor.cursor = 1
	editor.num = 1
	editor.den = 1
	editor.focus_field = 0
	editor.n_fields = 2
	editor.on_update = function() end
	return editor
end

function ScaleEditor:select(class)
	if class ~= nil then
		self.class = class
	end
	self.input = ''
	self.cursor = 1
	self.focus_field = 0
	if self.class == 1 then
		self.ratio = self.span
	else
		self.ratio = self.ratios[self.class - 1]
	end
	self.num = self.ratio.num
	self.den = self.ratio.den
end

function ScaleEditor:select_pitch(pitch_id)
	self:select(self.scale:get_class(pitch_id))
end

function ScaleEditor:print_ratios()
	for r = 1, self.length do
		local ratio = (r == 1 and self.span or self.ratios[r - 1])
		local marker = (self:is_class_active(r) and '*' or ' ')
		print(string.format('%d. %s %s -> %s', r, marker, ratio, self.pitches[r]))
	end
end

local function sort_ratios(a, b)
	if a == nil then
		return false
	elseif b == nil then
		return true
	end
	return a < b
end

--- reduce & sort ratios, update scale values to match them
function ScaleEditor:update()

	local ratios = self.ratios
	local count = #ratios
	local span = self.span
	local root = self.root
	local pitches = self.pitches
	
	for r = 1, count do
		ratios[r]:reduce(span)
	end
	
	table.sort(ratios, sort_ratios)

	self.class = 1
	pitches[1] = root
	for r = 1, count do
		if ratios[r] == self.ratio then
			self.class = r + 1
		end
		pitches[r + 1] = ratios[r] * root
	end

	self.length = count + 1 -- include span ratio in length

	local class_values = {}
	for i = 1, count do
		class_values[i] = self.ratios[i].value
	end
	class_values[self.length] = span.value
	self.scale:set_class_values(class_values, root.value)
	
	self:print_ratios()
	self:select()
	self:on_update()
end

function ScaleEditor:is_class_active(class)
	if class == nil then
		class = self.class
	end
	return self.scale:is_class_active(class)
end

function ScaleEditor:toggle_class(class)
	if class == nil then
		class = self.class
	end
	return self.scale:toggle_class(class)
end

function ScaleEditor:replace_class(class, ratio)
	if ratio == nil then
		ratio = class
		class = self.class
	end
	if class < 2 or class > self.length then
		error('invalid ratio index: ' .. class)
		return
	end
	self.ratios[class - 1] = Ratio.new(ratio)
	self:select(class)
	self:update()
end

function ScaleEditor:multiply_class(class, ratio)
	if ratio == nil then
		ratio = class
		class = self.class
	end
	if class < 2 or class > self.length then
		error('invalid ratio index: ' .. class)
		return
	end
	self:replace_class(class, self.ratios[class] * ratio)
end

function ScaleEditor:delete_class(class)
	if class == nil then
		class = self.class
	end
	if class < 2 or class > self.length then
		error('invalid ratio index: ' .. class)
		return
	end
	table.remove(self.ratios, class - 1)
	-- TODO: select next lowest ratio
	self:update()
end

-- transpose the entire scale
function ScaleEditor:transpose(ratio)
	local shift = Ratio.new(ratio)
	local active_values = self.scale:get_active_values()
	for i, v in ipairs(active_values) do
		active_values[i] = v + shift.value
	end
	self.root = self.pitches[1] * shift
	self.root:reduce(self.span)
	self:update()
	self.scale:set_active_values(active_values)
	self.scale:apply_edits()
end

-- change the root pitch of the scale, without changing absolute pitches
function ScaleEditor:reroot(class)
	if class == nil then
		class = self.class
	end
	if class < 2 or class > self.length then
		error('invalid ratio index: ' .. class)
		return
	end
	local root = self.pitches[class]
	root:reduce(self.span)
	local shift = self.ratios[class - 1]
	for r = 1, self.length - 1 do
		if r == class - 1 then
			-- shift/shift = 1/1, which is always & already in the scale; the pitch we really want is 1/shift
			self.ratios[r] = 1 / shift
		else
			local str = self.ratios[r]:__tostring()
			self.ratios[r] = self.ratios[r] / shift
		end
	end
	self.root = root
	self:update()
	self:select(1)
end

-- TODO: another function to respell note names only, without changing pitches

function ScaleEditor:insert(ratio)
	self.ratios[self.length] = Ratio.new(ratio)
	self:select(self.length + 1)
	self:update()
end

--- find the pitch class nearest to ratio and retune it to match
-- @param ratio target ratio
-- @param insert_threshold if nearest found class is > than this many cents away from `ratio`, inset `ratio` as a new pitch class instead or retuning
function ScaleEditor:retune(ratio, insert_threshold)
	ratio = Ratio.new(ratio)
	local nearest_pitch_id = self.scale:get_nearest_pitch_id(ratio.value)
	if insert_threshold ~= nil then
		cents_diff = math.abs(ratio.value - self.scale.values[nearest_pitch_id]) * 1200
		if cents_diff > insert_threshold then
			self:insert(ratio)
			return
		end
	end
	self:replace_class(self.scale:get_class(nearest_pitch_id), ratio)
end

function ScaleEditor:read_scala_file(path)
	-- read the file
	local ratios, description = read_scala_file(path)
	-- the final ratio is a special one, because it's the scale span; it shouldn't be editable with
	-- the same functions as other pitches, so we move it to a separate property
	self.length = #ratios
	for i = 1, self.length do
		setmetatable(ratios[i], Ratio)
	end
	self.span = ratios[self.length]
	ratios[self.length] = nil
	-- sort, reduce, and update scale ratios
	self.ratios = ratios
	self:update()
	-- announce ourselves
	print(description)
end

function ScaleEditor:split_input_at_cursor()
	local before = string.sub(self.input, 1, self.cursor - 1)
	local after = string.sub(self.input, self.cursor, -1)
	return before, after
end

function ScaleEditor:draw_field(x, y, value, level, right)
	if self.input ~= '' then
		local before, after = self:split_input_at_cursor()
		local width_before, height_before = screen.text_extents(before)
		local width_after, height_after = screen.text_extents(after)
		local height = math.max(height_before, height_after) -- one of these may be 0

		if right then
			screen.move(x - width_before - width_after - 3, y)
		else
			screen.move(x, y)
		end
		screen.level(level)
		screen.text(before)

		if right then
			screen.move(x - width_after - 0.5, y + 1)
		else
			screen.move(x + width_before + 0.5, y + 1)
		end
		screen.line_rel(0, -height)
		screen.level(blink_slow and 15 or 3)
		screen.stroke()

		if right then
			screen.move(x - width_after, y)
		else
			screen.move(x + width_before + 2, y)
		end
		screen.level(level)
		screen.text(after)
	else
		local width, height = screen.text_extents(value)
		if right then
			screen.rect(x - width - 1, y - height + 2, width + 2, height - 1)
			screen.level(1)
			screen.fill()
			screen.move(x - width, y)
		else
			screen.rect(x - 1, y - height + 2, width + 2, height - 1)
			screen.level(1)
			screen.fill()
			screen.move(x, y)
		end
		screen.level(blink_slow and level or math.floor(level / 2))
		screen.text(value)
	end
end

function ScaleEditor:redraw()
	screen.clear()

	screen.font_face(1)
	screen.font_size(8)

	local class = self.class
	local pitch = self.pitches[class]
	local active = self:is_class_active()
	local ratio = self.ratio

	screen.level(active and 10 or 3)
	screen.move(3, 14)
	if class == 1 then
		screen.text('span')
	else
		screen.text(string.format('%d.', class))
	end

	screen.font_face(27)
	screen.font_size(10)

	if self.focus_field == 1 then
		self:draw_field(61, 12, string.format('%.0f', self.num), active and 15 or 4, true)
	else
		screen.move(61, 12)
		screen.level(active and 15 or 4)
		screen.text_right(string.format('%.0f', self.num))
	end

	screen.level(active and 4 or 1)
	screen.move(58, 21)
	screen.line(68, 1)
	screen.stroke()

	if self.focus_field == 2 then
		self:draw_field(66, 17, string.format('%.0f', self.den), active and 15 or 4)
	else
		screen.move(66, 17)
		screen.level(active and 15 or 4)
		screen.text(string.format('%.0f', self.den))
	end

	if self.input ~= '' or self.num ~= ratio.num or self.den ~= ratio.den then
		screen.move_rel(3, -7)
		screen.level((self.focus_field == 0 and blink_slow and 15) or 2)
		screen.text('*')
	end

	screen.font_face(1)
	screen.font_size(8)
	screen.level(active and 10 or 3)
	
	local x = 3
	local name = pitch.name
	local char = string.sub(name, 1, 1)
	name = string.sub(name, 2)
	screen.move(x, 23)
	screen.text(char)
	x = x + screen.text_extents(char) + 1
	while string.len(name) > 0 do
		char = string.sub(name, 1, 1)
		name = string.sub(name, 2)
		screen.move(x, 23)
		if char == 'b' then
			screen.move_rel(0.5, -5)
			screen.line_rel(0, 5)
			screen.move_rel(0.5, -0.5)
			screen.line_rel(1, 0)
			screen.move_rel(0.5, -0.5)
			screen.line_rel(0, -2)
			screen.move_rel(-0.5, 0.5)
			screen.line_rel(-1, 0)
			screen.stroke()
			x = x + 4
		elseif char == '^' then
			screen.move_rel(0, -2.5)
			screen.line_rel(1, 0)
			screen.move_rel(0, -1)
			screen.line_rel(1, 0)
			screen.move_rel(0.5, -1.5)
			screen.line_rel(0, 5)
			screen.move_rel(0.5, -3.5)
			screen.line_rel(1, 0)
			screen.move_rel(0, 1)
			screen.line_rel(1, 0)
			screen.stroke()
			x = x + 6
		elseif char == 'v' then
			screen.move_rel(0, -2.5)
			screen.line_rel(1, 0)
			screen.move_rel(0, 1)
			screen.line_rel(1, 0)
			screen.move_rel(0.5, 1.5)
			screen.line_rel(0, -5)
			screen.move_rel(0.5, 3.5)
			screen.line_rel(1, 0)
			screen.move_rel(0, -1)
			screen.line_rel(1, 0)
			screen.stroke()
			x = x + 6
		elseif char == 'E' then
			screen.move_rel(1, -4.5)
			screen.line_rel(3, 0)
			screen.move_rel(-4, 1)
			screen.line_rel(1, 0)
			screen.move_rel(0, 1)
			screen.line_rel(2, 0)
			screen.move_rel(-3, 1)
			screen.line_rel(1, 0)
			screen.move_rel(0, 1)
			screen.line_rel(3, 0)
			screen.stroke()
			x = x + 5
		elseif char == 'l' then
			screen.move_rel(0.5, -5)
			screen.line_rel(0, 5)
			screen.move_rel(0.5, -0.5)
			screen.line_rel(1, 0)
			screen.stroke()
			x = x + 3
		elseif char == 'L' then
			screen.move_rel(0, -0.5)
			screen.line_rel(4, 0)
			screen.move_rel(-4, -0.5)
			screen.line_rel(1, 0)
			screen.move_rel(0, -1)
			screen.line_rel(1, 0)
			screen.move_rel(0.5, -0.5)
			screen.line_rel(0, -2)
			screen.stroke()
			x = x + 5
		elseif char == 'Z' then
			screen.move_rel(0, -4.5)
			screen.line_rel(4, 0)
			screen.move_rel(0, 1)
			screen.line_rel(-1, 0)
			screen.move_rel(0, 1)
			screen.line_rel(-2, 0)
			screen.move_rel(0, 1)
			screen.line_rel(-1, 0)
			screen.move_rel(1, 1)
			screen.line_rel(3, 0)
			screen.stroke()
			x = x + 5
		else
			screen.text(char)
			x = x + screen.text_extents(char) + 1
		end
	end

	screen.move(3, 42)
	if ratio.factors ~= nil then
		local is_first = true
		for p, e in ipairs(ratio.factors) do
			if e ~= 0 then

				screen.font_face(1)
				screen.font_size(8)
				if not is_first then
					screen.move_rel(1, 1)
					screen.level(1)
					screen.text('*')
					screen.level(active and 10 or 3)
					screen.move_rel(1, -1)
				end
				screen.text(Ratio.primes[p])

				if e ~= 1 then
					screen.move_rel(0, -4)
					screen.font_face(25)
					screen.font_size(6)
					screen.text(e)
					screen.move_rel(0, 4)
				end

				is_first = false
			end
		end
	end

	local span_value = self.span.value
	for c = 1, self.length do
		
		local ratio = c == 1 and self.span or self.ratios[c - 1]
		local x = math.floor(125 * ratio.value / span_value) + 1.5
		local len = self:is_class_active(c) and 4 or 1

		local level = 1
		if class == c and self:is_class_active(c) then
			level = 15
		elseif self:is_class_active(c) then
			level = 7
		elseif class == c then
			level = 5
		end
		screen.level(level)

		screen.move(x, 64)
		screen.line_rel(0, -len)
		screen.stroke()
		if c == 1 then
			screen.move(1.5, 64)
			screen.line_rel(0, -len)
			screen.stroke()
		end

		if class == c then
			screen.move(x - 1.5, 59.5 - len)
			screen.line_rel(3, 0)
			screen.move_rel(-2, 1)
			screen.line_rel(1, 0)
			screen.stroke()
			if c == 1 then
				screen.move(0, 59.5 - len)
				screen.line_rel(3, 0)
				screen.move_rel(-2, 1)
				screen.line_rel(1, 0)
				screen.stroke()
			end
		end
	end

	screen.update()
end

function ScaleEditor:type(char)
	if self.focus_field ~= 0 then
		local before, after = self:split_input_at_cursor()
		self.input = before .. char .. after
		self.cursor = self.cursor + 1
	end
end

function ScaleEditor:direction_key(direction)
	-- directions: 1 = left, 2 = down, 3 = up, 4 = right
	if self.focus_field == 0 then
		if direction == 1 then
			self:select((self.class - 2) % self.length + 1)
		elseif direction == 4 then
			self:select(self.class % self.length + 1)
		end
	else
		if direction == 1 then
			self.cursor = math.max(1, self.cursor - 1)
		elseif direction == 2 then
			self.cursor = string.len(self.input) + 1
		elseif direction == 3 then
			self.cursor = 1
		elseif direction == 4 then
			self.cursor = math.min(string.len(self.input) + 1, self.cursor + 1)
		end
	end
end

function ScaleEditor:focus_next()
	if self.input ~= '' then
		if self.focus_field == 1 then
			self.num = tonumber(self.input)
		elseif self.focus_field == 2 then
			self.den = tonumber(self.input)
		end
		self.input = ''
	end
	self.cursor = 1
	if self.held_keys.plus or self.held_keys.shift then
		self.focus_field = (self.focus_field - 1) % (self.n_fields + 1)
	else
		self.focus_field = (self.focus_field + 1) % (self.n_fields + 1)
	end
end

function ScaleEditor:keyboard_event(type, code, value)
	if type == hid.types.EV_KEY then
		if code == hid.codes.KEY_LEFTCTRL then
			self.held_keys.lctrl = value ~= 0
			self.held_keys.ctrl = self.held_keys.lctrl or self.held_keys.rctrl
		elseif code == hid.codes.KEY_RIGHTCTRL then
			self.held_keys.rctrl = value ~= 0
			self.held_keys.ctrl = self.held_keys.lctrl or self.held_keys.rctrl
		elseif code == hid.codes.KEY_LEFTSHIFT then
			self.held_keys.lshift = value ~= 0
			self.held_keys.shift = self.held_keys.lshift or self.held_keys.rshift
		elseif code == hid.codes.KEY_RIGHTSHIFT then
			self.held_keys.rshift = value ~= 0
			self.held_keys.shift = self.held_keys.lshift or self.held_keys.rshift
		elseif code == hid.codes.KEY_LEFTALT then
			self.held_keys.lalt = value ~= 0
			self.held_keys.alt = self.held_keys.lalt or self.held_keys.ralt
		elseif code == hid.codes.KEY_RIGHTALT then
			self.held_keys.ralt = value ~= 0
			self.held_keys.alt = self.held_keys.lalt or self.held_keys.ralt
		elseif code == hid.codes.KEY_KPPLUS then
			self.held_keys.plus = value ~= 0
		elseif value == 1 then
			if (self.held_keys.alt or self.held_keys.plus) and not (self.held_keys.ctrl or self.held_keys.shift) then
				if code == hid.codes.KEY_ENTER or code == hid.codes.KEY_KP5 then
					self:toggle_class()
					return
				elseif code == hid.codes.KEY_BACKSPACE or code == hid.codes.KEY_KPDOT then
					self:delete_class()
					return
				elseif code == hid.codes.KEY_DOT or code == hid.codes.KEY_KP7 then
					self:reroot()
					return
				elseif code == hid.codes.KEY_KP1 then
					-- TODO: undo
					return
				end
			elseif not (self.held_keys.ctrl or self.held_keys.alt or self.held_keys.shift) then
				if self.held_keys.numlock then
					if code == hid.codes.KEY_1 or code == hid.codes.KEY_KP1 then
						self:type('1')
					elseif code == hid.codes.KEY_2 or code == hid.codes.KEY_KP2 then
						self:type('2')
					elseif code == hid.codes.KEY_3 or code == hid.codes.KEY_KP3 then
						self:type('3')
					elseif code == hid.codes.KEY_4 or code == hid.codes.KEY_KP4 then
						self:type('4')
					elseif code == hid.codes.KEY_5 or code == hid.codes.KEY_KP5 then
						self:type('5')
					elseif code == hid.codes.KEY_6 or code == hid.codes.KEY_KP6 then
						self:type('6')
					elseif code == hid.codes.KEY_7 or code == hid.codes.KEY_KP7 then
						self:type('7')
					elseif code == hid.codes.KEY_8 or code == hid.codes.KEY_KP8 then
						self:type('8')
					elseif code == hid.codes.KEY_9 or code == hid.codes.KEY_KP9 then
						self:type('9')
					elseif self.input ~= '' and (code == hid.codes.KEY_0 or code == hid.codes.KEY_KP0) then
						self:type('0')
					end
				else
					if code == hid.codes.KEY_KP1 or code == hid.codes.KEY_KP2 then
						self:direction_key(2)
						return
					elseif code == hid.codes.KEY_KP4 then
						self:direction_key(1)
						return
					elseif code == hid.codes.KEY_KP6 then
						self:direction_key(4)
						return
					elseif code == hid.codes.KEY_KP7 or code == hid.codes.KEY_KP8 then
						self:direction_key(3)
					end
				end
				-- TODO: other direction keys: left, right, up, down, home, end, fwd delete, ctrl keys...
				if code == hid.codes.KEY_RIGHTBRACE then
					self:direction_key(4)
					return
				elseif code == hid.codes.KEY_LEFTBRACE then
					self:direction_key(1)
					return
				elseif code == hid.codes.KEY_BACKSPACE then
					local before, after = self:split_input_at_cursor()
					self.input = string.sub(before, 1, -2) .. after
					self.cursor = math.max(1, self.cursor - 1)
					return
				elseif self.focus_field == 1 and code == hid.codes.KEY_KPSLASH then
					self:focus_next()
				end
			end
			if code == hid.codes.KEY_TAB then
				self:focus_next()
				return
			elseif code == hid.codes.KEY_ENTER or code == hid.codes.KEY_KPENTER then
				if self.focus_field == 0 then
					self:replace_class(self.num / self.den)
					return
				else
					self:focus_next()
				end
			end
		end
	elseif type == hid.types.EV_LED then
		if code == hid.codes.LED_NUML then
			self.held_keys.numlock = value ~= 0
		end
	end
end

return ScaleEditor
