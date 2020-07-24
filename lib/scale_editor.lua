local read_scala_file = include 'lib/scala'

local primes = { 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113, 127 }
local n_primes = #primes

local log2 = math.log(2)
local johnston_notes = {
	{
		note_name = 'C',
		num = 1,
		den = 1
	},
	{
		note_name = 'D',
		num = 9,
		den = 8
	},
	{
		note_name = 'E',
		num = 5,
		den = 4
	},
	{
		note_name = 'F',
		num = 4,
		den = 3
	},
	{
		note_name = 'G',
		num = 3,
		den = 2
	},
	{
		note_name = 'A',
		num = 5,
		den = 3
	},
	{
		note_name = 'B',
		num = 15,
		den = 8
	},
}

--- get prime factors of a number
-- @param n any number
function factorize(n)
	local p = 1
	local prime = primes[p]
	local factors = {}
	for p = 1, n_primes do
		factors[p] = 0
	end
	while n > 1 and p <= n_primes do
		if n % prime == 0 then
			-- divide by prime, keep going
			factors[p] = factors[p] + 1
			n = n / prime
		elseif p >= n_primes then
			-- if we've tried the last prime and we aren't done factoring, give up
			print('failed to factorize', n)
			return nil
		else
			-- next prime
			p = p + 1
			prime = primes[p]
			factors[p] = 0
		end
	end
	return factors
end

Ratio = {}

function Ratio.new(num, den)
	if type(num) == 'table' then
		return num
	elseif type(num) == 'string' then
		return Ratio.dejohnstonize(num)
	elseif type(num) ~= 'number' then
		num = 1
	end
	if type(den) ~= 'number' then
		num, den = rationalize(num)
	end
	local r = {
		num = num,
		den = den
	}
	return setmetatable(r, Ratio)
end

--- recalculate factors based on num/den, then simplify if possible
function Ratio:factorize()
	print('factorizing...')
	local factors = factorize(self.num)
	local den_factors = factorize(self.den)
	-- if we couldn't factorize either the numerator or the denominator, set factors to nil to
	-- indicate that this ratio is irrational
	if factors == nil or den_factors == nil then
		print('missing factors for num or den')
		self._factors = nil
		self._dirty = false
		return
	end
	for p = 1, n_primes do
		factors[p] = factors[p] - den_factors[p]
	end
	self:update_from_factors(factors)
end

--- set factors property and simplify num/den if possible
-- TODO: reduce!
function Ratio:update_from_factors(factors)
	if factors == nil then
		factors = self._factors
	else
		self._factors = factors
	end
	local num = 1
	local den = 1
	for p = 1, n_primes do
		if factors[p] > 0 then
			num = num * math.pow(primes[p], factors[p])
		elseif factors[p] < 0 then
			den = den * math.pow(primes[p], -factors[p])
		end
	end
	self.num = num
	self.den = den
	self._dirty = false
end

function Ratio:__index(key)
	if 'value' == key then
		return math.log(self.num / self.den) / log2
	elseif 'quotient' == key then
		return self.num / self.den
	elseif 'factors' == key then
		if self._dirty == false then
			return self._factors
		end
		self:factorize()
		return self._factors
	elseif 'name' == key then
		if self._name ~= nil then
			return self._name
		end
		self:johnstonize()
		return self._name
	end
	if Ratio[key] ~= nil then
		return Ratio[key]
	end
end

function Ratio:__mul(other)
	if getmetatable(other) ~= Ratio then
		other = Ratio.new(other)
	end
	if self.factors == nil or other.factors == nil then
		-- one or both ratios is irrational, so just multiply num + den
		return Ratio.new(self.num * other.num, self.den * other.den)
	end
	local factors = self.factors
	local other_factors = other.factors
	local product = Ratio.new()
	local product_factors = {}
	for p = 1, n_primes do
		product_factors[p] = factors[p] + other_factors[p]
	end
	product:update_from_factors(product_factors)
	return product
end

