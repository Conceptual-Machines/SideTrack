-- Drum Editor View for SideTrack

local r = reaper
local Colors = require('colors')
local State = require('state')
local MidiOutput = require('midi_output')
local Mouse = require('mouse')

local DrumEditor = {}

-- Fixed dimensions
local ROW_LABEL_W = 70
local MODIFIER_W = 220
local HEADER_H = 20
local BASE_CELL_W = 24
local MIN_ROW_H = 20

-- Store grid geometry for mouse hit testing
local grid_geo = {
  x = 0, y = 0,
  cell_w = 0, row_h = 0,
  steps = 0, rows = 0,
}

-- Convert screen position to grid cell
local function screen_to_cell(mx, my)
  local col = math.floor((mx - grid_geo.x) / grid_geo.cell_w)
  local row = math.floor((my - grid_geo.y) / grid_geo.row_h) + 1

  if col >= 0 and col < grid_geo.steps and row >= 1 and row <= grid_geo.rows then
    return row, col
  end
  return nil, nil
end

-- Get cell screen bounds
local function get_cell_bounds(row, col)
  local x = grid_geo.x + col * grid_geo.cell_w
  local y = grid_geo.y + (row - 1) * grid_geo.row_h
  return x + 1, y + 1, x + grid_geo.cell_w - 1, y + grid_geo.row_h - 1
end

-- Check if a note is selected
local function is_note_selected(note_idx)
  return State.drums.selected_notes[note_idx] == true
end

-- Clear selection
local function clear_selection()
  State.drums.selected_notes = {}
end

-- Select notes within rectangle
local function select_notes_in_rect(pattern)
  clear_selection()

  for idx, note in ipairs(pattern.notes) do
    -- Find which row this note belongs to
    local note_row = pattern:get_row_for_pitch(note.pitch)

    if note_row then
      -- Get the grid column for this note
      local note_col = math.floor(note.start / pattern.grid_division + 0.5)
      local cx1, cy1, cx2, cy2 = get_cell_bounds(note_row, note_col)

      -- Check if cell overlaps selection
      if Mouse.rect_in_selection(cx1, cy1, cx2, cy2) then
        State.drums.selected_notes[idx] = true
      end
    end
  end
end

-- Check if clicking on a selected note
local function is_clicking_selected_note(pattern, row, col)
  if not row or not col then return false end
  local drum = pattern.drum_map[row]
  if not drum then return false end

  local note_idx = pattern:get_note_at_grid(drum.pitch, col)
  if note_idx and State.drums.selected_notes[note_idx] then
    return true
  end
  return false
end

-- Get selection count
local function get_selection_count()
  local count = 0
  for _ in pairs(State.drums.selected_notes) do count = count + 1 end
  return count
end

