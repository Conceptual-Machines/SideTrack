-- Step Sequencer View for SideTrack

local r = reaper
local Colors = require('colors')
local State = require('state')
local MidiOutput = require('midi_output')

local StepSeq = {}

-- Constants
local NOTE_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

-- Dimensions
local ROW_LABEL_W = 40
local ROW_H = 24
local CELL_W = 28
local HEADER_H = 24

local function get_note_name(pitch)
  local note = NOTE_NAMES[(pitch % 12) + 1]
  local octave = math.floor(pitch / 12) - 1
  return note .. octave
end

function StepSeq.draw()
  local ctx = State.ctx
  local pattern = State.get_pattern()
  if not pattern or not ctx then return end

  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)

  local grid_steps = pattern:get_grid_steps()
  local grid_w = grid_steps * CELL_W
  local num_rows = State.steps.num_rows
  local grid_h = num_rows * ROW_H

  local grid_x = cursor_x + ROW_LABEL_W
  local grid_y = cursor_y + HEADER_H
  local total_w = ROW_LABEL_W + grid_w
  local total_h = HEADER_H + grid_h

  -- Reserve space
  r.ImGui_InvisibleButton(ctx, "step_grid", total_w, total_h)
  local is_hovered = r.ImGui_IsItemHovered(ctx)
  local is_clicked = r.ImGui_IsItemClicked(ctx, 0)
  local is_right_clicked = r.ImGui_IsItemClicked(ctx, 1)

  -- Background
  r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y,
    cursor_x + total_w, cursor_y + total_h, Colors.bg)

  -- Header
  r.ImGui_DrawList_AddRectFilled(draw_list, grid_x, cursor_y,
    grid_x + grid_w, cursor_y + HEADER_H, Colors.header_bg)

  -- Bar markers
  for step = 0, grid_steps - 1 do
    local x = grid_x + step * CELL_W
    if (step * pattern.grid_division) % 1 == 0 then
      local bar_num = math.floor(step * pattern.grid_division) + 1
      r.ImGui_DrawList_AddText(draw_list, x + 4, cursor_y + 4, Colors.text, tostring(bar_num))
    end
  end

  local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
  State.steps.hover_row = -1
  State.steps.hover_col = -1

  -- Draw rows (pitches from high to low)
  for i = 1, num_rows do
    local pitch = State.steps.base_pitch + (num_rows - i)
    local y = grid_y + (i - 1) * ROW_H
    local row_bg = (i % 2 == 0) and Colors.row_alt or Colors.bg

    -- Row background
    r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, y, cursor_x + ROW_LABEL_W, y + ROW_H, row_bg)

    -- Note label
    r.ImGui_DrawList_AddText(draw_list, cursor_x + 4, y + 4, Colors.text_dim, get_note_name(pitch))

    -- Cells
    for step = 0, grid_steps - 1 do
      local x = grid_x + step * CELL_W

      local cell_x1 = x + 1
      local cell_y1 = y + 1
      local cell_x2 = x + CELL_W - 1
      local cell_y2 = y + ROW_H - 1

      local is_cell_hovered = mouse_x >= cell_x1 and mouse_x < cell_x2 and
                              mouse_y >= cell_y1 and mouse_y < cell_y2

      if is_cell_hovered and is_hovered then
        State.steps.hover_row = i
        State.steps.hover_col = step
      end

      -- Check for note at this position
      local _, note = pattern:get_note_at_grid(pitch, step)

      local cell_color
      if note then
        local vel_factor = note.vel / 127
        cell_color = vel_factor > 0.6 and Colors.cell_filled or Colors.cell_filled_dim
      elseif is_cell_hovered and is_hovered then
        cell_color = Colors.cell_hover
      else
        cell_color = Colors.cell_empty
      end

      r.ImGui_DrawList_AddRectFilled(draw_list, cell_x1, cell_y1, cell_x2, cell_y2, cell_color, 2)

      -- Velocity bar
      if note then
        local vel_h = (note.vel / 127) * (ROW_H - 6)
        local bar_y = cell_y2 - vel_h - 2
        r.ImGui_DrawList_AddRectFilled(draw_list,
          cell_x1 + 2, bar_y, cell_x2 - 2, cell_y2 - 2, Colors.velocity_bar, 1)
      end

      -- Grid lines
      local is_bar = (step * pattern.grid_division) % 1 == 0
      local is_beat = (step * pattern.grid_division) % 0.25 == 0
      local line_color = is_bar and Colors.grid_bar or (is_beat and Colors.grid_beat or Colors.grid_line)
      r.ImGui_DrawList_AddLine(draw_list, x, grid_y, x, grid_y + grid_h, line_color)
    end

    -- Row line
    r.ImGui_DrawList_AddLine(draw_list, grid_x, y, grid_x + grid_w, y, Colors.grid_line)
  end

  -- Border
  r.ImGui_DrawList_AddRect(draw_list, grid_x, grid_y, grid_x + grid_w, grid_y + grid_h, Colors.grid_beat)

  -- Handle clicks
  if is_hovered and State.steps.hover_row > 0 and State.steps.hover_col >= 0 then
    local pitch = State.steps.base_pitch + (num_rows - State.steps.hover_row)

    if is_clicked then
      local idx = pattern:toggle_note(pitch, State.steps.hover_col, 100)
      if idx then
        MidiOutput.preview_note(pitch, 100, pattern.channel, 150)
      end
    elseif is_right_clicked then
      local vel_idx, note = pattern:get_note_at_grid(pitch, State.steps.hover_col)
      if note then
        local new_vel = note.vel <= 40 and 100 or note.vel - 20
        pattern:set_velocity(vel_idx, new_vel)
        MidiOutput.preview_note(pitch, new_vel, pattern.channel, 150)
      end
    end
  end

  -- Controls
  r.ImGui_Text(ctx, string.format("Base: %s", get_note_name(State.steps.base_pitch)))
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "-Oct", 40, 0) then
    State.steps.base_pitch = math.max(0, State.steps.base_pitch - 12)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "+Oct", 40, 0) then
    State.steps.base_pitch = math.min(115, State.steps.base_pitch + 12)
  end

  r.ImGui_SameLine(ctx)
  r.ImGui_Text(ctx, string.format("Rows: %d", State.steps.num_rows))
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "-##rows", 20, 0) then
    State.steps.num_rows = math.max(4, State.steps.num_rows - 1)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "+##rows", 20, 0) then
    State.steps.num_rows = math.min(24, State.steps.num_rows + 1)
  end
end

return StepSeq
