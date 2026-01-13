-- Piano Roll View for SideTrack

local r = reaper
local Colors = require('colors')
local State = require('state')
local MidiOutput = require('midi_output')

local PianoRoll = {}

-- Constants
local NOTE_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local BLACK_KEYS = {false, true, false, true, false, false, true, false, true, false, true, false}

-- Dimensions
local KEYBOARD_W = 50
local ROW_H = 14
local HEADER_H = 24
local BASE_STEP_W = 28

local function is_black_key(pitch)
  return BLACK_KEYS[(pitch % 12) + 1]
end

local function get_note_name(pitch)
  local note = NOTE_NAMES[(pitch % 12) + 1]
  local octave = math.floor(pitch / 12) - 1
  return note .. octave
end

function PianoRoll.draw()
  local ctx = State.ctx
  local pattern = State.get_pattern()
  if not pattern or not ctx then return end

  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)

  local step_w = BASE_STEP_W * State.piano.zoom_x
  local grid_steps = pattern:get_grid_steps()
  local grid_w = grid_steps * step_w
  local note_range = State.piano.note_max - State.piano.note_min + 1
  local grid_h = note_range * ROW_H

  local total_w = KEYBOARD_W + grid_w
  local total_h = HEADER_H + grid_h

  -- Clamp to available space
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local display_w = math.min(total_w, avail_w)
  local display_h = math.min(total_h, 300)

  -- Scrollable child window
  local scroll_flags = r.ImGui_WindowFlags_HorizontalScrollbar()
  r.ImGui_BeginChild(ctx, "piano_roll_scroll", display_w, display_h, 0, scroll_flags)

  r.ImGui_InvisibleButton(ctx, "piano_grid", total_w, total_h)
  local is_hovered = r.ImGui_IsItemHovered(ctx)
  local is_clicked = r.ImGui_IsItemClicked(ctx, 0)
  local is_right_clicked = r.ImGui_IsItemClicked(ctx, 1)
  local is_mouse_down = r.ImGui_IsMouseDown(ctx, 0)

  local scroll_x = r.ImGui_GetScrollX(ctx)
  local scroll_y = r.ImGui_GetScrollY(ctx)
  local scroll_cursor_x = cursor_x - scroll_x
  local scroll_cursor_y = cursor_y - scroll_y
  local grid_x = scroll_cursor_x + KEYBOARD_W
  local grid_y = scroll_cursor_y + HEADER_H

  -- Background
  r.ImGui_DrawList_AddRectFilled(draw_list, scroll_cursor_x, scroll_cursor_y,
    scroll_cursor_x + total_w, scroll_cursor_y + total_h, Colors.bg)

  -- Header
  r.ImGui_DrawList_AddRectFilled(draw_list, grid_x, scroll_cursor_y,
    grid_x + grid_w, scroll_cursor_y + HEADER_H, Colors.header_bg)

  -- Bar markers
  for step = 0, grid_steps - 1 do
    local x = grid_x + step * step_w
    if (step * pattern.grid_division) % 1 == 0 then
      local bar_num = math.floor(step * pattern.grid_division) + 1
      r.ImGui_DrawList_AddText(draw_list, x + 4, scroll_cursor_y + 4, Colors.text, tostring(bar_num))
    end
  end

  local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
  State.piano.hover_note = nil

  -- Draw rows and keyboard
  for i = 0, note_range - 1 do
    local pitch = State.piano.note_max - i
    local y = grid_y + i * ROW_H
    local is_black = is_black_key(pitch)

    -- Row background
    local row_bg = is_black and Colors.piano_black_row or
                   ((pitch % 12 == 0) and Colors.row_alt or Colors.bg)
    r.ImGui_DrawList_AddRectFilled(draw_list, grid_x, y, grid_x + grid_w, y + ROW_H, row_bg)

    -- Piano key
    local key_color = is_black and Colors.piano_black or Colors.piano_white
    local key_text_color = is_black and Colors.piano_white or Colors.piano_black
    local key_x2 = scroll_cursor_x + KEYBOARD_W - 2
    r.ImGui_DrawList_AddRectFilled(draw_list, scroll_cursor_x, y, key_x2, y + ROW_H - 1, key_color, 2)

    -- Note name
    if pitch % 12 == 0 or ROW_H >= 16 then
      r.ImGui_DrawList_AddText(draw_list, scroll_cursor_x + 4, y + 1, key_text_color, get_note_name(pitch))
    end

    -- Row line
    local line_color = (pitch % 12 == 0) and Colors.grid_bar or Colors.grid_line
    r.ImGui_DrawList_AddLine(draw_list, grid_x, y, grid_x + grid_w, y, line_color)
  end

  -- Vertical grid lines
  for step = 0, grid_steps do
    local x = grid_x + step * step_w
    local is_bar = (step * pattern.grid_division) % 1 == 0
    local is_beat = (step * pattern.grid_division) % 0.25 == 0
    local line_color = is_bar and Colors.grid_bar or (is_beat and Colors.grid_beat or Colors.grid_line)
    r.ImGui_DrawList_AddLine(draw_list, x, grid_y, x, grid_y + grid_h, line_color)
  end

  -- Draw notes
  for note_idx, note in ipairs(pattern.notes) do
    if note.pitch >= State.piano.note_min and note.pitch <= State.piano.note_max then
      local row_from_top = State.piano.note_max - note.pitch
      local note_x = grid_x + (note.start / pattern.grid_division) * step_w
      local note_y = grid_y + row_from_top * ROW_H + 1
      local note_w = (note.length / pattern.grid_division) * step_w - 2
      local note_h = ROW_H - 2

      local is_note_hovered = mouse_x >= note_x and mouse_x < note_x + note_w and
                               mouse_y >= note_y and mouse_y < note_y + note_h and is_hovered

      if is_note_hovered then
        State.piano.hover_note = note_idx
      end

      local vel_factor = note.vel / 127
      local is_selected = State.piano.selected_note == note_idx
      local note_color = is_selected and Colors.note_bar_selected or
                        (is_note_hovered and Colors.cell_hover or
                        (vel_factor > 0.6 and Colors.note_bar or Colors.cell_filled_dim))

      r.ImGui_DrawList_AddRectFilled(draw_list, note_x, note_y, note_x + note_w, note_y + note_h, note_color, 2)
      r.ImGui_DrawList_AddRect(draw_list, note_x, note_y, note_x + note_w, note_y + note_h, Colors.note_bar_border, 2)

      -- Velocity indicator
      local vel_bar_h = vel_factor * (note_h - 2)
      r.ImGui_DrawList_AddRectFilled(draw_list,
        note_x + 1, note_y + note_h - vel_bar_h - 1, note_x + 4, note_y + note_h - 1, Colors.velocity_bar)
    end
  end

  -- Border
  r.ImGui_DrawList_AddRect(draw_list, grid_x, grid_y, grid_x + grid_w, grid_y + grid_h, Colors.grid_beat)

  -- Handle dragging
  if State.piano.dragging then
    if is_mouse_down then
      local drag = State.piano.dragging
      local dx = mouse_x - drag.start_x
      local dy = mouse_y - drag.start_y

      if drag.mode == "move" then
        local grid_delta = math.floor(dx / step_w + 0.5)
        local pitch_delta = -math.floor(dy / ROW_H + 0.5)
        local new_start = drag.orig_start + grid_delta * pattern.grid_division
        local new_pitch = drag.orig_pitch + pitch_delta
        pattern.notes[drag.note_idx].start = math.max(0, new_start)
        pattern.notes[drag.note_idx].pitch = math.max(0, math.min(127, new_pitch))
      elseif drag.mode == "resize" then
        local grid_delta = math.floor(dx / step_w + 0.5)
        local new_len = drag.orig_len + grid_delta * pattern.grid_division
        pattern.notes[drag.note_idx].length = math.max(pattern.grid_division, new_len)
      end
    else
      State.piano.dragging = nil
    end
  end

  -- Handle clicks
  if is_hovered and not State.piano.dragging then
    local rel_x = mouse_x - grid_x
    local rel_y = mouse_y - grid_y

    if rel_x >= 0 and rel_x < grid_w and rel_y >= 0 and rel_y < grid_h then
      local grid_step = math.floor(rel_x / step_w)
      local row_idx = math.floor(rel_y / ROW_H)
      local pitch = State.piano.note_max - row_idx

      if is_clicked then
        if State.piano.hover_note then
          local note = pattern.notes[State.piano.hover_note]
          local note_x = grid_x + (note.start / pattern.grid_division) * step_w
          local note_w = (note.length / pattern.grid_division) * step_w
          local mode = (mouse_x > note_x + note_w - 8) and "resize" or "move"

          State.piano.dragging = {
            note_idx = State.piano.hover_note,
            mode = mode,
            start_x = mouse_x,
            start_y = mouse_y,
            orig_pitch = note.pitch,
            orig_start = note.start,
            orig_len = note.length,
          }
          State.piano.selected_note = State.piano.hover_note
        else
          local start_time = grid_step * pattern.grid_division
          local new_idx = pattern:add_note(pitch, start_time, pattern.grid_division, 100)
          State.piano.selected_note = new_idx
          MidiOutput.preview_note(pitch, 100, pattern.channel, 150)
        end
      elseif is_right_clicked and State.piano.hover_note then
        pattern:remove_note(State.piano.hover_note)
        if State.piano.selected_note == State.piano.hover_note then
          State.piano.selected_note = nil
        end
      end
    end
  end

  -- Mouse wheel zoom
  local wheel_h = r.ImGui_GetMouseWheel(ctx)
  if is_hovered and r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl()) and wheel_h ~= 0 then
    State.piano.zoom_x = math.max(0.5, math.min(4.0, State.piano.zoom_x + wheel_h * 0.1))
  end

  r.ImGui_EndChild(ctx)

  -- Controls
  r.ImGui_SetNextItemWidth(ctx, 100)
  local changed_zoom, new_zoom = r.ImGui_SliderDouble(ctx, "Zoom", State.piano.zoom_x, 0.5, 4.0, "%.1fx")
  if changed_zoom then State.piano.zoom_x = new_zoom end

  r.ImGui_SameLine(ctx)
  local range_str = string.format("Range: %s - %s",
    get_note_name(State.piano.note_min), get_note_name(State.piano.note_max))
  r.ImGui_Text(ctx, range_str)

  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "-", 20, 0) then
    State.piano.note_min = math.max(0, State.piano.note_min - 12)
    State.piano.note_max = math.max(State.piano.note_min + 12, State.piano.note_max - 12)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "+", 20, 0) then
    State.piano.note_min = math.min(115, State.piano.note_min + 12)
    State.piano.note_max = math.min(127, State.piano.note_max + 12)
  end
end

return PianoRoll