function Ratio:__div(other)
	if getmetatable(other) ~= Ratio then
		other = Ratio.new(other)
	end
	if self.factors == nil or other.factors == nil then
		-- one or both ratios is irrational, so just multiply num*den + den*num
		return Ratio.new(self.num * other.den, self.den * other.num)
	end
	local quotient = Ratio.new()
	local quotient_factors = {}
	for p = 1, n_primes do
		quotient_factors[p] = self.factors[p] - other.factors[p]
	end
	quotient:update_from_factors(quotient_factors)
	return quotient
end

function Ratio:__lt(other)
	if type(other) == 'number' then
		return self.quotient < other
	elseif getmetatable(other) ~= Ratio then
		other = Ratio.new(other)
	end
	return self.quotient < other.quotient
end

function Ratio:__lte(other)
	if type(other) == 'number' then
		return self.quotient <= other
	elseif getmetatable(other) ~= Ratio then
		other = Ratio.new(other)
	end
	return self.quotient <= other.quotient
end

function Ratio:__gt(other)
	if type(other) == 'number' then
		return self.quotient > other
	elseif getmetatable(other) ~= Ratio then
		other = Ratio.new(other)
	end
	return self.quotient > other.quotient
end

function Ratio:__gte(other)
	if type(other) == 'number' then
		return self.quotient >= other
	elseif getmetatable(other) ~= Ratio then
		other = Ratio.new(other)
	end
	return self.quotient >= other.quotient
end

function Ratio:__tostring()
	if self.factors ~= nil then
		return string.format('%.0f/%.0f', self.num, self.den)
	end
	return string.format('%f', self.num / self.den)
end

function Ratio:print_factors()
	local factors = self.factors
	if factors == nil then
		print('irrational')
	end
	local string = string.format('%s = ', self)
	local first = true
	for p = 1, n_primes do
		if factors[p] ~= 0 then
			if not first then
				string = string .. ' * '
			end
			if factors[p] == 1 then
				string = string .. string.format('%d', primes[p])
			else
				string = string .. string.format('%d^%d', primes[p], factors[p])
			end
			first = false
		end
	end
	print(string)
end

