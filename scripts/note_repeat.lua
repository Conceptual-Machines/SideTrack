-- @description SideTrack: Note Repeat Operator
-- @author Conceptual Machines
-- @version 1.0.0
-- @about
--   Bitwig-style note repeat operator.
--   Creates repetitions of selected notes with velocity controlled by a curve.

local r = reaper

-- Check for ReaImGui
if not r.ImGui_CreateContext then
  r.ShowMessageBox("ReaImGui is required for this script.\nInstall via ReaPack.", "SideTrack", 0)
  return
end

-- Constants
local CURVE_RESOLUTION = 100

-- Colors
local COLORS = {
  background = 0x1E1E22FF,
  grid = 0x383840FF,
  grid_major = 0x484850FF,
  curve = 0x5B9FD4FF,
  node = 0xFF8822FF,
  node_hover = 0xFFBB66FF,
  node_endpoint = 0x5B9FD4FF,
  text = 0xAAAAAAFF,
  preview_bar = 0x5B9FD488,
}

-- Grid divisions (in fractions of a bar)
local GRID_OPTIONS = {
  { label = "1/4",  value = 0.25 },
  { label = "1/8",  value = 0.125 },
  { label = "1/16", value = 0.0625 },
  { label = "1/32", value = 0.03125 },
}

-- State
local state = {
  -- Velocity curve
  vel_points = {{x = 0, y = 1}, {x = 1, y = 0.3}},
  vel_curves = {0.5},
  -- Timing curve (Y = position in time span, 0-1)
  time_points = {{x = 0, y = 0}, {x = 1, y = 1}},
  time_curves = {0},
  -- Active curve for editing
  active_curve = "velocity",  -- "velocity" or "timing"
  -- Drag state
  hover_node = -1,
  drag_node = -1,
  hover_segment = -1,
  drag_segment = -1,
  drag_start_curve = 0,
  drag_start_mouse_y = 0,
  -- Settings
  repetitions = 4,
  grid_idx = 2,  -- Default 1/8
  selected_notes = {},
  preview_velocities = {},
  preview_timings = {},
}

--------------------------------------------------------------------------------
-- Curve Math
--------------------------------------------------------------------------------

local function sort_points_by_x(points)
  local sorted = {}
  for i, pt in ipairs(points) do
    sorted[i] = {x = pt.x, y = pt.y, orig_idx = i}
  end
  table.sort(sorted, function(a, b) return a.x < b.x end)
  return sorted
end

local function apply_curve_shape(t, curve_shape)
  if curve_shape == 0 then return t end
  local power = 2 ^ curve_shape
  return t ^ power
end

local function eval_curve(points, x, segment_curves)
  if #points < 2 then return 0 end
  segment_curves = segment_curves or {}

  local sorted = sort_points_by_x(points)
  local n = #sorted

  x = math.max(0, math.min(1, x))

  local seg_idx = 1
  while seg_idx < n and sorted[seg_idx + 1].x < x do
    seg_idx = seg_idx + 1
  end
  seg_idx = math.min(seg_idx, n - 1)

  local seg_start = sorted[seg_idx].x
  local seg_end = sorted[seg_idx + 1].x
  local seg_len = seg_end - seg_start
  if seg_len < 0.0001 then seg_len = 0.0001 end

  local y_start = sorted[seg_idx].y
  local y_end = sorted[seg_idx + 1].y

  local t_norm = (x - seg_start) / seg_len
  t_norm = math.max(0, math.min(1, t_norm))

  local seg_curve = segment_curves[seg_idx] or 0
  local t_curved = apply_curve_shape(t_norm, seg_curve)

  local out = y_start + (y_end - y_start) * t_curved
  return math.max(0, math.min(1, out))
end

--------------------------------------------------------------------------------
-- MIDI Functions
--------------------------------------------------------------------------------

local function get_active_midi_editor()
  return r.MIDIEditor_GetActive()
end

