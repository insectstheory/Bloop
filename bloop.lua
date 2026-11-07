-- bloop
--
-- Insects Theory 2026
-- ENC1 = repeats (loop decay, also active in playback only)
-- ENC2 = mod A (rate / pitch, speed only)
-- ENC3 = mod B (filter cutoff)
--
-- KEY2 = tap to go: rec -> play -> overdub
-- KEY3 = stop / play
-- KEY1 (hold) = ALT
-- KEY1 (tap)  = scrambler on/off (on by default; amount and slices in params)
-- ALT + KEY2        = cycle mode (normal / additive / sampler)
-- ALT + KEY3 (tap)  = undo (up to 4 levels)
-- ALT + KEY3 (hold) = clear loop
-- ALT + ENC1        = loop start point
-- ALT + ENC2        = loop length / trim
-- ALT + ENC3        = direction: turn left = reverse, turn right = forward
--
-- USB PEDAL (single footswitch acting as a keyboard, key learned on first press)
-- tap = rec/play/overdub | double tap in overdub = cancel | hold 0.7s = stop
-- hold 2.5s = clear | params > "pedal: learn key" to reassign the key


local MODES = {"normal", "additive", "sampler"}
local QUANT = {"off", "beat", "bar"}
local QUANT_BEATS = {0, 1, 4}
local SCRAMBLE_DIVS = {2, 4, 8, 16}

local LOOP_MAX = 30
local UNDO_DEPTH = 4
local SLOT_STRIDE = LOOP_MAX + 1
local HOLD_CLEAR = 0.8
local COPY_FADE = 0.005

local state = "empty"
local loop_len = 0
local phase = 0
local reverse = false
local alt = false
local wobble_val = 0

local undo_n = 0
local undo_head = 0

local msg, msg_until = "", 0

local k3_down, k3_alt, k3_cleared, k3_id = false, false, false, 0

local ui_metro, lfo_metro

local UI_FPS = 20
local INTRO_TIME = 5
local reel_angle, reel_spin = 0, 0
local vu_l, vu_r, vu = 0, 0, 0
local amp_polls = {}
local intro_start, intro_active = 0, false

local function flash(s)
  msg = s
  msg_until = util.time() + 1.2
end

local function mode()
  return MODES[params:get("mode")]
end

local function each_voice(fn)
  fn(1)
  fn(2)
end

local function apply_rate()
  local first = (state == "recording")
  local mag = first and 1.0 or params:get("mod_a_rate")
  local dir = (reverse and not first) and -1 or 1
  local r = dir * mag * (1 + wobble_val)
  each_voice(function(v) softcut.rate(v, r) end)
end

local function lfo_tick()
  local depth = params:get("wobble")
  if depth > 0 then
    local t = util.time()
    wobble_val = depth * 0.03 * (math.sin(t * 2 * math.pi * 0.4)
      + 0.4 * math.sin(t * 2 * math.pi * 1.3 + 1.7))
    apply_rate()
  elseif wobble_val ~= 0 then
    wobble_val = 0
    apply_rate()
  end
end

local function loop_bounds()
  if loop_len <= 0 then return 0, LOOP_MAX end
  local s = params:get("start_point") * loop_len
  local len = math.max(0.05, params:get("loop_trim") * (loop_len - s))
  return s, math.min(s + len, loop_len)
end

local function apply_loop_bounds(force)
  if loop_len <= 0 then return end
  local s, e = loop_bounds()
  each_voice(function(v)
    softcut.loop_start(v, s)
    softcut.loop_end(v, e)
  end)
  if force or phase < s or phase > e then
    each_voice(function(v) softcut.position(v, s) end)
  end
end

local scramble_on = false
local scramble_idx = 0
local scramble_step = 0
local scramble_pattern = {}
local scramble_clock
local k1_used, k1_t = false, 0

local function scramble_div()
  return SCRAMBLE_DIVS[params:get("scramble_div")]
end

local function scramble_new_pattern()
  local n = scramble_div()
  scramble_pattern = {}
  for i = 1, n do scramble_pattern[i] = i - 1 end
  for i = n, 2, -1 do
    local j = math.random(i)
    scramble_pattern[i], scramble_pattern[j] = scramble_pattern[j], scramble_pattern[i]
  end
  scramble_step = 0
end

local function scramble_jump(s, slice, idx)
  local pos = reverse and (s + (idx + 1) * slice - 0.01) or (s + idx * slice)
  softcut.position(1, pos)