function Ratio:johnstonize()
	print('johnstonizing...')

	local factors = self.factors
	local note = 1 -- C
	local class = 1
	local sharps = 0
	local pluses = 0
	local sevens = 0
	local arrows = 0
	local thirteens = 0
	local seventeens = 0
	local nineteens = 0

	-- For every 3 in the numerator:
	-- Ascend one perfect fifth. (Add a plus to the perfect fifth note if starting on any kind of B or
	-- D, including Bb, D#, B-, whatever. If the original note had a minus, the plus will merely cancel
	-- it out on the new note.)

	local f3 = factors[2]
	while f3 > 0 do
		note = note + 4
		if class == 7 then -- B
			sharps = sharps + 1
		end
		if class == 7 or class == 2 then -- B or D
			pluses = pluses + 1
		end
		f3 = f3 - 1
		class = (note - 1) % 7 + 1
	end
	-- For every 3 in the denominator:
	-- Descend one perfect fifth. (Add minus if starting on an A or F.)
	while f3 < 0 do
		note = note - 4
		if class == 4 then -- F
			sharps = sharps - 1
		end
		if class == 4 or class == 6 then
			pluses = pluses - 1
		end
		f3 = f3 + 1
		class = (note - 1) % 7 + 1
	end

	-- For every 5 in the numerator:
	-- Ascend one major 3rd. (Add plus if starting on a D.)
	local f5 = factors[3]
	while f5 > 0 do
		note = note + 2
		if class == 2 or class == 3 or class == 6 or class == 7 then
			sharps = sharps + 1
		end
		if class == 2 then
			pluses = pluses + 1
		end
		f5 = f5 - 1
		class = (note - 1) % 7 + 1
	end
	-- For every 5 in the denominator:
	-- Descend one major 3rd. (Add minus if starting on an F.)
	while f5 < 0 do
		note = note - 2
		if class == 1 or class == 2 or class == 4 or class == 5 then
			sharps = sharps - 1
		end
		if class == 4 then
			pluses = pluses - 1
		end
		f5 = f5 + 1
		class = (note - 1) % 7 + 1
	end

	-- For every 7 in the numerator:
	-- Ascend one minor seventh and add a 7. (Add plus if starting on a G, B, or D.)
	local f7 = factors[4]
	while f7 > 0 do
		note = note + 6
		if class == 1 or class == 4 then
			sharps = sharps - 1
		end
		if class == 2 or class == 5 or class == 7 then
			pluses = pluses + 1
		end
		sevens = sevens + 1
		f7 = f7 - 1
		class = (note - 1) % 7 + 1
	end
	-- For every 7 in the denominator:
	-- Descend one minor seventh and add a L (sub-7). (Add minus if starting on an F, A, or C.)
	while f7 < 0 do
		note = note - 6
		if class == 3 or class == 7 then
			sharps = sharps + 1
		end
		if class == 1 or class == 4 or class == 6 then
			pluses = pluses - 1
		end
		sevens = sevens - 1
		f7 = f7 + 1
		class = (note - 1) % 7 + 1
	end

	-- For every 11 in the numerator:
	-- Ascend one perfect fourth and add ^ (up-arrow). (Add minus if starting on an A or F.)
	local f11 = factors[5]
	while f11 > 0 do
		note = note + 3
		if class == 4 then
			sharps = sharps - 1
		end
		if class == 4 or class == 6 then
			pluses = pluses - 1
		end
		arrows = arrows + 1
		f11 = f11 - 1
		class = (note - 1) % 7 + 1
	end
	-- For every 11 in the denominator:
	-- Descend one perfect fourth and add v (down-arrow). (Add plus if starting on a B or D.)
	while f11 < 0 do
		note = note - 3
		if class == 7 then
			sharps = sharps + 1
		end
		if class == 2 or class == 7 then
			pluses = pluses + 1
		end
		arrows = arrows - 1
		f11 = f11 + 1
		class = (note - 1) % 7 + 1
	end

	-- For every 13 in the numerator:
	-- Ascend one minor sixth and add a 13. (Add minus if starting on an F.)
	local f13 = factors[6]
	while f13 > 0 do
		note = note + 5
		if class == 1 or class == 2 or class == 4 or class == 5 then
			sharps = sharps - 1
		end
		if class == 4 then
			pluses = pluses - 1
		end
		thirteens = thirteens + 1
		f13 = f13 - 1
		class = (note - 1) % 7 + 1
	end
	-- For every 13 in the denominator:
	-- Descend one minor sixth and add an upside-down 13. (Add plus if starting on a D.)
	while f13 < 0 do
		note = note - 5
		if class == 2 or class == 3 or class == 6 or class == 7 then
			sharps = sharps + 1
		end
		if class == 2 then
			pluses = pluses + 1
		end
		thirteens = thirteens - 1
		f13 = f13 + 1
		class = (note - 1) % 7 + 1
	end

	-- For every 17 in the numerator:
	-- Add a sharp and a 17.
	-- For every 17 in the denominator:
	-- Add a flat and an upside-down 17.
	sharps = sharps + factors[7]
	seventeens = factors[7]

	-- For every 19 in the numerator:
	-- Ascend a minor third and add a 19. (Add plus if starting on a D.)
	local f19 = factors[8]
	while f19 > 0 do
		note = note + 2
		if class == 1 or class == 4 or class == 5 then
			sharps = sharps - 1
		end
		if class == 2 then
			pluses = pluses + 1
		end
		nineteens = nineteens + 1
		f19 = f19 - 1
		class = (note - 1) % 7 + 1
	end
	-- For every 19 in the denominator:
	-- Descend a minor third and add an upside-down 19. (Add minus if starting on an F.) 
	while f19 < 0 do
		note = note - 2
		if class == 3 or class == 6 or class == 7 then
			sharps = sharps + 1
		end
		if class == 4 then
			pluses = pluses - 1
		end
		nineteens = nineteens - 1
		f19 = f19 + 1
		class = (note - 1) % 7 + 1
	end

	local check = johnston_notes[class]
	local name = check.note_name

	local accidentals = Ratio.accidentals

	while sharps > 0 do
		name = name .. '#'
		check = check * accidentals.sharp
		sharps = sharps - 1
	end
	while sharps < 0 do
		name = name .. 'b'
		check = check / accidentals.sharp
		sharps = sharps + 1
	end

	while sevens > 0 do
		name = name .. '7'
		check = check * accidentals.seven
		sevens = sevens - 1
	end
	while sevens < 0 do
		name = name .. 'L'
		check = check / accidentals.seven
		sevens = sevens + 1
	end

	while arrows > 0 do
		name = name .. '^'
		check = check * accidentals.arrow
		arrows = arrows - 1
	end
	while arrows < 0 do
		name = name .. 'v'
		check = check / accidentals.arrow
		arrows = arrows + 1
	end

	while thirteens > 0 do
		name = name .. '13'
		check = check * accidentals.thirteen
		thirteens = thirteens - 1
	end
	while thirteens < 0 do
		name = name .. 'El'
		check = check / accidentals.thirteen
		thirteens = thirteens + 1
	end

	while seventeens > 0 do
		name = name .. '17'
		check = check * accidentals.seventeen
		seventeens = seventeens - 1
	end
	while seventeens < 0 do
		name = name .. 'Ll'
		check = check / accidentals.seventeen
		seventeens = seventeens + 1
	end

	while nineteens > 0 do
		name = name .. '19'
		check = check * accidentals.nineteen
		nineteens = nineteens - 1
	end
	while nineteens < 0 do
		name = name .. '6l'
		check = check / accidentals.nineteen
		nineteens = nineteens + 1
	end

	while pluses > 0 do
		name = name .. '+'
		check = check * accidentals.plus
		pluses = pluses - 1
	end
	while pluses < 0 do
		name = name .. '-'
		check = check / accidentals.plus
		pluses = pluses + 1
	end

	for p = 2, n_primes do -- ignore factors of 2
		if check.factors[p] ~= factors[p] then
			error('incorrect johnstonization')
		end
	end
	
	self._name = name
