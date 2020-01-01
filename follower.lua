-- follower
-- follow pitch, quantize, etc...

engine.name = 'Analyst'

local musicutil = require 'musicutil'

local pitch_poll_l
local amp_poll_l
local pitch_in = 0
local pitch_in_detected = false
local pitch_in_octave = 0
local crow_pitch_in = 0
local mask = {}
-- TODO: increase number of chords/masks
local saved_masks = {} -- TODO: save with params... somehow
-- idea: use a 'data file' param, so it can be changed; the hardest part will be naming new files, I think
local active_mask = 0
local mask_dirty = false
local max_pitch = 96

-- TODO: save/recall memory/loop contents like masks
local memory = {}
local mem_size = 32
local loop_length = mem_size
local head = 1
local heads = {}
local n_heads = 4

local source
local source_names = {
  'grid',
  'pitch track',
  'crow input 2',
  'grid OR pitch',
  'grid OR crow',
  'pitch OR grid'
  -- TODO: random too?
}
local source_grid = 1
local source_pitch = 2
local source_crow = 3
local source_grid_pitch = 4
local source_grid_crow = 5
local source_pitch_grid = 6

local loop_probability = 100
-- TODO: add internal clock using beatclock
local clock_mode
local clock_mode_names = {
  'trig in',
  'grid',
  'trig in OR grid'
}
local clock_mode_trig = 1
local clock_mode_grid = 2
local clock_mode_trig_grid = 3

local output_transpose = { 0, 0, 0, 0 }
local output_note = { 0, 0, 0, 0 }
local output_mode = {}
local output_mode_names = {
  'head 1 pitch',
  'head 1 aux',
  'head 2 pitch',
  'head 2 aux',
  'head 3 pitch',
  'head 3 aux',
  'head 4 pitch',
  'head 4 aux',
  'pitch in s+h',
  'pitch in stream',
  'amp in s+h',
  'amp in stream',
  'grid s+h',
  'grid stream'
}
local mode_head_1_pitch = 1
local mode_head_1_aux = 2
local mode_head_2_pitch = 3
local mode_head_2_aux = 4
local mode_head_3_pitch = 5
local mode_head_3_aux = 6
local mode_head_4_pitch = 7
local mode_head_4_aux = 8
local mode_pitch_in_sh = 9
local mode_pitch_in_stream = 10
local mode_amp_in_sh = 11
local mode_amp_in_stream = 12
local mode_grid_sh = 13
local mode_grid_stream = 14

local grid_mode_play = 1
local grid_mode_mask = 2
local grid_mode_transpose = 3
local grid_mode_heads = 4
local grid_mode = grid_mode_play

local output_selected = { true, true, true, true }
local output_button_held = { false, false, false, false }
local output_last_edited = 1

local g = grid.connect()
local held_keys = {}
local last_key = 0

local shift = false
local ctrl = false
local scroll = 4

local key_scroll = scroll
local transpose_scroll = scroll

local dirty = false
local redraw_metro

local function quantize(pitch)
  return math.floor(pitch + 0.5)
end

local function snap(pitch)
  pitch = math.max(1, math.min(max_pitch, pitch))
  local quantized = quantize(pitch)
  -- print(string.format('quantize %f to %d', pitch, quantized))
  local low = quantized < pitch
  if mask[quantized] then
    -- print('pitch enabled')
    return quantized
  end
  for i = 1, 96 do
    local up = math.min(96, quantized + i)
    local down = math.max(1, quantized - i)
    if low then
      if mask[down] then
        return down
      elseif mask[up] then
        return up
      end
    else
      if mask[up] then
        return up
      elseif mask[down] then
        return down
      end
    end
  end
  return 0
end

-- TODO: allow undo??
local function recall_mask(m)
  for i = 1, max_pitch do
    mask[i] = saved_masks[m][i]
  end
  active_mask = m
  mask_dirty = false
end

-- TODO: allow undo??
local function save_mask(m)
  for i = 1, max_pitch do
    saved_masks[m][i] = mask[i]
  end
  active_mask = m
  mask_dirty = false
end

local function get_grid_note(x, y)
  return x - 4 + (7 + scroll - y) * 5
end

local function get_grid_id_note(id)
  local x = id % 16
  local y = math.floor(id / 16)
  local note = get_grid_note(x, y)
  -- print(string.format('get grid id note: %d (%d, %d) = %d', id, x, y, note))
  return note
end

local function get_grid_mask(x, y)
  return x + (y - 3) * 4