end

local function scramble_run()
  while true do
    local playing = (state == "playing" or state == "overdubbing")
    if not (scramble_on and playing and loop_len > 0) then
      clock.sleep(0.05)
    else
      local s, e = loop_bounds()
      local n = scramble_div()
      local slice = (e - s) / n
      local amount = params:get("scramble")
      local nxt = (scramble_idx + 1) % n
      if math.random() < math.abs(amount) then
        if amount < 0 then
          nxt = math.random(n) - 1
        else
          scramble_step = scramble_step % n + 1
          nxt = scramble_pattern[scramble_step]
        end
      end
      scramble_idx = nxt
      scramble_jump(s, slice, nxt)
      local mag = math.max(0.1, params:get("mod_a_rate") * (1 + wobble_val))
      clock.sleep(slice / mag)
    end
  end
end

local function set_scramble(on)
  scramble_on = on
  if on then
    local s, e = loop_bounds()
    local n = scramble_div()
    scramble_idx = math.max(0, math.min(n - 1, math.floor((phase - s) / ((e - s) / n))))
    scramble_new_pattern()
  else
  end
  flash(on and "scramble on" or "scramble off")
end

local function update_routing()
  local repeats = params:get("repeats")

  if state == "empty" or state == "stopped" then
    each_voice(function(v)
      softcut.play(v, 0)
      softcut.rec(v, 0)
    end)
    return
  end

  if state == "recording" then
    softcut.play(1, 1)
    softcut.rec(1, 1)
    softcut.rec_level(1, 1.0)
    softcut.pre_level(1, 1.0)
    softcut.play(2, 0)
    softcut.rec(2, 0)
    softcut.level_cut_cut(1, 2, 0)
    softcut.level_input_cut(1, 2, 0)
    softcut.level_input_cut(2, 2, 0)
    return
  end

  local od = (state == "overdubbing")
  softcut.play(1, 1)
  softcut.play(2, 1)

  if mode() == "additive" then
    softcut.rec(1, 0)
    softcut.rec(2, 1)
    softcut.rec_level(2, 1.0)
    softcut.pre_level(2, 0.0)
    softcut.level_cut_cut(1, 2, repeats)
    local g = od and 1.0 or 0.0
    softcut.level_input_cut(1, 2, g)
    softcut.level_input_cut(2, 2, g)
  else
    softcut.rec(1, 1)
    softcut.rec_level(1, od and 1.0 or 0.0)
    softcut.pre_level(1, repeats)
    softcut.rec(2, 0)
    softcut.level_cut_cut(1, 2, 0)
    softcut.level_input_cut(1, 2, 0)
    softcut.level_input_cut(2, 2, 0)
  end
end

local function post(name)
  return softcut["post_filter_" .. name] or softcut["filter_" .. name]
end

local function set_cutoff(v) post("fc")(1, v) end
local function set_rq(v) post("rq")(1, v) end

local function apply_mode()
  post("dry")(1, 0.0)
  post("lp")(1, 1.0)
  post("hp")(1, 0.0)
  post("bp")(1, 0.0)
  post("br")(1, 0.0)
  set_cutoff(params:get("mod_b_cutoff"))
  set_rq(params:get("filter_rq"))
  update_routing()
end

local function slot_off(i)
  return (i - 1) * SLOT_STRIDE
end

local function push_undo()
  if loop_len <= 0 then return end
  undo_head = (undo_head % UNDO_DEPTH) + 1
  softcut.buffer_copy_mono(1, 2, 0, slot_off(undo_head), loop_len, COPY_FADE, 0)
  undo_n = math.min(undo_n + 1, UNDO_DEPTH)
end

local function do_undo()
  if undo_n == 0 or loop_len <= 0 then
    flash("no undo")
    return
  end
  softcut.buffer_copy_mono(2, 1, slot_off(undo_head), 0, loop_len, COPY_FADE, 0)
  undo_head = (undo_head - 2) % UNDO_DEPTH + 1
  undo_n = undo_n - 1
  flash("undo")
end

local function start_record()
  undo_n, undo_head = 0, 0
  loop_len = 0
  phase = 0
  softcut.buffer_clear_region_channel(1, 0, LOOP_MAX, 0, 0)
  each_voice(function(v)
    softcut.loop_start(v, 0)
    softcut.loop_end(v, LOOP_MAX)
    softcut.position(v, 0)
  end)
  state = "recording"
  apply_rate()
  update_routing()