function DrumEditor.draw()
  local ctx = State.ctx
  local pattern = State.get_pattern()
  if not pattern or not ctx then return end

  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local grid_steps = pattern:get_grid_steps()
  local num_rows = #pattern.drum_map

  -- Cell dimensions
  local cell_w = math.floor(BASE_CELL_W * State.drums.zoom_x)
  local grid_content_h = avail_h - HEADER_H - 30  -- 30 for zoom controls
  local row_h = math.max(MIN_ROW_H, math.floor(grid_content_h / num_rows))

  -- Grid dimensions (fixed based on content, not stretched)
  local grid_w = grid_steps * cell_w
  local grid_h = num_rows * row_h

  -- Available width for scrollable grid area
  local grid_area_w = avail_w - ROW_LABEL_W - MODIFIER_W

  -- Begin main layout
  local draw_list = r.ImGui_GetWindowDrawList(ctx)

  -- === ROW LABELS (left column) ===
  r.ImGui_BeginChild(ctx, "drum_labels", ROW_LABEL_W, grid_h + HEADER_H, 0, 0)
  local labels_x, labels_y = r.ImGui_GetCursorScreenPos(ctx)

  -- Header spacer
  r.ImGui_DrawList_AddRectFilled(draw_list, labels_x, labels_y,
    labels_x + ROW_LABEL_W, labels_y + HEADER_H, Colors.header_bg)

  -- Row labels
  for i, drum in ipairs(pattern.drum_map) do
    local y = labels_y + HEADER_H + (i - 1) * row_h
    local row_bg = (i % 2 == 0) and Colors.row_alt or Colors.bg
    r.ImGui_DrawList_AddRectFilled(draw_list, labels_x, y,
      labels_x + ROW_LABEL_W, y + row_h, row_bg)
    r.ImGui_DrawList_AddText(draw_list, labels_x + 4, y + 2, Colors.text_dim, drum.name)
  end
  r.ImGui_EndChild(ctx)

  r.ImGui_SameLine(ctx, 0, 0)

  -- === GRID AREA (scrollable middle) ===
  local scroll_flags = r.ImGui_WindowFlags_HorizontalScrollbar()
  r.ImGui_BeginChild(ctx, "drum_grid_scroll", grid_area_w, grid_h + HEADER_H, 0, scroll_flags)

  local grid_cursor_x, grid_cursor_y = r.ImGui_GetCursorScreenPos(ctx)

  -- Reserve space for entire grid
  r.ImGui_InvisibleButton(ctx, "drum_grid", grid_w, grid_h + HEADER_H)
  local is_hovered = r.ImGui_IsItemHovered(ctx)

  local grid_x = grid_cursor_x
  local grid_y = grid_cursor_y + HEADER_H

  -- Store grid geometry for hit testing
  grid_geo.x = grid_x
  grid_geo.y = grid_y
  grid_geo.cell_w = cell_w
  grid_geo.row_h = row_h
  grid_geo.steps = grid_steps
  grid_geo.rows = num_rows

  -- Header background
  r.ImGui_DrawList_AddRectFilled(draw_list, grid_x, grid_cursor_y,
    grid_x + grid_w, grid_cursor_y + HEADER_H, Colors.header_bg)

  -- Beat/bar markers in header
  for step = 0, grid_steps - 1 do
    local x = grid_x + step * cell_w
    local is_bar = (step * pattern.grid_division) % 1 == 0
    if is_bar then
      local bar_num = math.floor(step * pattern.grid_division) + 1
      r.ImGui_DrawList_AddText(draw_list, x + 2, grid_cursor_y + 2, Colors.text, tostring(bar_num))
    end
  end

  -- Mouse position
  local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
  State.drums.hover_row = -1
  State.drums.hover_col = -1

  -- Draw grid rows and cells
  for row = 1, num_rows do
    local drum = pattern.drum_map[row]
    local y = grid_y + (row - 1) * row_h
    local row_bg = (row % 2 == 0) and Colors.row_alt or Colors.bg

    -- Row background
    r.ImGui_DrawList_AddRectFilled(draw_list, grid_x, y, grid_x + grid_w, y + row_h, row_bg)

    for step = 0, grid_steps - 1 do
      local x = grid_x + step * cell_w
      local cell_x1, cell_y1 = x + 1, y + 1
      local cell_x2, cell_y2 = x + cell_w - 1, y + row_h - 1

      -- Hover check
      local is_cell_hovered = mouse_x >= cell_x1 and mouse_x < cell_x2 and
                              mouse_y >= cell_y1 and mouse_y < cell_y2
      if is_cell_hovered and is_hovered then
        State.drums.hover_row = row
        State.drums.hover_col = step
      end

      -- Get note
      local note_idx, note = pattern:get_note_at_grid(drum.pitch, step)

      -- Cell color
      local cell_color
      if note then
        if is_note_selected(note_idx) then
          cell_color = Colors.cell_selected
        else
          local vel_factor = note.vel / 127
          cell_color = vel_factor > 0.6 and Colors.cell_filled or Colors.cell_filled_dim
        end
      elseif is_cell_hovered and is_hovered then
        cell_color = Colors.cell_hover
      else
        cell_color = Colors.cell_empty
      end

      r.ImGui_DrawList_AddRectFilled(draw_list, cell_x1, cell_y1, cell_x2, cell_y2, cell_color, 2)

      -- Velocity bar
      if note then
        local vel_h = (note.vel / 127) * (row_h - 6)
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

    -- Horizontal line
    r.ImGui_DrawList_AddLine(draw_list, grid_x, y, grid_x + grid_w, y, Colors.grid_line)
  end

  -- Border
  r.ImGui_DrawList_AddRect(draw_list, grid_x, grid_y, grid_x + grid_w, grid_y + grid_h, Colors.grid_beat)

  -- Playhead
  if State.playback.playing then
    local playhead_step = State.playback.position / pattern.grid_division
    local playhead_x = grid_x + playhead_step * cell_w
    if playhead_x >= grid_x and playhead_x <= grid_x + grid_w then
      r.ImGui_DrawList_AddLine(draw_list, playhead_x, grid_cursor_y,
        playhead_x, grid_y + grid_h, Colors.playhead, 2)
    end
  end

  -- === MOUSE HANDLING ===
  local mouse_down = r.ImGui_IsMouseDown(ctx, 0)
  local mouse_released = r.ImGui_IsMouseReleased(ctx, 0)
  local right_clicked = r.ImGui_IsMouseClicked(ctx, 1)

  -- Handle mouse down
  if is_hovered and r.ImGui_IsMouseClicked(ctx, 0) then
    local row, col = screen_to_cell(mouse_x, mouse_y)
    local clicking_selected = is_clicking_selected_note(pattern, row, col)

    Mouse.on_down(mouse_x, mouse_y, {
      row = row,
      col = col,
      area = Mouse.AREA_GRID,
      click_type = Mouse.CLICK_LEFT,
      ctrl = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl()),
      shift = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift()),
      alt = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Alt()),
    })

    -- If clicking on selected note, prepare for drag-move
    if clicking_selected and get_selection_count() > 0 then
      Mouse.drag_context = { mode = "move" }
    end
  end

  -- Handle mouse drag
  if mouse_down and Mouse.state ~= Mouse.STATE_IDLE then
    local crossed = Mouse.on_drag(mouse_x, mouse_y)

    -- If we crossed threshold and have drag context, switch to dragging mode
    if crossed and Mouse.drag_context and Mouse.drag_context.mode == "move" then
      Mouse.state = Mouse.STATE_DRAGGING
    end
  end

  -- Calculate drag delta for ghost notes
  local drag_row_delta = 0
  local drag_col_delta = 0
  if Mouse.is_dragging() and Mouse.drag_context then
    local current_row, current_col = screen_to_cell(mouse_x, mouse_y)
    if current_row and current_col and Mouse.down_row and Mouse.down_col then
      drag_row_delta = current_row - Mouse.down_row
      drag_col_delta = current_col - Mouse.down_col
    end
  end

  -- Draw ghost notes when dragging
  if Mouse.is_dragging() and Mouse.drag_context then
    local shift_held = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift())

    for idx, _ in pairs(State.drums.selected_notes) do
      local note = pattern.notes[idx]
      if note then
        local note_row = pattern:get_row_for_pitch(note.pitch)
        if note_row then
          local note_col = math.floor(note.start / pattern.grid_division + 0.5)
          local ghost_row = note_row + drag_row_delta
          local ghost_col = note_col + drag_col_delta

          -- Only draw if valid position
          if ghost_row >= 1 and ghost_row <= num_rows and ghost_col >= 0 then
            local gx1, gy1, gx2, gy2 = get_cell_bounds(ghost_row, ghost_col)
            local ghost_color = shift_held and 0x88FF8880 or 0x5B9FD480
            r.ImGui_DrawList_AddRectFilled(draw_list, gx1, gy1, gx2, gy2, ghost_color, 2)
            r.ImGui_DrawList_AddRect(draw_list, gx1, gy1, gx2, gy2, Colors.selection_border, 2)
          end
        end
      end
    end
  end

  -- Handle mouse release
  if mouse_released and Mouse.state ~= Mouse.STATE_IDLE then
    local final_state = Mouse.on_up(mouse_x, mouse_y)

    if final_state == Mouse.STATE_PENDING then
      -- It was a click, not a drag
      local row, col = Mouse.down_row, Mouse.down_col
      if row and col and row > 0 and col >= 0 then
        local drum = pattern.drum_map[row]
        if drum then
          -- If clicking on a selected note without dragging, just keep selection
          local note_idx = pattern:get_note_at_grid(drum.pitch, col)
          if not (note_idx and State.drums.selected_notes[note_idx]) then
            -- Clear selection and toggle note
            clear_selection()
            local idx = pattern:toggle_note(drum.pitch, col, 100)
            if idx then
              MidiOutput.preview_note(drum.pitch, 100, pattern.channel, 150)
            end
            -- Sync to MIDI item
            State.sync_to_midi_item()
          end
        end
      end
    elseif final_state == Mouse.STATE_SELECTING then
      -- Finished drag selection
      select_notes_in_rect(pattern)
    elseif final_state == Mouse.STATE_DRAGGING and Mouse.drag_context then
      -- Finished dragging notes
      local current_row, current_col = screen_to_cell(mouse_x, mouse_y)
      if current_row and current_col and Mouse.down_row and Mouse.down_col then
        local row_delta = current_row - Mouse.down_row
        local col_delta = current_col - Mouse.down_col

        if row_delta ~= 0 or col_delta ~= 0 then
          local shift_held = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift())
          local new_selection

          if shift_held then
            -- Duplicate
            new_selection = pattern:duplicate_notes(State.drums.selected_notes, row_delta, col_delta)
          else
            -- Move
            new_selection = pattern:move_notes(State.drums.selected_notes, row_delta, col_delta)
          end

          State.drums.selected_notes = new_selection
          -- Sync to MIDI item
          State.sync_to_midi_item()
        end
      end
    end

    Mouse.reset()
  end

  -- Draw selection rectangle
  if Mouse.is_selecting() then
    local bounds = Mouse.get_selection_bounds()
    r.ImGui_DrawList_AddRectFilled(draw_list, bounds.x1, bounds.y1, bounds.x2, bounds.y2, Colors.selection_fill)
    r.ImGui_DrawList_AddRect(draw_list, bounds.x1, bounds.y1, bounds.x2, bounds.y2, Colors.selection_border)
  end

  -- Handle right-click for velocity
  if is_hovered and right_clicked then
    local row, col = screen_to_cell(mouse_x, mouse_y)
    if row and col then
      local drum = pattern.drum_map[row]
      local vel_idx, note = pattern:get_note_at_grid(drum.pitch, col)
      if note then
        local new_vel = note.vel <= 40 and 100 or note.vel - 20
        pattern:set_velocity(vel_idx, new_vel)
        MidiOutput.preview_note(drum.pitch, new_vel, pattern.channel, 150)
        -- Sync to MIDI item
        State.sync_to_midi_item()
      end
    end
  end

  -- Mouse wheel zoom
  local wheel = r.ImGui_GetMouseWheel(ctx)
  if is_hovered and r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl()) and wheel ~= 0 then
    State.drums.zoom_x = math.max(0.5, math.min(3.0, State.drums.zoom_x + wheel * 0.1))
  end

  r.ImGui_EndChild(ctx)

  r.ImGui_SameLine(ctx, 0, 0)

  -- === MODIFIERS (right column) ===
  r.ImGui_BeginChild(ctx, "drum_modifiers", MODIFIER_W, grid_h + HEADER_H, 0, 0)
  local mod_x, mod_y = r.ImGui_GetCursorScreenPos(ctx)

  -- Header
  r.ImGui_DrawList_AddRectFilled(draw_list, mod_x, mod_y,
    mod_x + MODIFIER_W, mod_y + HEADER_H, Colors.header_bg)
  r.ImGui_DrawList_AddText(draw_list, mod_x + 4, mod_y + 2, Colors.text_dim, "M S")

  -- Per-row modifiers (placeholder - M=mute, S=solo)
  for i = 1, num_rows do
    local y = mod_y + HEADER_H + (i - 1) * row_h
    local row_bg = (i % 2 == 0) and Colors.row_alt or Colors.bg
    r.ImGui_DrawList_AddRectFilled(draw_list, mod_x, y, mod_x + MODIFIER_W, y + row_h, row_bg)
    -- TODO: Add mute/solo buttons
  end
  r.ImGui_EndChild(ctx)

  -- === ZOOM CONTROLS (below grid) ===
  r.ImGui_Spacing(ctx)
  r.ImGui_Text(ctx, "Zoom:")
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 100)
  local changed, new_zoom = r.ImGui_SliderDouble(ctx, "##zoom", State.drums.zoom_x, 0.5, 3.0, "%.1fx")
  if changed then State.drums.zoom_x = new_zoom end
  r.ImGui_SameLine(ctx)

  -- Show selection count if any
  local sel_count = get_selection_count()
  if sel_count > 0 then
    r.ImGui_Text(ctx, string.format("| Sel: %d | Steps: %d | Bars: %d",
      sel_count, grid_steps, pattern.length_bars))
  else
    r.ImGui_Text(ctx, string.format("| Steps: %d | Bars: %d", grid_steps, pattern.length_bars))
  end
end

return DrumEditor
