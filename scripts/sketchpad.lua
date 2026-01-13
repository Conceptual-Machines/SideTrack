-- @description SideTrack: MIDI Sketchpad
-- @author Conceptual Machines
-- @version 0.1.0
-- @about
--   MIDI sketchpad with drum editor, piano roll, and step sequencer.
--   Create patterns and print them to MIDI tracks.

local r = reaper

-- Check for ReaImGui
if not r.ImGui_CreateContext then
  r.ShowMessageBox("ReaImGui is required.\nInstall via ReaPack.", "SideTrack", 0)
  return
end

-- Path setup
local script_path = ({r.get_action_context()})[2]:match('^.+[\\//]')
package.path = script_path .. "../lib/?.lua;" .. package.path

-- Modules
local Pattern = require('pattern')
local MidiOutput = require('midi_output')

--------------------------------------------------------------------------------
-- Colors
--------------------------------------------------------------------------------

local COLORS = {
  bg = 0x1E1E22FF,
  grid_line = 0x383840FF,
  grid_beat = 0x484850FF,
  grid_bar = 0x5a5a60FF,
  cell_empty = 0x2a2a30FF,
  cell_hover = 0x3a3a44FF,
  cell_filled = 0x5B9FD4FF,
  cell_filled_dim = 0x3a6a94FF,
  text = 0xCCCCCCFF,
  text_dim = 0x888888FF,
  row_alt = 0x24242aFF,
  header_bg = 0x2a2a32FF,
  button = 0x3a3a44FF,
  button_hover = 0x4a4a54FF,
  button_active = 0x5B9FD4FF,
  accent = 0x5B9FD4FF,
  velocity_bar = 0xFFAA22FF,
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local ctx = r.ImGui_CreateContext('SideTrack Sketchpad')

local state = {
  patterns = {},
  current_pattern_idx = 1,
  view = "drums",  -- "drums", "piano", "steps"
  scroll_x = 0,
  scroll_y = 0,
  hover_row = -1,
  hover_col = -1,
  drag_velocity = false,
  drag_start_vel = 0,
  playing_preview = false,
}

-- Initialize with default pattern
state.patterns[1] = Pattern.new("Pattern 1", 2)

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function get_current_pattern()
  return state.patterns[state.current_pattern_idx]
end

--------------------------------------------------------------------------------
-- Drum Editor View
--------------------------------------------------------------------------------

local function draw_drum_editor()
  local pattern = get_current_pattern()
  if not pattern then return end

  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)

  -- Dimensions
  local row_label_w = 80
  local row_h = 24
  local cell_w = 28
  local header_h = 24

  local grid_x = cursor_x + row_label_w
  local grid_y = cursor_y + header_h
  local grid_steps = pattern:get_grid_steps()
  local grid_w = grid_steps * cell_w
  local num_rows = #pattern.drum_map
  local grid_h = num_rows * row_h

  local total_w = row_label_w + grid_w
  local total_h = header_h + grid_h

  -- Reserve space
  r.ImGui_InvisibleButton(ctx, "drum_grid", total_w, total_h)
  local is_hovered = r.ImGui_IsItemHovered(ctx)
  local is_clicked = r.ImGui_IsItemClicked(ctx, 0)
  local is_right_clicked = r.ImGui_IsItemClicked(ctx, 1)

  -- Background
  r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y,
    cursor_x + total_w, cursor_y + total_h, COLORS.bg)

  -- Header background
  r.ImGui_DrawList_AddRectFilled(draw_list, grid_x, cursor_y,
    grid_x + grid_w, cursor_y + header_h, COLORS.header_bg)

  -- Beat/bar markers in header
  for step = 0, grid_steps - 1 do
    local x = grid_x + step * cell_w
    local is_bar = (step * pattern.grid_division) % 1 == 0

    if is_bar then
      local bar_num = math.floor(step * pattern.grid_division) + 1
      r.ImGui_DrawList_AddText(draw_list, x + 4, cursor_y + 4, COLORS.text, tostring(bar_num))
    end
  end

  -- Row labels (drum names)
  for i, drum in ipairs(pattern.drum_map) do
    local y = grid_y + (i - 1) * row_h
    local row_bg = (i % 2 == 0) and COLORS.row_alt or COLORS.bg
    r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, y, cursor_x + row_label_w, y + row_h, row_bg)
    r.ImGui_DrawList_AddText(draw_list, cursor_x + 4, y + 4, COLORS.text_dim, drum.name)
  end

  -- Grid cells
  local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)

  state.hover_row = -1
  state.hover_col = -1

  for row = 1, num_rows do
    local drum = pattern.drum_map[row]
    local y = grid_y + (row - 1) * row_h

    for step = 0, grid_steps - 1 do
      local x = grid_x + step * cell_w

      -- Cell bounds
      local cell_x1 = x + 1
      local cell_y1 = y + 1
      local cell_x2 = x + cell_w - 1
      local cell_y2 = y + row_h - 1

      -- Check hover
      local is_cell_hovered = mouse_x >= cell_x1 and mouse_x < cell_x2 and
                              mouse_y >= cell_y1 and mouse_y < cell_y2

      if is_cell_hovered and is_hovered then
        state.hover_row = row
        state.hover_col = step
      end

      -- Get note at this cell
      local _, note = pattern:get_note_at_grid(drum.pitch, step)

      -- Draw cell
      local cell_color
      if note then
        local vel_factor = note.vel / 127
        cell_color = vel_factor > 0.6 and COLORS.cell_filled or COLORS.cell_filled_dim
      elseif is_cell_hovered and is_hovered then
        cell_color = COLORS.cell_hover
      else
        cell_color = COLORS.cell_empty
      end

      r.ImGui_DrawList_AddRectFilled(draw_list, cell_x1, cell_y1, cell_x2, cell_y2, cell_color, 2)

      -- Velocity bar for filled cells
      if note then
        local vel_h = (note.vel / 127) * (row_h - 6)
        local bar_y = cell_y2 - vel_h - 2
        r.ImGui_DrawList_AddRectFilled(draw_list,
          cell_x1 + 2, bar_y, cell_x2 - 2, cell_y2 - 2, COLORS.velocity_bar, 1)
      end

      -- Grid lines
      local is_bar = (step * pattern.grid_division) % 1 == 0
      local is_beat = (step * pattern.grid_division) % 0.25 == 0
      local line_color = is_bar and COLORS.grid_bar or (is_beat and COLORS.grid_beat or COLORS.grid_line)
      r.ImGui_DrawList_AddLine(draw_list, x, grid_y, x, grid_y + grid_h, line_color)
    end

    -- Horizontal row line
    r.ImGui_DrawList_AddLine(draw_list, grid_x, y, grid_x + grid_w, y, COLORS.grid_line)
  end

  -- Border
  r.ImGui_DrawList_AddRect(draw_list, grid_x, grid_y, grid_x + grid_w, grid_y + grid_h, COLORS.grid_beat)

  -- Handle clicks
  if is_hovered and state.hover_row > 0 and state.hover_col >= 0 then
    local drum = pattern.drum_map[state.hover_row]

    if is_clicked then
      local idx = pattern:toggle_note(drum.pitch, state.hover_col, 100)
      if idx then
        MidiOutput.preview_note(drum.pitch, 100, pattern.channel, 150)
      end
    elseif is_right_clicked then
      local vel_idx, note = pattern:get_note_at_grid(drum.pitch, state.hover_col)
      if note then
        local new_vel = note.vel <= 40 and 100 or note.vel - 20
        pattern:set_velocity(vel_idx, new_vel)
        MidiOutput.preview_note(drum.pitch, new_vel, pattern.channel, 150)
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Main Window
--------------------------------------------------------------------------------