end

local function stop_record_start_loop()
  local len = phase
  if len < 0.1 then
    state = "empty"
    update_routing()
    flash("too short")
    return
  end
  local q = QUANT_BEATS[params:get("quantize")]
  if q > 0 then
    local unit = clock.get_beat_sec() * q
    len = math.max(1, math.floor(len / unit + 0.5)) * unit
  end
  loop_len = math.min(len, LOOP_MAX)
  state = "playing"
  apply_rate()
  update_routing()
  apply_loop_bounds(true)
end

local function start_overdub()
  if mode() == "sampler" then
    start_record()
    return
  end
  push_undo()
  state = "overdubbing"
  update_routing()
end

local function stop_overdub()
  state = "playing"
  update_routing()
end

local function stop_loop()
  state = "stopped"
  update_routing()
end

local function resume_loop()
  state = "playing"
  update_routing()
end

local function clear_loop()
  state = "empty"
  loop_len = 0
  phase = 0
  undo_n, undo_head = 0, 0
  update_routing()
  softcut.buffer_clear_region_channel(1, 0, LOOP_MAX, 0, 0)
  each_voice(function(v)
    softcut.loop_start(v, 0)
    softcut.loop_end(v, LOOP_MAX)
    softcut.position(v, 0)
  end)
  flash("cleared")
end

local function main_action()
  if state == "empty" then
    start_record()
  elseif state == "stopped" then
    resume_loop()
  elseif state == "recording" then
    stop_record_start_loop()
  elseif state == "playing" then
    start_overdub()
  elseif state == "overdubbing" then
    stop_overdub()
  end
end

local PEDAL_DOUBLE = 0.35
local PEDAL_HOLD = 0.7
local PEDAL_CLEAR = 2.5

local pedal_code = nil
local pedal_learning = false
local pedal_down, pedal_id = false, 0
local pedal_last, pedal_last_od, pedal_pre = 0, false, "empty"
local pedal_file

local function pedal_save()
  pcall(function() tab.save({code = pedal_code}, pedal_file) end)
end

local function pedal_load()
  local ok, t = pcall(tab.load, pedal_file)
  if ok and type(t) == "table" then pedal_code = t.code end
end

local function pedal_press()
  if intro_active then return end
  local now = util.time()
  pedal_id = pedal_id + 1
  local id = pedal_id
  pedal_down = true

  if state == "overdubbing" and pedal_last_od and now - pedal_last < PEDAL_DOUBLE then
    pedal_last_od = false
    stop_overdub()
    do_undo()
    redraw()
    return
  end

  pedal_pre = state
  main_action()
  pedal_last = now
  pedal_last_od = (state == "overdubbing")

  clock.run(function()
    clock.sleep(PEDAL_HOLD)
    if not (pedal_down and pedal_id == id) then return end
    if state == "recording" then
      clear_loop()
      redraw()
      return
    end
    if pedal_pre == "playing" and state == "overdubbing" then
      stop_overdub()
      do_undo()
    end
    if state == "playing" or state == "overdubbing" then
      stop_loop()
      flash("stop")
    end
    redraw()
    clock.sleep(PEDAL_CLEAR - PEDAL_HOLD)
    if pedal_down and pedal_id == id and state ~= "empty" then
      clear_loop()
      redraw()
    end
  end)
end

local function pedal_release()
  pedal_down = false
end

local function pedal_key(code, value)
  if value == 2 then return end
  if value == 1 and (pedal_learning or pedal_code == nil) then
    pedal_code = code
    pedal_learning = false
    pedal_save()
    flash("pedal: " .. tostring(code))
    redraw()
    return
  end
  if code ~= pedal_code then return end
  if value == 1 then pedal_press() else pedal_release() end
end