end

Ratio.accidentals = {
	plus = Ratio.new(81, 80),
	sharp = Ratio.new(25, 24),
	seven = Ratio.new(35, 36),
	arrow = Ratio.new(33, 32),
	thirteen = Ratio.new(65, 64),
	seventeen = Ratio.new(51, 50),
	nineteen = Ratio.new(95, 96),
	twentythree = Ratio.new(46, 45),
	twentynine = Ratio.new(145, 144),
	thirtyone = Ratio.new(31, 30)
}

function Ratio.dejohnstonize(name)
	print('dejohnstonizing...')
	local ratio = nil
	local note_name = string.sub(name, 1, 1)
	if note_name == 'C' then
		ratio = johnston_notes[1]
		name = string.sub(name, 2)
	elseif note_name == 'D' then
		ratio = johnston_notes[2]
		name = string.sub(name, 2)
	elseif note_name == 'E' then
		ratio = johnston_notes[3]
		name = string.sub(name, 2)
	elseif note_name == 'F' then
		ratio = johnston_notes[4]
		name = string.sub(name, 2)
	elseif note_name == 'G' then
		ratio = johnston_notes[5]
		name = string.sub(name, 2)
	elseif note_name == 'A' then
		ratio = johnston_notes[6]
		name = string.sub(name, 2)
	elseif note_name == 'B' then
		ratio = johnston_notes[7]
		name = string.sub(name, 2)
	else
		ratio = Ratio.new()
	end
	local accidentals = Ratio.accidentals
	while string.len(name) > 0 do
		local char = string.sub(name, 1, 1)
		local pair = string.sub(name, 1, 2)
		if char == '#' then
			ratio = ratio * accidentals.sharp
			name = string.sub(name, 2)
		elseif char == 'b' then
			ratio = ratio / accidentals.sharp
			name = string.sub(name, 2)
		elseif char == '7' then
			ratio = ratio * accidentals.seven
			name = string.sub(name, 2)
		elseif char == 'L' then
			ratio = ratio / accidentals.seven
			name = string.sub(name, 2)
		elseif char == '^' then
			ratio = ratio * accidentals.arrow
			name = string.sub(name, 2)
		elseif char == 'v' then
			ratio = ratio / accidentals.arrow
			name = string.sub(name, 2)
		elseif pair == '13' then
			ratio = ratio * accidentals.thirteen
			name = string.sub(name, 3)
		elseif pair == 'El' then
			ratio = ratio / accidentals.thirteen
			name = string.sub(name, 3)
		elseif pair == '17' then
			ratio = ratio * accidentals.seventeen
			name = string.sub(name, 3)
		elseif pair == 'Ll' then
			ratio = ratio / accidentals.seventeen
			name = string.sub(name, 3)
		elseif pair == '19' then
			ratio = ratio * accidentals.nineteen
			name = string.sub(name, 3)
		elseif pair == '6l' then
			ratio = ratio / accidentals.nineteen
			name = string.sub(name, 3)
		else
			print(name)
			error('can\'t dejohnstonize')
			return nil
		end
	end
	return ratio