local function get_selected_notes(take)
  local notes = {}
  if not take then return notes end

  local _, note_count = r.MIDI_CountEvts(take)

  for i = 0, note_count - 1 do
    local _, selected, muted, startppq, endppq, chan, pitch, vel = r.MIDI_GetNote(take, i)
    if selected then
      table.insert(notes, {
        idx = i,
        startppq = startppq,
        endppq = endppq,
        pitch = pitch,
        vel = vel,
        chan = chan,
        muted = muted
      })
    end
  end

  table.sort(notes, function(a, b) return a.startppq < b.startppq end)
  return notes
end

local function get_ppq_per_beat(take)
  local item = r.GetMediaItemTake_Item(take)
  local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local ppq_start = r.MIDI_GetPPQPosFromProjTime(take, item_pos)
  local ppq_beat = r.MIDI_GetPPQPosFromProjTime(take, item_pos + (60 / r.Master_GetTempo()))
  return ppq_beat - ppq_start
end

local function apply_note_repeat(take, notes, repetitions, grid_value, vel_points, vel_curves, time_points, time_curves)
  if not take or #notes == 0 or repetitions < 1 then return end

  local ppq_per_beat = get_ppq_per_beat(take)
  local ppq_per_bar = ppq_per_beat * 4  -- Assuming 4/4
  local total_span = ppq_per_bar * grid_value * repetitions

  r.MIDI_DisableSort(take)

  for _, note in ipairs(notes) do
    local note_length = note.endppq - note.startppq

    for rep = 1, repetitions do
      local t = rep / repetitions

      -- Velocity from curve
      local vel_val = eval_curve(vel_points, t, vel_curves)
      local new_vel = math.floor(note.vel * vel_val + 0.5)
      new_vel = math.max(1, math.min(127, new_vel))

      -- Timing from curve (maps linear position to curved position)
      local time_val = eval_curve(time_points, t, time_curves)
      local new_start = note.startppq + (time_val * total_span)
      local new_end = new_start + note_length

      r.MIDI_InsertNote(take, false, note.muted, new_start, new_end, note.chan, note.pitch, new_vel, true)
    end
  end

  r.MIDI_Sort(take)
  r.MarkTrackItemsDirty(r.GetMediaItemTake_Track(take), r.GetMediaItemTake_Item(take))
end

local function calculate_previews(base_vel, repetitions, vel_points, vel_curves, time_points, time_curves)
  local velocities = {}
  local timings = {}
  for i = 1, repetitions do
    local t = i / repetitions
    -- Velocity
    local vel_val = eval_curve(vel_points, t, vel_curves)
    local new_vel = math.floor(base_vel * vel_val + 0.5)
    velocities[i] = math.max(1, math.min(127, new_vel))
    -- Timing (normalized 0-1)
    timings[i] = eval_curve(time_points, t, time_curves)
  end
  return velocities, timings
end

--------------------------------------------------------------------------------
-- UI Drawing
--------------------------------------------------------------------------------

