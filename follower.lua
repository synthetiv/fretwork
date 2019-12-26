-- follower
-- follow pitch, quantize, etc...

engine.name = 'Analyst'

local pitch_poll_l
local amp_poll_l
local pitch_in = 0
local mask = {}
local saved_masks = {}
local max_pitch = 96

local memory = {}
local mem_size = 32
local head = 1
local heads = {}
local n_heads = 4

local mix = 100
local clock_mode = 3

local output_transpose = { 0, 0, 0, 0 }
local output_mode = { 1, 1, 1, 1 }
local output_note = { 0, 0, 0, 0 }

local g = grid.connect()
local held_keys = {}

local shift = false
local ctrl = false
local alt = false
local cmd = false
local scroll = 1

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

local function recall_mask(m)
  for i = 1, max_pitch do
    mask[i] = saved_masks[m][i]
  end
end

local function save_mask(m)
  for i = 1, max_pitch do
    saved_masks[m][i] = mask[i]
  end
end

local function get_grid_note(x, y)
  return x - 4 + (7 + scroll - y) * 5
end

local function get_grid_id_note(id)
  local x = id % 16 + 1
  local y = math.floor(id / 16)
  return get_grid_note(x, y)
end

local function update_output(out)
  local mode = output_mode[out]
  local volts = 0
  if mode == 9 or mode == 10 then -- pitch in
    output_note[out] = snap(quantize(pitch_in) + output_transpose[out] - 1)
    volts = output_note[out] / 12 - 2
  elseif mode == 11 or mode == 12 then -- amp in
    output_note[out] = 0
    volts = amp_in * 5
  elseif mode == 13 or mode == 14 then -- grid
    if #held_keys < 1 then
      -- TODO: keep track of last_key instead, so this output mode can be updated when scale changes
      return
    end
    output_note[out] = snap(get_grid_id_note(held_keys[#held_keys]) + output_transpose[out] - 1)
    volts = output_note[out] / 12 - 2
  else
    local is_pitch = mode % 2 > 0
    local out_head = math.ceil(mode / 2)
    if is_pitch then
      output_note[out] = snap(memory[heads[out_head].pos].pitch + output_transpose[out] - 1)
      volts = output_note[out] / 12 - 2
    else
      output_note[out] = 0
      volts = memory[heads[out_head].pos].amp * 5
    end
  end
  dirty = true
  crow.output[out].volts = volts
end

local function sample_pitch(pitch, force_enable)
  local amp = amp_in -- TODO: other amp sources...?
  head = head % mem_size + 1
  for i = 1, 4 do
    heads[i]:move()
  end
  if pitch <= 0 or math.random(0, 99) >= mix then
    pitch = memory[heads[4].pos].pitch -- feed back an un-snapped value
    amp = memory[heads[4].pos].amp
  end
  memory[head] = {
    pitch = pitch,
    amp = amp
  }
  if force_enable then
    mask[quantize(pitch)] = true
  end
  -- TODO: move this?
  for i = 1, 4 do
    update_output(i)
  end
  dirty = true
end

local function grid_redraw()
  for x = 1, 16 do
    for y = 1, 8 do
      if x < 4 and y > 3 and y < 7 then
        g:led(x, y, 2)
      elseif x == 1 and y == 7 then
        g:led(x, y, shift and 4 or 2)
      elseif x == 1 and y == 8 then
        g:led(x, y, ctrl and 4 or 2)
      elseif x == 2 and y == 8 then
        g:led(x, y, alt and 4 or 2)
      elseif x == 3 and y == 8 then
        g:led(x, y, cmd and 4 or 2)
      elseif x > 4 and x < 16 then
        local n = get_grid_note(x, y)
        local pitch = (n - 1) % 12 + 1
        -- TODO: only show heads/outputs that are in use
        -- TODO: indicate output transposition on the grid
        -- if quantize(pitch_in) == n then
          -- g:led(x, y, 10)
        -- elseif snap(memory[head].pitch) == n then
          -- g:led(x, y, 9)
        if output_note[1] == n then
          g:led(x, y, 7)
        elseif output_note[2] == n then
          g:led(x, y, 7)
        elseif output_note[3] == n then
          g:led(x, y, 7)
        elseif output_note[4] == n then
          g:led(x, y, 7)
        elseif mask[n] then
          g:led(x, y, 4)
        elseif pitch == 1 or pitch == 3 or pitch == 4 or pitch == 6 or pitch == 8 or pitch == 9 or pitch == 11 then
          g:led(x, y, 2)
        else
          g:led(x, y, 0)
        end
      elseif x == 16 then
        if 9 - y == scroll or 8 - y == scroll then
          g:led(x, y, 2)
        else
          g:led(x, y, 1)
        end
      end
    end
  end
  g:refresh()
end

local function grid_key(x, y, z)
  if x < 5 then
    if x < 4 and y > 3 and y < 7 then
      local m = x + (y - 4) * 3
      if shift then
        save_mask(m)
      else
        recall_mask(m)
      end
    elseif y == 7 and x == 1 then
      shift = z == 1
    elseif y == 8 then
      if x == 1 then
        ctrl = z == 1
      elseif x == 2 then
        alt = z == 1
      elseif x == 3 then
        cmd = z == 1
      elseif x == 4 and z == 1 then
        -- TODO: update output? no?
        if #held_keys > 0 then
          sample_pitch(get_grid_id_note(held_keys[#held_keys]))
        else
          -- sample_pitch(pitch_in)
          sample_pitch(0) -- FIXME
        end
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
  else
    local key_id = x + y * 16
    if z == 1 then
      local n = get_grid_note(x, y)
      local pitch = (n - 1 ) % 12 + 1
      -- print(string.format("pitch %d (%d)", n, pitch))
      if shift then
        local enable = not mask[n]
        for o = 0, 7 do
          mask[pitch + o * 12] = enable
        end
        if ctrl then
          for i = 1, 4 do
            update_output(i)
          end
        end
      elseif ctrl then
        mask[n] = not mask[n]
        for i = 1, 4 do
          update_output(i)
        end
      else
        if clock_mode > 1 then
          sample_pitch(n, cmd)
        end
        for i = 1, 4 do
          if output_mode[i] == 14 then
            update_output(i)
          end
        end
        table.insert(held_keys, key_id)
      end
    else
      -- TODO: this assumes there's no way a key ID could end up in held_keys twice...
      if held_keys[#held_keys] == key_id then
        table.remove(held_keys)
        if #held_keys > 0 then
          if clock_mode > 1 then
            sample_pitch(get_grid_id_note(held_keys[#held_keys]))
          end
        end
      else
        for i = 1, #held_keys do
          if held_keys[i] == key_id then
            table.remove(held_keys, i)
          end
        end
      end
    end
  end
  dirty = true
end

local function update_freq(value)
  if value <= 0 then
    pitch_in = 0
  else
    local ratio = value / 27.5; -- a very low A
    pitch_in = 12 * math.log(ratio) / math.log(2)
  end
  -- print(pitch_in)
  for i = 1, 4 do
    -- TODO: do this for amp input too
    if output_mode[i] == 10 then
      update_output(i)
    end
  end
  dirty = true
end

function init()
  
  redraw_metro = metro.init()
  redraw_metro.event = function()
    if dirty then
      grid_redraw()
      redraw()
      dirty = false
    end
  end
  redraw_metro:start(1 / 15)
  
  engine.amp_threshold(util.dbamp(-80))
  -- TODO: did you get rid of the 'clarity' threshold in the engine, or no?
  pitch_poll_l = poll.set('pitch_analyst_l', update_freq)
  pitch_poll_l.time = 1 / 8
  amp_poll_l = poll.set('amp_analyst_l', function(value)
    amp_in = value
  end)
  amp_poll_l.time = 1 / 8
  
  for i = 1, max_pitch do
    local pitch_class = (i - 1) % 12 + 1
    mask[i] = pitch_class == 1 or pitch_class == 4 or pitch_class == 8 or pitch_class == 11
  end
  
  for m = 1, 9 do
    saved_masks[m] = {}
    for i = 1, max_pitch do
      saved_masks[m][i] = false
    end
  end
  
  for i = 1, mem_size do
    memory[i] = {
      pitch = 0,
      amp = 0
    }
  end
  
  -- TODO: there might be a saner way to label this; it's really a probability
  -- TODO: read from crow input 2
  -- TODO: and/or add a grid control
  params:add{
    type = 'control',
    id = 'input_mix',
    name = 'input mix (loop - ext)',
    controlspec = controlspec.new(0, 100, 'lin', 1, 100, '%'),
    action = function(value)
      mix = value
    end
  }
  
  params:add{
    type = 'option',
    id = 'shift_clock',
    name = 'shift clock',
    options = {
      'trig in',
      'grid',
      'trig in OR grid'
    },
    default = 3,
    action = function(value)
      clock_mode = value
    end
  }
  
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
    params:add{
      type = 'control',
      id = 'head_' .. i .. '_offset_low',
      name = 'head ' .. i .. ' offset (low)',
      controlspec = controlspec.new(0, mem_size - 2, 'lin', 1, i * 3),
      action = function(value)
        heads[i].offset_low = value
      end
    }
    params:add{
      type = 'control',
      id = 'head_' .. i .. '_offset_high',
      name = 'head ' .. i .. ' offset (high)',
      controlspec = controlspec.new(0, mem_size - 2, 'lin', 1, i * 3),
      action = function(value)
        heads[i].offset_high = value
      end
    }
  end
  
  for i = 1, 4 do
    params:add{
      type = 'option',
      id = 'output_' .. i .. '_mode',
      name = 'out ' .. i .. ' mode',
      options = {
        'head 1 pitch',
        'head 1 amp',
        'head 2 pitch',
        'head 2 amp',
        'head 3 pitch',
        'head 3 amp',
        'head 4 pitch',
        'head 4 amp',
        'pitch in s+h',
        'pitch in stream',
        'amp in s+h',
        'amp in stream',
        'grid s+h',
        'grid stream'
      },
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
    params:add{
      type = 'control',
      id = 'output_' .. i .. '_transpose',
      name = 'out ' .. i .. ' transpose',
      controlspec = controlspec.new(-24, 24, 'lin', 1, 0, 'st'),
      action = function(value)
        output_transpose[i] = value
        update_output(i)
      end
    }
  end
  
  params:bang()
  
  pitch_poll_l:start()
  amp_poll_l:start()
  g.key = grid_key
  
  crow.clear()
  
  crow.input[1].mode('change', 2.0, 0.25, 'rising')
  crow.input[1].change = function()
    if clock_mode == 1 or clock_mode == 3 then
      if #held_keys > 0 then
        sample_pitch(get_grid_id_note(held_keys[#held_keys]))
      else
        -- sample_pitch(pitch_in)
        sample_pitch(0) -- FIXME
      end
    end
  end
  
  dirty = true
end

function redraw()
  screen.clear()
  screen.stroke()
  for x = 1, mem_size do
    local pos = (head - mem_size - 1 + x) % mem_size + 1
    if pos == head or pos == heads[1].pos or pos == heads[2].pos or pos == heads[3].pos or pos == heads[4].pos then
      screen.level(15)
    else
      screen.level(2)
    end
    screen.line_width(1)
    screen.move((x - 1) * 4, 63 + scroll * 2 - snap(memory[pos].pitch)) -- TODO: is this expensive?
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