end

for i, r in ipairs(johnston_notes) do
	setmetatable(r, Ratio)
end

local ScaleEditor = {}
ScaleEditor.__index = ScaleEditor

function ScaleEditor.new(scale)
	local editor = setmetatable({}, ScaleEditor)
	editor.scale = scale
	editor.ratios = {}
	editor.selected_ratio = 0
	editor.held_keys = {
		ctrl = false,
		lctrl = false,
		rctrl = false,
		shift = false,
		lshift = false,
		rshift = false,
		alt = false,
		lalt = false,
		ralt = false
	}
	return editor
end

function ScaleEditor:select_pitch(pitch_id)
	self.selected_ratio = self.scale:get_class(pitch_id) - 1
end

--- reduce a ratio to [1/1, span_ratio)
-- @param r a ratio table containing `num` and `den` properties; a `factors` property will be added
function ScaleEditor:reduce_ratio(r)
	local i = 1
	local s = self.span_ratio
	local span = s.num / s.den
	while r.num / r.den >= span do
		print('down', r.num .. '/' .. r.den)
		r.num = r.num * s.den
		r.den = r.den * s.num
		i = i + 1
		if i > 10 then
			print('too many loops down', r.num .. '/' .. r.den)
			return
		end
	end
	while r.den / r.num > span do
		print('up', r.num .. '/' .. r.den)
		r.num = r.num * s.num
		r.den = r.den * s.den
		i = i + 1
		if i > 10 then
			print('too many loops up', r.num .. '/' .. r.den)
			return
		end
	end
	r._dirty = true
end

function ScaleEditor:print_ratios()
	local classes_active = self.scale.classes_active
	for p = 1, self.length do
		local r = (p == self.length and self.span_ratio or self.ratios[p])
		local marker = (classes_active[p % self.length + 1] and '*' or ' ')
		print(string.format('%d. %s %s', p, marker, r))
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
	local selected = self.ratios[self.selected_ratio]

	for i = 1, count do
		self:reduce_ratio(ratios[i])
	end
	table.sort(ratios, sort_ratios)

	self.selected_ratio = 0
	for r = 1, count do
		if ratios[r] == selected then
			self.selected_ratio = r
		end
	end

	self.span_ratio._dirty = true -- TODO: why did I think this was necessary...?
	self.length = #ratios + 1 -- include span ratio in length

	local class_values = {}
	for i, r in ipairs(ratios) do
		class_values[i] = math.log(r.num / r.den) / log2
	end
	class_values[self.length] = math.log(self.span_ratio.num / self.span_ratio.den) / log2
	self.scale:set_class_values(class_values)
	
	self:print_ratios()
end

function ScaleEditor:replace_ratio(r, num, den)
	if r < 2 or r > self.length then
		error('invalid ratio index: ' .. r)
		return
	end
	self.selected_ratio = r - 1
	self.ratios[self.selected_ratio] = Ratio.new(num, den)
	self:update()
end

function ScaleEditor:multiply_ratio(r, num, den)
	if r < 2 or r > self.length then
		error('invalid ratio index: ' .. r)
		return
	end
	self:replace_ratio(r, self.ratios[self.selected_ratio] * Ratio.new(num, den))
end