end

local function update_output(out)
  local mode = output_mode[out]
  local volts = 0
  if mode == mode_pitch_in_sh or mode == mode_pitch_in_stream then
    output_note[out] = snap(quantize(pitch_in) + output_transpose[out])
    volts = output_note[out] / 12 - 1
  elseif mode == mode_amp_in_sh or mode == mode_amp_in_stream then
    output_note[out] = 0
    -- TODO: scale with params... or inside supercollider? 
    volts = amp_in * 5
  elseif mode == mode_grid_sh or mode == mode_grid_stream then
    output_note[out] = snap(get_grid_id_note(last_key) + output_transpose[out])
    volts = output_note[out] / 12 - 1
  else
    local is_pitch = mode % 2 > 0
    local out_head = math.ceil(mode / 2)
    if is_pitch then
      output_note[out] = snap(memory[heads[out_head].pos] + output_transpose[out])
      volts = output_note[out] / 12 - 1
    else
      output_note[out] = 0
      -- TODO: aux outputs
      -- parameter locks: add an expression lookup table, 1 value per note, accompanying output mode·
    end
  end
  dirty = true
  crow.output[out].volts = volts
end

local function sample_pitch(force_enable)
  -- TODO: you ditched cmd, so `force_enable` is never used. do you want it...?
  head = head % mem_size + 1
  for i = 1, 4 do
    heads[i]:move()
  end
  local grid_pitch = get_grid_id_note(last_key)
  local loop_pitch = memory[(head - loop_length - 1) % mem_size + 1] -- feed back an un-snapped value
  local pitch = loop_pitch
  if loop_probability <= math.random(1, 100) then
    if source == source_crow then
      pitch = crow_pitch_in
    elseif #held_keys > 0 and (source == source_grid or source == source_grid_pitch or source == source_grid_crow) then
      pitch = grid_pitch
    elseif pitch_in_detected and (source == source_pitch or source == source_pitch_grid) then
      pitch = pitch_in
    elseif source == source_grid_crow then
      pitch = crow_pitch_in
    elseif #held_keys > 0 and source == source_pitch_grid then
      pitch = grid_pitch
    end
  end
  memory[head] = pitch
  if force_enable then
    mask[quantize(pitch)] = true
    mask_dirty = true
  end
  for i = 1, 4 do
    local mode = output_mode[i]
    if mode ~= mode_pitch_in_stream and mode ~= mode_amp_in_stream and mode ~= mode_grid_stream then
      update_output(i)
    end
  end
  dirty = true
end

local function grid_redraw(tick)

  -- mode buttons
  g:led(1, 1, grid_mode == grid_mode_play and 4 or 1)
  g:led(2, 1, grid_mode == grid_mode_mask and 4 or 1)
  g:led(3, 1, grid_mode == grid_mode_transpose and 4 or 1)
  g:led(4, 1, grid_mode == grid_mode_heads and 4 or 1)

  -- recall buttons
  for x = 1, 4 do
    for y = 3, 6 do
      local m = get_grid_mask(x, y)
      if active_mask == m then
	if mask_dirty and tick % 8 > 3 then
	  g:led(x, y, 5)
	else
	  g:led(x, y, 4)
	end
      else
	g:led(x, y, 2)
      end
    end
  end

  -- shift + ctrl
  g:led(1, 7, shift and 4 or 2)
  g:led(1, 8, ctrl and 4 or 2)
  
  -- scrollbar
  for y = 1, 8 do
    if 9 - y == scroll or 8 - y == scroll then
      g:led(16, y, 2)
    else
      g:led(16, y, 1)
    end
  end

  if grid_mode == grid_mode_play or grid_mode == grid_mode_mask then
    for x = 5, 15 do
      for y = 1, 8 do
	-- keyboard
	local n = get_grid_note(x, y)
	local pitch = (n - 1) % 12 + 1
	if output_note[1] == n then
	  g:led(x, y, 7)
	elseif output_note[2] == n then
	  g:led(x, y, 7)
	elseif output_note[3] == n then
	  g:led(x, y, 7)
	elseif output_note[4] == n then
	  g:led(x, y, 7)
	elseif mask[n] then
	  g:led(x, y, grid_mode == grid_mode_mask and 4 or 3)
	elseif pitch == 2 or pitch == 4 or pitch == 5 or pitch == 7 or pitch == 9 or pitch == 11 or pitch == 12 then
	  g:led(x, y, grid_mode == grid_mode_mask and 2 or 1)
	else
	  g:led(x, y, 0)
	end
      end
    end
  elseif grid_mode == grid_mode_transpose then
    local transpositions = {
      params:get('output_1_transpose'),
      params:get('output_2_transpose'),
      params:get('output_3_transpose'),
      params:get('output_4_transpose')
    }
    -- clear
    for x = 5, 15 do
      for y = 1, 8 do
	g:led(x, y, 0)
      end
    end
    -- output buttons
    for i = 1, 4 do
      g:led(5, i + 2, output_selected[i] and 4 or 1)
    end
    -- transposition keyboard
    for x = 6, 15 do
      for y = 1, 8 do
	local n = get_grid_note(x, y)
	local level = 0
	if n == 36 then
	  level = math.max(level, 4)
	elseif n % 12 == 0 then
	  level = math.max(level, 2)
	end
	for i = 1, 4 do
	  if n - 36 == transpositions[i] then
	    level = math.max(level, output_selected[i] and 10 or 7)
	  end
	end
	g:led(x, y, level)
      end
    end
  else
    for x = 5, 16 do
      -- TODO: this also removes the scrollbar; ideally you wouldn't draw it in the first place
      for y = 1, 8 do
	g:led(x, y, 0)
      end
    end
  end
  g:refresh()