function key(n, z)
  if intro_active then return end
  if n == 1 then
    alt = (z == 1)
    if z == 1 then
      k1_used, k1_t = false, util.time()
    elseif not k1_used and util.time() - k1_t < 0.5 then
      local on = not scramble_on
      set_scramble(on)
      params:set("scramble_on", on and 1 or 0, true)
      print("bloop: scrambler " .. (on and "on" or "off"))
    end

  elseif n == 2 then
    if z == 1 then
      if alt then
        k1_used = true
        params:set("mode", params:get("mode") % #MODES + 1)
      else
        main_action()
      end
    end

  elseif n == 3 then
    if z == 1 then
      k3_down, k3_alt, k3_cleared = true, alt, false
      k3_id = k3_id + 1
      if alt then
        k1_used = true
        local id = k3_id
        clock.run(function()
          clock.sleep(HOLD_CLEAR)
          if k3_down and k3_alt and k3_id == id then
            k3_cleared = true
            clear_loop()
          end
        end)
      elseif state == "playing" then
        stop_loop()
      elseif state == "stopped" then
        resume_loop()
      end
    else
      k3_down = false
      if k3_alt and not k3_cleared then do_undo() end
      k3_alt = false
    end
  end
  redraw()
end

function enc(n, d)
  if intro_active then return end
  if alt then
    k1_used = true
    if n == 1 then
      params:delta("start_point", d)
    elseif n == 2 then
      params:delta("loop_trim", d)
    elseif n == 3 and d ~= 0 then
      reverse = (d < 0)
      apply_rate()
    end
  else
    if n == 1 then
      params:delta("repeats", d)
    elseif n == 2 then
      params:delta("mod_a_rate", d)
    elseif n == 3 then
      params:delta("mod_b_cutoff", d * 2)
    end
  end
  redraw()
end

local function circle(x, y, r)
  screen.move(x + r, y)
  screen.circle(x, y, r)
end

local function anim_tick(dt)
  local moving = (state == "playing" or state == "overdubbing" or state == "recording")
  local target = 0
  if moving then
    local dir = (reverse and state ~= "recording") and -1 or 1
    local mag = (state == "recording") and 1.0 or params:get("mod_a_rate")
    target = dir * mag * 5
  end
  reel_spin = reel_spin + (target - reel_spin) * 0.25
  reel_angle = (reel_angle + reel_spin * dt) % (2 * math.pi)
  vu = math.max(vu_l, vu_r)
end

local function draw_reel(cx, cy, r)
  local lv
  if state == "recording" then
    lv = (math.floor(util.time() * 4) % 2 == 0) and 15 or 7
  elseif state == "overdubbing" then
    lv = 8 + math.floor(7 * math.abs(math.sin(util.time() * 5)))
  elseif state == "playing" then
    lv = 10
  else
    lv = 3
  end
  screen.level(lv)
  circle(cx, cy, r)
  screen.stroke()
  for i = 0, 2 do
    local a = reel_angle + i * 2 * math.pi / 3
    screen.move(cx, cy)
    screen.line(cx + math.cos(a) * (r - 2), cy + math.sin(a) * (r - 2))
    screen.stroke()
  end
  screen.level(15)
  circle(cx, cy, 1 + math.floor(vu * 3))
  screen.fill()
end

local INTRO_FONT = 8

local function ease_out_back(x)
  local c1, c3 = 1.70158, 2.70158
  return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function draw_intro()
  local t = (util.time() - intro_start) / INTRO_TIME
  if t >= 1 then
    intro_active = false
    return
  end
  local fade = math.min(1, (1 - t) / 0.15)
  local function L(x) return math.max(0, math.floor(x * fade + 0.5)) end

  local water = 40

  for i = 1, 9 do
    local p = (t * (0.8 + (i % 4) * 0.25) + i * 0.37) % 1
    local x = 8 + ((i * 53) % 112) + math.sin(t * 9 + i) * 3
    screen.level(L(3 + (i % 3) * 2))
    circle(x, 66 - p * 70, 1 + (i % 3))
    screen.stroke()
  end

  if t < 0.2 then
    local g = (t / 0.2) ^ 2
    screen.level(L(15))
    circle(64, -4 + g * (water - 8), 2)
    screen.fill()
  end

  for k = 0, 2 do
    local rt = (t - 0.2 - k * 0.07) / 0.4
    if rt > 0 and rt < 1 then
      screen.level(L(math.floor(12 * (1 - rt))))
      circle(64, water - 6, 2 + rt * 30)
      screen.stroke()
    end
  end

  local word = "bloop"
  screen.font_face(INTRO_FONT)
  screen.font_size(18)
  local x0 = 64 - screen.text_extents(word) / 2
  for i = 1, #word do
    local lt = (t - (0.2 + i * 0.09)) / 0.16
    if lt > 0 then
      lt = math.min(1, lt)
      local dy = -16 * (1 - ease_out_back(lt))
      if t > 0.7 then dy = dy + math.sin(t * 14 + i * 1.3) * 1.2 end
      screen.level(L(15))
      screen.move(x0 + screen.text_extents(word:sub(1, i - 1)), water + 6 + dy)
      screen.text(word:sub(i, i))
    end
  end

  screen.font_face(1)
  screen.font_size(8)
  if t > 0.72 then
    screen.level(L(6))
    screen.move(64, 60)
    screen.text_center("micro looper")
  end
end

function redraw()
  screen.clear()
  screen.aa(0)
  if intro_active then
    draw_intro()
    if intro_active then
      screen.update()
      return
    end
  end
  screen.font_size(8)

  screen.level(15)
  screen.move(0, 8)
  screen.text("bloop [" .. mode() .. "]")
  screen.level(alt and 15 or 2)
  screen.move(100, 8)
  screen.text("ALT")
  if scramble_on then
    screen.level(15)
    screen.move(82, 8)
    screen.text("scr")
  end

  screen.move(0, 24)
  if state == "recording" then
    screen.level((math.floor(util.time() * 4) % 2 == 0) and 15 or 6)
  else
    screen.level(4)
  end
  screen.text("rec")
  screen.move(30, 24)
  screen.level(state == "overdubbing" and 15 or 4)
  screen.text("overdub")
  screen.move(80, 24)
  screen.level(state == "playing" and 15 or 4)
  screen.text("play")
  if undo_n > 0 then
    screen.move(112, 24)
    screen.level(6)
    screen.text("u" .. undo_n)
  end

  screen.level(3)
  screen.move(0, 29)
  screen.line(128, 29)
  screen.stroke()
  if state == "recording" then
    screen.level(15)
    screen.move(0, 29)
    screen.line(128 * math.min(1, phase / LOOP_MAX), 29)
    screen.stroke()
  elseif loop_len > 0 then
    local s, e = loop_bounds()
    screen.level(8)
    screen.move(128 * s / loop_len, 29)
    screen.line(128 * e / loop_len, 29)
    screen.stroke()
    screen.level(15)
    local xp = 128 * math.min(1, phase / loop_len)
    screen.move(xp, 26)
    screen.line_rel(0, 6)
    screen.stroke()
  end

  screen.level(10)
  screen.move(0, 40)
  screen.text("repeats " .. string.format("%.2f", params:get("repeats")))
  if util.time() < msg_until then
    screen.level(15)
    screen.move(70, 40)
    screen.text(msg)
  end

  screen.level(15)
  if alt then
    screen.move(0, 50)
    screen.text("start " .. string.format("%.2f", params:get("start_point")))
    screen.move(64, 50)
    screen.text("trim " .. string.format("%.2f", params:get("loop_trim")))
    screen.move(0, 60)
    screen.text(reverse and "<< reverse" or ">> forward")
    screen.move(64, 60)
    screen.text("K3:clr")
  else
    screen.move(0, 50)
    screen.text("speed " .. string.format("%.2f", params:get("mod_a_rate")) ..
      (reverse and " REV" or ""))
    screen.move(0, 60)
    screen.text("cutoff " .. math.floor(params:get("mod_b_cutoff")) .. "hz")
  end

  draw_reel(117, 51, 9)

  screen.update()
end

function init()
  print("bloop: caricato da " .. tostring(norns.state.script))
  audio.level_adc_cut(1.0)
  for i = 1, 3 do
    norns.enc.sens(i, 1)
    norns.enc.accel(i, true)
  end

  softcut.buffer_clear()

  for v = 1, 2 do
    softcut.enable(v, 1)
    softcut.buffer(v, 1)
    softcut.pan(v, 0.0)
    softcut.rate(v, 1.0)
    softcut.rate_slew_time(v, 0.05)
    softcut.level_slew_time(v, 0.05)
    softcut.fade_time(v, 0.01)
    softcut.recpre_slew_time(v, 0.01)
    softcut.loop(v, 1)
    softcut.loop_start(v, 0)
    softcut.loop_end(v, LOOP_MAX)
    softcut.position(v, 0)
    softcut.play(v, 0)
    softcut.rec(v, 0)
    softcut.rec_level(v, 1.0)
    softcut.pre_level(v, 1.0)
  end
  softcut.level(1, 1.0)
  softcut.level(2, 0.0)

  softcut.level_input_cut(1, 1, 1.0)
  softcut.level_input_cut(2, 1, 1.0)
  softcut.level_input_cut(1, 2, 0.0)
  softcut.level_input_cut(2, 2, 0.0)

  softcut.phase_quant(1, 0.01)
  softcut.event_phase(function(voice, pos)
    if voice ~= 1 then return end
    phase = pos
    if state == "recording" and pos >= LOOP_MAX - 0.1 then
      stop_record_start_loop()
      flash("max len")
    end
  end)
  softcut.poll_start_phase()

  params:add_separator("bloop")

  params:add_option("mode", "mode", MODES, 1)
  params:set_action("mode", function() apply_mode(); redraw() end)

  params:add_control("repeats", "repeats", controlspec.new(0, 1, "lin", 0.01, 1.0))
  params:set_action("repeats", function() update_routing() end)

  params:add_control("mod_a_rate", "mod a: speed/pitch", controlspec.new(0.1, 2, "lin", 0.01, 1.0))
  params:set_action("mod_a_rate", function() apply_rate() end)

  params:add_control("mod_b_cutoff", "mod b: filter cutoff", controlspec.new(60, 12000, "exp", 1, 12000, "hz"))
  params:set_action("mod_b_cutoff", function(v) set_cutoff(v) end)

  params:add_control("filter_rq", "filter resonance (rq)", controlspec.new(0.1, 2.0, "lin", 0.01, 0.6))
  params:set_action("filter_rq", function(v) set_rq(v) end)

  params:add_control("start_point", "start point", controlspec.new(0, 0.95, "lin", 0.01, 0.0))
  params:set_action("start_point", function() apply_loop_bounds(false) end)

  params:add_control("loop_trim", "loop length (trim)", controlspec.new(0.05, 1.0, "lin", 0.01, 1.0))
  params:set_action("loop_trim", function() apply_loop_bounds(false) end)

  params:add_option("quantize", "quantize loop length", QUANT, 1)

  params:add_control("scramble", "scrambler amount", controlspec.new(-1, 1, "lin", 0.01, 0.6))
  params:add_option("scramble_div", "scrambler slices", {"2", "4", "8", "16"}, 3)
  params:set_action("scramble_div", function()
    if scramble_on then scramble_new_pattern() end
  end)
  params:add_binary("scramble_on", "scrambler on", "toggle", 1)
  params:set_action("scramble_on", function(v)
    if (v == 1) ~= scramble_on then set_scramble(v == 1) end
  end)

  params:add_control("wobble", "stability (wobble)", controlspec.new(0, 1, "lin", 0.01, 0.0))

  params:add_control("out_level", "loop output level", controlspec.new(0, 2, "lin", 0.01, 1.0))
  params:set_action("out_level", function(v) softcut.level(1, v) end)

  params:add_option("comp", "output compressor", {"off", "on"}, 1)
  params:set_action("comp", function(v) audio.comp_mix(v - 1) end)

  pedal_file = norns.state.data .. "pedal.data"
  pedal_load()
  params:add_trigger("pedal_learn", "pedal: learn key")
  params:set_action("pedal_learn", function()
    pedal_learning = true
    flash("press pedal")
  end)
  keyboard.code = pedal_key

  for i, side in ipairs({"l", "r"}) do
    local p = poll.set("amp_in_" .. side)
    p.time = 1 / 20
    p.callback = function(v)
      local x = math.min(1, v * 4)
      if side == "l" then vu_l = vu_l * 0.5 + x * 0.5 else vu_r = vu_r * 0.5 + x * 0.5 end
    end
    p:start()
    amp_polls[i] = p
  end

  ui_metro = metro.init(function()
    anim_tick(1 / UI_FPS)
    redraw()
  end, 1 / UI_FPS, -1)
  ui_metro:start()
  lfo_metro = metro.init(lfo_tick, 1 / 30, -1)
  lfo_metro:start()
  scramble_clock = clock.run(scramble_run)

  params:bang()
  apply_mode()
  apply_rate()
  intro_start = util.time()
  intro_active = true
  redraw()
end

function cleanup()
  for _, p in ipairs(amp_polls) do p:stop() end
  if ui_metro then ui_metro:stop() end
  if lfo_metro then lfo_metro:stop() end
  if scramble_clock then clock.cancel(scramble_clock) end
  pcall(function() softcut.poll_stop_phase() end)
end