local function main()
  local pattern = get_current_pattern()

  r.ImGui_SetNextWindowSize(ctx, 700, 450, r.ImGui_Cond_FirstUseEver())
  local visible, open = r.ImGui_Begin(ctx, 'SideTrack Sketchpad', true)

  if visible then
    -- Header row
    r.ImGui_SetNextItemWidth(ctx, 150)
    local changed, new_name = r.ImGui_InputText(ctx, "##name", pattern.name)
    if changed then pattern.name = new_name end

    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 60)
    local changed_len, new_len = r.ImGui_DragInt(ctx, "Bars", pattern.length_bars, 0.1, 1, 16)
    if changed_len then pattern.length_bars = new_len end

    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 80)
    local grid_options = {"1/4", "1/8", "1/16", "1/32"}
    local grid_values = {0.25, 0.125, 0.0625, 0.03125}
    local current_grid_idx = 1
    for i, v in ipairs(grid_values) do
      if math.abs(pattern.grid_division - v) < 0.001 then current_grid_idx = i break end
    end
    if r.ImGui_BeginCombo(ctx, "Grid", grid_options[current_grid_idx]) then
      for i, label in ipairs(grid_options) do
        if r.ImGui_Selectable(ctx, label, i == current_grid_idx) then
          pattern.grid_division = grid_values[i]
        end
      end
      r.ImGui_EndCombo(ctx)
    end

    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, string.format("Notes: %d", #pattern.notes))

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    -- View tabs
    if r.ImGui_Button(ctx, "Drums", 60, 0) then state.view = "drums" end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Piano", 60, 0) then state.view = "piano" end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Steps", 60, 0) then state.view = "steps" end

    r.ImGui_SameLine(ctx, r.ImGui_GetContentRegionAvail(ctx) - 200)
    if r.ImGui_Button(ctx, "Clear", 50, 0) then pattern:clear() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Preview", 60, 0) then MidiOutput.preview_pattern(pattern) end

    r.ImGui_Spacing(ctx)

    -- Editor view
    if state.view == "drums" then
      draw_drum_editor()
    elseif state.view == "piano" then
      r.ImGui_Text(ctx, "Piano Roll (coming soon)")
    elseif state.view == "steps" then
      r.ImGui_Text(ctx, "Step Sequencer (coming soon)")
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    -- Bottom row: print controls
    if r.ImGui_Button(ctx, "Print to Selected Item", 150, 30) then
      local take = MidiOutput.get_selected_midi_take()
      if take then
        local count = MidiOutput.print_to_item(pattern, take, "replace")
        r.ShowConsoleMsg(string.format("SideTrack: Printed %d notes\n", count))
      else
        r.ShowMessageBox("Select a MIDI item first", "SideTrack", 0)
      end
    end

    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Print to New Item", 150, 30) then
      local count = MidiOutput.print_to_new_item(pattern)
      if count then
        r.ShowConsoleMsg(string.format("SideTrack: Created item with %d notes\n", count))
      end
    end

    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Append", 80, 30) then
      local take = MidiOutput.get_selected_midi_take()
      if take then
        local count = MidiOutput.print_to_item(pattern, take, "append")
        r.ShowConsoleMsg(string.format("SideTrack: Appended %d notes\n", count))
      end
    end

    r.ImGui_End(ctx)
  end

  if open then
    r.defer(main)
  end
end

main()