end

local function grid_key(x, y, z)
  if x < 5 then
    if y == 1 and z == 1 then
      -- grid mode buttons
      if x == 1 then
	if grid_mode == grid_mode_transpose then
	  transpose_scroll = scroll
	  scroll = key_scroll
	end
	grid_mode = grid_mode_play
      elseif x == 2 then
	if grid_mode == grid_mode_transpose then
	  transpose_scroll = scroll
	  scroll = key_scroll
	end
	grid_mode = grid_mode_mask
      elseif x == 3 then
	if grid_mode == grid_mode_play or grid_mode == grid_mode_mask then
	  key_scroll = scroll
	  scroll = transpose_scroll
	end
	grid_mode = grid_mode_transpose
      elseif x == 4 then
	grid_mode = grid_mode_heads
      end
    elseif y > 2 and y < 7 and z == 1 then
      -- recall buttons
      local m = get_grid_mask(x, y)
      if shift then
        save_mask(m)
      else
        recall_mask(m)
      end
      if ctrl then
        for i = 1, 4 do
          local mode = output_mode[i]
          if mode ~= mode_amp_in_stream and mode ~= mode_amp_in_sh then
            update_output(i)
          end
        end
      end
    elseif y == 7 and x == 1 then
      shift = z == 1
    elseif y == 8 then
      if x == 1 then
        ctrl = z == 1
      elseif x == 4 and z == 1 then
        sample_pitch()
      end
    end
  elseif x == 16 then
    if z == 1 then
      if 9 - y < scroll and scroll > 1 then
        scroll = 9 - y
      elseif 8 - y > scroll and scroll < 7 then
        scroll = 8 - y
      end
    end
  elseif grid_mode == grid_mode_play then
    local key_id = x + y * 16
    if z == 1 then
      local n = get_grid_note(x, y)
      -- print(string.format("pitch %d (%d)", n, pitch))
	if ctrl then
        mask[n] = not mask[n]
        mask_dirty = true
        for i = 1, 4 do
          local mode = output_mode[i]
          if mode ~= mode_amp_in_stream and mode ~= mode_amp_in_sh then
            update_output(i)
          end
        end
      else
        table.insert(held_keys, key_id)
        -- tab.print(held_keys)
        last_key = key_id
        -- print('last key: ' .. last_key)
        if clock_mode ~= clock_mode_trig then
          sample_pitch()
        end
        for i = 1, 4 do
          if output_mode[i] == mode_grid_stream  then
            update_output(i)
          end
        end
      end
    else
      -- TODO: this assumes there's no way a key ID could end up in held_keys twice; is that safe?
      if held_keys[#held_keys] == key_id then
        table.remove(held_keys)
        -- tab.print(held_keys)
        if #held_keys > 0 then
          last_key = held_keys[#held_keys]
          -- print('last key: ' .. last_key)
          if clock_mode ~= clock_mode_trig then
            sample_pitch()
          end
          for i = 1, 4 do
            if output_mode[i] == mode_grid_stream then
              update_output(i)
            end
          end
        end
      else
        for i = 1, #held_keys do
          if held_keys[i] == key_id then
            table.remove(held_keys, i)
          end
          -- tab.print(held_keys)
        end
      end
    end
  elseif grid_mode == grid_mode_mask then
    if z == 1 then
      local n = get_grid_note(x, y)
      local enable = not mask[n]
      local pitch = (n - 1 ) % 12 + 1
      for octave = 0, 7 do
	mask[pitch + octave * 12] = enable
      end
      mask_dirty = true
      if ctrl then
	-- TODO: you're cutting & pasting this a lot; should you use more '*_dirty' variables instead?
	for i = 1, 4 do
	  local mode = output_mode[i]
	  if mode ~= mode_amp_in_stream and mode ~= mode_amp_in_sh then
	    update_output(i)
	  end
	end
      end
    end
  elseif grid_mode == grid_mode_transpose then
    if x == 5 and y > 2 and y < 7 then
      -- TODO: make it possible to select none
      -- TODO: move these output buttons to the left so they can apply to other grid modes
      local output = y - 2
      local other_held = false
      -- local was_selected = output_selected[output]
      for i = 1, 4 do
	other_held = other_held or output_button_held[i]
      end
      if not other_held then
	output_selected = { false, false, false, false }
      end
      if z == 1 then
	output_selected[output] = true -- not was_selected
      end
      output_button_held[output] = z == 1
    elseif x > 5 and x < 16 and z == 1 then
      local any_selected = false
      for i = 1, 4 do
	any_selected = any_selected or output_selected[i]
      end
      if any_selected then
	local output_to_edit = output_last_edited % 4 + 1
	while not output_selected[output_to_edit] do
	  output_to_edit = output_to_edit % 4 + 1
	end
	params:set('output_' .. output_to_edit .. '_transpose', math.min(72, math.max(0, get_grid_note(x, y))) - 36)
	output_last_edited = output_to_edit
      end
    end
  elseif grid_mode == grid_mode_heads then
    -- TODO
  end
  dirty = true
end

local function update_freq(value)
  pitch_in_detected = value > 0
  if pitch_in_detected then
    pitch_in = musicutil.freq_to_note_num(value) + (pitch_in_octave - 2) * 12
    for i = 1, 4 do
      if output_mode[i] == mode_pitch_in_stream then
        update_output(i)
      end
    end
    dirty = true
  end
end

local function update_amp(value)
  amp_in = value
  for i = 1, 4 do
    if output_mode[i] == mode_amp_in_stream then
      update_output(i)
    end
  end
end

local function crow_setup()
  crow.clear()
  -- input modes will be set by params
  crow.input[1].change = function()
    if clock_mode ~= clock_mode_grid then
      sample_pitch()
    end
  end
  crow.input[2].stream = function(value)
    crow_pitch_in = math.floor(value * 12 + 0.5)
    print(string.format('crow input 2: %fV = %d', value, crow_pitch_in))
  end
  params:bang()
end

function init()
  
  redraw_metro = metro.init()
  redraw_metro.event = function(tick)
    if dirty then
      grid_redraw(tick)
      redraw()
      dirty = false
    elseif mask_dirty then -- blink
      grid_redraw(tick)
    end
  end
  redraw_metro:start(1 / 15)
  
  engine.amp_threshold(util.dbamp(-80))
  -- TODO: did you get rid of the 'clarity' threshold in the engine, or no?
  pitch_poll_l = poll.set('pitch_analyst_l', update_freq)
  pitch_poll_l.time = 1 / 8
  amp_poll_l = poll.set('amp_analyst_l', update_amp)
  amp_poll_l.time = 1 / 8
  
  for m = 1, 16 do
    saved_masks[m] = {}
    for i = 1, max_pitch do
      saved_masks[m][i] = false
    end
  end
  for i = 1, max_pitch do
    local pitch_class = (i - 1) % 12 + 1
    -- C maj pentatonic
    mask[i] = pitch_class == 2 or pitch_class == 4 or pitch_class == 7 or pitch_class == 9 or pitch_class == 12
  end
  save_mask(1)
  
  for i = 1, mem_size do
    memory[i] = 0
  end
  
  -- TODO: read from crow input 2
  -- TODO: and/or add a grid control
  params:add{
    type = 'option',
    id = 'shift_source',
    name = 'sr source',
    options = source_names,
    default = source_grid_pitch,
    action = function(value)
      source = value
      if source == source_crow then
	crow.input[2].mode('stream', 1/32) -- TODO: is this too fast? not fast enough? what about querying?
      else
	crow.input[2].mode('none')
      end
    end
  }
  params:add{
    type = 'number',
    id = 'loop_probability',
    name = 'loop probability',
    min = 0,
    max = 100,
    default = 0,
    controlspec = controlspec.new(0, 100, 'lin', 1, 0, '%'),
    formatter = function(param)
      return string.format('%d%%', param:get())
    end,
    action = function(value)
      loop_probability = value
    end
  }
  params:add{
    type = 'option',
    id = 'shift_clock',
    name = 'sr/s+h clock',
    options = clock_mode_names,
    default = clock_mode_trig_grid,
    action = function(value)
      clock_mode = value
      if clock_mode ~= clock_mode_grid then
	crow.input[1].mode('change', 2.0, 0.25, 'rising')
      else
	crow.input[1].mode('none')
      end
    end
  }
  params:add{
    type = 'number',
    id = 'pitch_in_octave',
    name = 'pitch in octave',
    min = -2,
    max = 2,
    default = 0,
    action = function(value)
      pitch_in_octave = value
    end
  }
  
  params:add_separator()
  
  for i = 1, n_heads do
    -- TODO: make this a 'real' class
    heads[i] = {
      pos = 1,
      offset_low = i * 3,
      offset_high = i * 3,
      move = function(self)
        local offset = self.offset_low
        if offset < self.offset_high then
          offset = math.random(self.offset_low, self.offset_high)
        end
        self.pos = (head - offset - 1) % mem_size + 1
      end
    }
    -- TODO: grid control over head position / random window
    params:add{
      type = 'number',
      id = 'head_' .. i .. '_offset_low',
      name = 'head ' .. i .. ' offset (low)',
      min = 0,
      max = mem_size - 1,
      default = i * 3,
      action = function(value)
        heads[i].offset_low = value
      end
    }
    params:add{
      type = 'number',
      id = 'head_' .. i .. '_offset_high',
      name = 'head ' .. i .. ' offset (high)',
      min = 0,
      max = mem_size - 1,
      default = i * 3,
      action = function(value)
        heads[i].offset_high = value
      end
    }
  end
  
  params:add{
    type = 'number',
    id = 'loop_length',
    name = 'loop length',
    min = 2,
    max = mem_size,
    default = mem_size,
    action = function(value)
      loop_length = value
    end
  }
  
  params:add_separator()
  
  for i = 1, 4 do
    params:add{
      type = 'option',
      id = 'output_' .. i .. '_mode',
      name = 'out ' .. i .. ' mode',
      options = output_mode_names,
      default = (i - 1) * 2 + 1,
      action = function(value)
        output_mode[i] = value
        update_output(i)
      end
    }
    params:add{
      type = 'control',
      id = 'output_' .. i .. '_slew',
      name = 'out ' .. i .. ' slew',
      controlspec = controlspec.new(1, 1000, 'exp', 1, 10, 'ms'),
      action = function(value)
        crow.output[i].slew = value / 1000
      end
    }
    -- TODO: grid control over output transpose
    params:add{
      type = 'number',
      id = 'output_' .. i .. '_transpose',
      name = 'out ' .. i .. ' transpose',
      min = -36,
      max = 36,
      default = 0,
      formatter = function(param)
        local value = param:get()
        if value > 0 then
          return string.format('+%d st', value)
        end
        return string.format('%d st', value)
      end,
      action = function(value)
        output_transpose[i] = value
        update_output(i)
      end
    }
  end
  
  pitch_poll_l:start()
  amp_poll_l:start()
  g.key = grid_key
  
  crow.add = crow_setup -- when crow is connected
  crow_setup() -- calls params:bang()
  
  dirty = true
end

function redraw()
  screen.clear()
  screen.stroke()
  for x = 1, mem_size do
    local pos = (head - mem_size - 1 + x) % mem_size + 1
    if pos == head or pos == heads[1].pos or pos == heads[2].pos or pos == heads[3].pos or pos == heads[4].pos then
      -- TODO: indicate output transposition too
      -- TODO: indicate randomization window for each head
      screen.level(15)
    else
      screen.level(2)
    end
    screen.line_width(1)
    screen.move((x - 1) * 4, 63 + scroll * 2 - snap(memory[pos] - 1)) -- TODO: is this expensive?
    screen.line_rel(4, 0)
    screen.stroke()
  end
  screen.update()
end

function cleanup()
  pitch_poll_l:stop()
  amp_poll_l:stop()
  redraw_metro:stop()
end