local function draw_curve_editor(ctx, id, width, height, points, segment_curves, preview_data, preview_type)
  local interacted = false
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)

  r.ImGui_InvisibleButton(ctx, "curve_" .. id, width, height)
  local item_hovered = r.ImGui_IsItemHovered(ctx)
  local item_clicked = r.ImGui_IsItemClicked(ctx, 0)
  local item_right_clicked = r.ImGui_IsItemClicked(ctx, 1)

  local pad = 4
  local area_x = cursor_x + pad
  local area_y = cursor_y + pad
  local area_w = width - pad * 2
  local area_h = height - pad * 2

  -- Background
  r.ImGui_DrawList_AddRectFilled(draw_list, area_x, area_y,
    area_x + area_w, area_y + area_h, COLORS.background)

  -- Grid lines
  for i = 0, 4 do
    local gx = area_x + (i / 4) * area_w
    local gy = area_y + (i / 4) * area_h
    local color = (i == 0 or i == 4) and COLORS.grid_major or COLORS.grid
    r.ImGui_DrawList_AddLine(draw_list, gx, area_y, gx, area_y + area_h, color)
    r.ImGui_DrawList_AddLine(draw_list, area_x, gy, area_x + area_w, gy, color)
  end

  -- Draw preview
  if preview_data and #preview_data > 0 then
    if preview_type == "velocity" then
      -- Velocity bars
      local bar_width = area_w / #preview_data
      for i, vel in ipairs(preview_data) do
        local bar_x = area_x + (i - 1) * bar_width
        local bar_h = (vel / 127) * area_h
        local bar_y = area_y + area_h - bar_h
        r.ImGui_DrawList_AddRectFilled(draw_list, bar_x + 1, bar_y,
          bar_x + bar_width - 1, area_y + area_h, COLORS.preview_bar)
      end
    elseif preview_type == "timing" then
      -- Timing markers (vertical lines showing note positions)
      for _, t in ipairs(preview_data) do
        local marker_x = area_x + t * area_w
        r.ImGui_DrawList_AddLine(draw_list, marker_x, area_y, marker_x, area_y + area_h, 0xFFEA0088, 2)
      end
    end
  end

  -- Draw curve
  local prev_px, prev_py = nil, nil
  for i = 0, CURVE_RESOLUTION do
    local t = i / CURVE_RESOLUTION
    local y = eval_curve(points, t, segment_curves)
    local px = area_x + t * area_w
    local py = area_y + area_h - y * area_h
    if prev_px then
      r.ImGui_DrawList_AddLine(draw_list, prev_px, prev_py, px, py, COLORS.curve, 2)
    end
    prev_px, prev_py = px, py
  end

  -- Mouse handling
  local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
  local norm_mx = (mouse_x - area_x) / area_w
  local norm_my = 1.0 - (mouse_y - area_y) / area_h

  local shift = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift()) or
                r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightShift())
  local left_down = r.ImGui_IsMouseDown(ctx, 0)

  -- Find nearest node
  local hover_node = -1
  local node_threshold = 0.06
  local min_dist = node_threshold * node_threshold
  if not shift then
    for i, pt in ipairs(points) do
      local dx = norm_mx - pt.x
      local dy = norm_my - pt.y
      local dist = dx * dx + dy * dy
      if dist < min_dist then
        min_dist = dist
        hover_node = i
      end
    end
  end
  state.hover_node = hover_node

  -- Find nearest segment
  local hover_segment = -1
  if shift and item_hovered then
    local sorted = sort_points_by_x(points)
    for i = 1, #sorted - 1 do
      if norm_mx >= sorted[i].x and norm_mx <= sorted[i + 1].x then
        hover_segment = i
        break
      end
    end
  end
  state.hover_segment = hover_segment

  -- Click handling
  if item_hovered and item_clicked then
    if shift and hover_segment > 0 then
      state.drag_segment = hover_segment
      state.drag_start_mouse_y = mouse_y
      state.drag_start_curve = segment_curves[hover_segment] or 0
      interacted = true
    elseif hover_node > 0 then
      state.drag_node = hover_node
      interacted = true
    elseif #points < 16 and not shift then
      local new_x = math.max(0.001, math.min(0.999, norm_mx))
      local new_y = math.max(0, math.min(1, norm_my))
      table.insert(points, {x = new_x, y = new_y})
      table.insert(segment_curves, 0)
      interacted = true
    end
  end

  -- Right-click to delete
  if item_hovered and item_right_clicked then
    if hover_node > 0 and #points > 2 then
      local sorted = sort_points_by_x(points)
      local is_endpoint = (sorted[1].orig_idx == hover_node) or
                         (sorted[#sorted].orig_idx == hover_node)
      if not is_endpoint then
        table.remove(points, hover_node)
        if #segment_curves > 1 then
          table.remove(segment_curves, #segment_curves)
        end
        interacted = true
      end
    end
  end

  -- Drag segment
  if state.drag_segment > 0 and left_down then
    local delta_screen = state.drag_start_mouse_y - mouse_y
    local delta_normalized = delta_screen / area_h
    local sorted = sort_points_by_x(points)
    local is_ascending = sorted[state.drag_segment + 1].y > sorted[state.drag_segment].y
    local direction_mult = is_ascending and -1 or 1
    local new_curve = state.drag_start_curve + delta_normalized * 2 * direction_mult
    segment_curves[state.drag_segment] = math.max(-1, math.min(1, new_curve))
    interacted = true
  elseif not left_down then
    state.drag_segment = -1
  end

  -- Drag node
  if state.drag_node > 0 and left_down then
    local sorted = sort_points_by_x(points)
    local is_left_endpoint = sorted[1].orig_idx == state.drag_node
    local is_right_endpoint = sorted[#sorted].orig_idx == state.drag_node
    local new_x = is_left_endpoint and 0 or (is_right_endpoint and 1 or math.max(0.001, math.min(0.999, norm_mx)))
    local new_y = math.max(0, math.min(1, norm_my))
    points[state.drag_node] = {x = new_x, y = new_y}
    interacted = true
  elseif not left_down then
    state.drag_node = -1
  end

  -- Draw nodes
  for i, pt in ipairs(points) do
    local nx = area_x + pt.x * area_w
    local ny = area_y + area_h - pt.y * area_h
    local is_hover = (i == state.hover_node)
    local is_drag = (i == state.drag_node)
    local sorted = sort_points_by_x(points)
    local is_endpoint = (sorted[1].orig_idx == i) or (sorted[#sorted].orig_idx == i)

    local color = is_endpoint and COLORS.node_endpoint or
                  (is_hover or is_drag) and COLORS.node_hover or COLORS.node
    local radius = (is_hover or is_drag) and 7 or 5

    r.ImGui_DrawList_AddCircleFilled(draw_list, nx, ny, radius, color)
    r.ImGui_DrawList_AddCircle(draw_list, nx, ny, radius, 0xFFFFFF80, 0, 1)
  end

  -- Draw segment handles when shift held
  if shift or state.drag_segment > 0 then
    local sorted = sort_points_by_x(points)
    for i = 1, #sorted - 1 do
      local mid_x = (sorted[i].x + sorted[i + 1].x) / 2
      local mid_y = eval_curve(points, mid_x, segment_curves)
      local hx = area_x + mid_x * area_w
      local hy = area_y + area_h - mid_y * area_h

      local is_hover = (state.hover_segment == i)
      local is_drag = (state.drag_segment == i)
      local hs = (is_hover or is_drag) and 6 or 4
      local handle_color = (is_hover or is_drag) and 0x88AACCFF or 0x6688AAFF

      r.ImGui_DrawList_AddQuadFilled(draw_list,
        hx, hy - hs, hx + hs, hy, hx, hy + hs, hx - hs, hy, handle_color)

      if is_hover or is_drag then
        local curve_val = segment_curves[i] or 0
        local text = string.format("%.2f", curve_val)
        r.ImGui_DrawList_AddText(draw_list, hx + 10, hy - 6, COLORS.text, text)
      end
    end
  end

  -- Border
  r.ImGui_DrawList_AddRect(draw_list, area_x, area_y,
    area_x + area_w, area_y + area_h, COLORS.grid_major)

  return interacted
end

--------------------------------------------------------------------------------
-- Main Window
--------------------------------------------------------------------------------

local ctx = r.ImGui_CreateContext('SideTrack Note Repeat')

local function main()
  local midi_editor = get_active_midi_editor()
  local take = midi_editor and r.MIDIEditor_GetTake(midi_editor)

  -- Update selected notes and previews
  if take then
    state.selected_notes = get_selected_notes(take)
    local base_vel = state.selected_notes[1] and state.selected_notes[1].vel or 100
    state.preview_velocities, state.preview_timings = calculate_previews(
      base_vel, state.repetitions, state.vel_points, state.vel_curves,
      state.time_points, state.time_curves)
  else
    state.selected_notes = {}
    state.preview_velocities = {}
    state.preview_timings = {}
  end

  r.ImGui_SetNextWindowSize(ctx, 400, 480, r.ImGui_Cond_FirstUseEver())
  local visible, open = r.ImGui_Begin(ctx, 'Note Repeat', true)

  if visible then
    -- Info text
    local note_count = #state.selected_notes
    if note_count > 0 then
      r.ImGui_Text(ctx, string.format("%d note%s selected", note_count, note_count > 1 and "s" or ""))
    else
      r.ImGui_TextColored(ctx, 0xFF8888FF, "Select MIDI notes to repeat")
    end

    r.ImGui_Spacing(ctx)

    -- Controls row
    r.ImGui_SetNextItemWidth(ctx, 120)
    local changed_rep, new_rep = r.ImGui_SliderInt(ctx, "Repetitions", state.repetitions, 1, 16)
    if changed_rep then
      state.repetitions = new_rep
    end

    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 80)
    if r.ImGui_BeginCombo(ctx, "Grid", GRID_OPTIONS[state.grid_idx].label) then
      for i, opt in ipairs(GRID_OPTIONS) do
        if r.ImGui_Selectable(ctx, opt.label, i == state.grid_idx) then
          state.grid_idx = i
        end
      end
      r.ImGui_EndCombo(ctx)
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local editor_h = 120

    -- TIMING CURVE
    r.ImGui_Text(ctx, "Timing")
    r.ImGui_SameLine(ctx, avail_w - 150)
    if r.ImGui_SmallButton(ctx, "Linear##t") then
      state.time_points = {{x = 0, y = 0}, {x = 1, y = 1}}
      state.time_curves = {0}
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx, "Accel##t") then
      state.time_points = {{x = 0, y = 0}, {x = 1, y = 1}}
      state.time_curves = {0.7}
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx, "Decel##t") then
      state.time_points = {{x = 0, y = 0}, {x = 1, y = 1}}
      state.time_curves = {-0.7}
    end

    draw_curve_editor(ctx, "time", avail_w, editor_h,
      state.time_points, state.time_curves, state.preview_timings, "timing")

    r.ImGui_Spacing(ctx)

    -- VELOCITY CURVE
    r.ImGui_Text(ctx, "Velocity")
    r.ImGui_SameLine(ctx, avail_w - 150)
    if r.ImGui_SmallButton(ctx, "Decay##v") then
      state.vel_points = {{x = 0, y = 1}, {x = 1, y = 0.2}}
      state.vel_curves = {0.5}
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx, "Ramp##v") then
      state.vel_points = {{x = 0, y = 0.3}, {x = 1, y = 1}}
      state.vel_curves = {-0.5}
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx, "Flat##v") then
      state.vel_points = {{x = 0, y = 1}, {x = 1, y = 1}}
      state.vel_curves = {0}
    end

    draw_curve_editor(ctx, "vel", avail_w, editor_h,
      state.vel_points, state.vel_curves, state.preview_velocities, "velocity")

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    -- Apply button
    local can_apply = take and note_count > 0
    if not can_apply then r.ImGui_BeginDisabled(ctx) end

    if r.ImGui_Button(ctx, "Apply Repeat", -1, 30) then
      r.Undo_BeginBlock()
      apply_note_repeat(take, state.selected_notes, state.repetitions,
        GRID_OPTIONS[state.grid_idx].value, state.vel_points, state.vel_curves,
        state.time_points, state.time_curves)
      r.Undo_EndBlock("Note Repeat", -1)
    end

    if not can_apply then r.ImGui_EndDisabled(ctx) end

    -- Help
    r.ImGui_Spacing(ctx)
    r.ImGui_TextColored(ctx, 0x888888FF, "Shift+drag to bend curves")

    r.ImGui_End(ctx)
  end

  if open then
    r.defer(main)
  end
end

main()
