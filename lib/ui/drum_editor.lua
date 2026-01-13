-- Drum Editor View for SideTrack

local r = reaper
local Colors = require('colors')
local State = require('state')
local MidiOutput = require('midi_output')

local DrumEditor = {}

-- Dimensions
local ROW_LABEL_W = 80
local ROW_H = 24
local CELL_W = 28
local HEADER_H = 24

-- Click debounce threshold (seconds)
local CLICK_DEBOUNCE = 0.1

function DrumEditor.draw()
  local ctx = State.ctx
  local pattern = State.get_pattern()
  if not pattern or not ctx then return end

  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)

  local grid_steps = pattern:get_grid_steps()
  local grid_w = grid_steps * CELL_W
  local num_rows = #pattern.drum_map
  local grid_h = num_rows * ROW_H

  local grid_x = cursor_x + ROW_LABEL_W
  local grid_y = cursor_y + HEADER_H
  local total_w = ROW_LABEL_W + grid_w
  local total_h = HEADER_H + grid_h

  -- Reserve space
  r.ImGui_InvisibleButton(ctx, "drum_grid", total_w, total_h)
  local is_hovered = r.ImGui_IsItemHovered(ctx)
  local is_clicked = r.ImGui_IsItemClicked(ctx, 0)
  local is_right_clicked = r.ImGui_IsItemClicked(ctx, 1)

  -- Background
  r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y,
    cursor_x + total_w, cursor_y + total_h, Colors.bg)

  -- Header background
  r.ImGui_DrawList_AddRectFilled(draw_list, grid_x, cursor_y,
    grid_x + grid_w, cursor_y + HEADER_H, Colors.header_bg)

  -- Beat/bar markers in header
  for step = 0, grid_steps - 1 do
    local x = grid_x + step * CELL_W
    local is_bar = (step * pattern.grid_division) % 1 == 0

    if is_bar then
      local bar_num = math.floor(step * pattern.grid_division) + 1
      r.ImGui_DrawList_AddText(draw_list, x + 4, cursor_y + 4, Colors.text, tostring(bar_num))
    end
  end

  -- Row labels (drum names)
  for i, drum in ipairs(pattern.drum_map) do
    local y = grid_y + (i - 1) * ROW_H
    local row_bg = (i % 2 == 0) and Colors.row_alt or Colors.bg
    r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, y, cursor_x + ROW_LABEL_W, y + ROW_H, row_bg)
    r.ImGui_DrawList_AddText(draw_list, cursor_x + 4, y + 4, Colors.text_dim, drum.name)
  end

  -- Grid cells
  local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
  State.drums.hover_row = -1
  State.drums.hover_col = -1

  for row = 1, num_rows do
    local drum = pattern.drum_map[row]
    local y = grid_y + (row - 1) * ROW_H

    for step = 0, grid_steps - 1 do
      local x = grid_x + step * CELL_W

      -- Cell bounds
      local cell_x1 = x + 1
      local cell_y1 = y + 1
      local cell_x2 = x + CELL_W - 1
      local cell_y2 = y + ROW_H - 1

      -- Check hover
      local is_cell_hovered = mouse_x >= cell_x1 and mouse_x < cell_x2 and
                              mouse_y >= cell_y1 and mouse_y < cell_y2

      if is_cell_hovered and is_hovered then
        State.drums.hover_row = row
        State.drums.hover_col = step
      end

      -- Get note at this cell
      local _, note = pattern:get_note_at_grid(drum.pitch, step)

      -- Draw cell
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

      -- Velocity bar for filled cells
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

    -- Horizontal row line
    r.ImGui_DrawList_AddLine(draw_list, grid_x, y, grid_x + grid_w, y, Colors.grid_line)
  end

  -- Border
  r.ImGui_DrawList_AddRect(draw_list, grid_x, grid_y, grid_x + grid_w, grid_y + grid_h, Colors.grid_beat)

  -- Draw playhead if playing
  if State.playback.playing then
    local playhead_step = State.playback.position / pattern.grid_division
    local playhead_x = grid_x + playhead_step * CELL_W
    if playhead_x >= grid_x and playhead_x <= grid_x + grid_w then
      r.ImGui_DrawList_AddLine(draw_list, playhead_x, cursor_y, playhead_x, grid_y + grid_h,
        Colors.playhead, 2)
    end
  end

  -- Handle clicks - calculate cell directly from mouse position
  local now = r.time_precise()
  if is_hovered and (is_clicked or is_right_clicked) then
    -- Calculate which cell was clicked from mouse position
    local click_col = math.floor((mouse_x - grid_x) / CELL_W)
    local click_row = math.floor((mouse_y - grid_y) / ROW_H) + 1

    -- Validate bounds
    if click_col >= 0 and click_col < grid_steps and
       click_row >= 1 and click_row <= num_rows then
      local drum = pattern.drum_map[click_row]

      if is_clicked then
        -- Check debounce: same cell clicked too fast?
        local same_cell = State.drums.last_click_row == click_row and
                          State.drums.last_click_col == click_col
        local too_fast = (now - State.drums.last_click_time) < CLICK_DEBOUNCE

        if not (same_cell and too_fast) then
          local idx = pattern:toggle_note(drum.pitch, click_col, 100)
          if idx then
            MidiOutput.preview_note(drum.pitch, 100, pattern.channel, 150)
          end
          State.drums.last_click_time = now
          State.drums.last_click_row = click_row
          State.drums.last_click_col = click_col
        end
      elseif is_right_clicked then
        local vel_idx, note = pattern:get_note_at_grid(drum.pitch, click_col)
        if note then
          local new_vel = note.vel <= 40 and 100 or note.vel - 20
          pattern:set_velocity(vel_idx, new_vel)
          MidiOutput.preview_note(drum.pitch, new_vel, pattern.channel, 150)
        end
      end
    end
  end
end

return DrumEditor