function ScaleEditor:delete_ratio(r)
	if r < 2 or r > self.length then
		error('invalid ratio index: ' .. r)
		return
	end
	table.remove(self.ratios, r - 1)
	self:update()
end

function ScaleEditor:insert_ratio(num, den)
	self.ratios[self.length] = Ratio.new(num, den)
	self.selected_ratio = self.length
	self:update()
end

function ScaleEditor:read_scala_file(path)
	-- read the file
	local _, ratios, description = read_scala_file(path)
	-- the final ratio is a special one, because it's the scale span; it shouldn't be editable with
	-- the same functions as other pitches, so we move it to a separate property
	self.length = #ratios
	for i = 1, self.length do
		setmetatable(ratios[i], Ratio)
	end
	self.span_ratio = ratios[self.length]
	ratios[self.length] = nil
	-- sort, reduce, and update scale ratios
	self.ratios = ratios
	self:update()
	-- announce ourselves
	print(description)
end

function ScaleEditor:redraw()
	screen.clear()

	screen.font_face(1)
	screen.font_size(8)
	-- large: 29/13 (mono), 27/10 (contrasty mono), 30/13 (italic), 32/13 (same, light), 34/16 (italic), 36/16 (same, light)
	-- tiny: 25/6
	--
	local classes_active = self.scale.classes_active
	local selected_ratio = self.selected_ratio
	local class = selected_ratio % self.scale.length + 1
	local active = classes_active[class]
	local ratio = self.ratios[selected_ratio]
	if class == 1 then
		ratio = self.span_ratio
	end

	screen.level(active and 10 or 3)
	screen.move(3, 14)
	if class == 1 then
		screen.text('span')
	else
		screen.text(string.format('%d.', class))
	end

	screen.level(active and 15 or 7)
	screen.font_face(27)
	screen.font_size(10)

	screen.move(61, 12)
	screen.text_right(string.format('%.0f', ratio.num))

	screen.level(active and 4 or 1)
	screen.move(58, 21)
	screen.line(68, 1)
	screen.stroke()

	screen.level(active and 15 or 7)
	screen.move(66, 17)
	screen.text(string.format('%.0f', ratio.den))

	screen.level(active and 10 or 3)
	screen.font_face(1)
	screen.font_size(8)
	screen.move(3, 28)
	screen.text(ratio.name)

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
				screen.text(primes[p])

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

	local span_value = self.span_ratio.value
	local level = 1
	local len = 1
	if self.selected_ratio == 0 and classes_active[1] then
		level = 15
		len = 5
	elseif classes_active[1] then
		level = 7
		len = 4
	elseif self.selected_ratio == 0 then
		level = 5
	end
	screen.level(level)
	screen.move(0.5, 64)
	screen.line_rel(0, -len)
	screen.stroke()
	screen.move(127.5, 64)
	screen.line_rel(0, -len)
	screen.stroke()
	for r = 1, self.length - 1 do
		local x = math.floor(127 * self.ratios[r].value / span_value) + 0.5
		level = 1
		len = 1
		if self.selected_ratio == r and classes_active[r + 1] then
			level = 15
			len = 5
		elseif classes_active[r + 1] then
			level = 7
			len = 4
		elseif self.selected_ratio == r then
			level = 5
		end
		screen.move(x, 64)
		screen.line_rel(0, -len)
		screen.level(level)
		screen.stroke()
	end

	screen.update()
end

function ScaleEditor:keyboard_event(type, code, value)
	if type == 1 then
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
		elseif value == 1 then
			if self.held_keys.alt and not (self.held_keys.ctrl or self.held_keys.shift) then
			elseif not (self.held_keys.ctrl or self.held_keys.alt or self.held_keys.shift) then
				if code == hid.codes.KEY_RIGHTBRACE then
					self.selected_ratio = (self.selected_ratio + 1) % self.scale.length
					dirty = true
					return
				elseif code == hid.codes.KEY_LEFTBRACE then
					self.selected_ratio = (self.selected_ratio - 1) % self.scale.length
					dirty = true
					return
				end
			end
		end
	end
	print('editor key', type, code, value)
end

return ScaleEditor
