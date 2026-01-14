-- @description SideTrack: MIDI Sketchpad
-- @author Conceptual Machines
-- @version 0.1.0
-- @provides
--   [nomain] lib/*.lua
--   [nomain] lib/ui/*.lua
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
package.path = script_path .. "lib/?.lua;"
            .. script_path .. "lib/ui/?.lua;"
            .. package.path

-- Modules
local State = require('state')
local MidiOutput = require('midi_output')
local DrumEditor = require('drum_editor')
local PianoRoll = require('piano_roll')
local StepSeq = require('step_seq')

-- Initialize
local ctx = r.ImGui_CreateContext('SideTrack', r.ImGui_ConfigFlags_DockingEnable())
State.ctx = ctx
State.init()

--------------------------------------------------------------------------------
-- Main Window
--------------------------------------------------------------------------------

local function main()
  -- Sync playhead to REAPER transport
  State.update_playback()

  -- Sync pattern length with selected MIDI item
  State.sync_with_midi_item()

  local pattern = State.get_pattern()

  r.ImGui_SetNextWindowSize(ctx, 700, 500, r.ImGui_Cond_FirstUseEver())
  local visible, open = r.ImGui_Begin(ctx, 'SideTrack', true)

  if visible then
    -- Header row
    r.ImGui_SetNextItemWidth(ctx, 150)
    local changed, new_name = r.ImGui_InputText(ctx, "##name", pattern.name)
    if changed then
      pattern.name = new_name
      State.update_clip_name()
    end

    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 60)
    local changed_len, new_len = r.ImGui_DragInt(ctx, "Bars", pattern.length_bars, 0.1, 1, 16)
    if changed_len then
      pattern.length_bars = new_len
      State.sync_to_midi_item()
    end

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

    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, "|")
    r.ImGui_SameLine(ctx)

    -- Link controls
    if State.linked_take then
      if State.is_sidetrack_clip() then
        r.ImGui_TextColored(ctx, 0x88FF88FF, "ST Clip")
      else
        r.ImGui_TextColored(ctx, 0xFFAA44FF, "Linked")
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_SmallButton(ctx, "Unlink") then
        State.linked_take = nil
      end
    else
      r.ImGui_TextColored(ctx, 0x888888FF, "No clip")
      r.ImGui_SameLine(ctx)
      if r.ImGui_SmallButton(ctx, "Create") then
        State.create_clip()
      end
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    -- View tabs
    if r.ImGui_Button(ctx, "Drums", 60, 0) then State.view = "drums" end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Piano", 60, 0) then State.view = "piano" end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Steps", 60, 0) then State.view = "steps" end

    r.ImGui_SameLine(ctx, r.ImGui_GetContentRegionAvail(ctx) - 60)
    if r.ImGui_Button(ctx, "Clear", 50, 0) then
      pattern:clear()
      State.sync_to_midi_item()
    end

    r.ImGui_Spacing(ctx)

    -- Editor view
    if State.view == "drums" then
      DrumEditor.draw()
    elseif State.view == "piano" then
      PianoRoll.draw()
    elseif State.view == "steps" then
      StepSeq.draw()
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

  end

  r.ImGui_End(ctx)

  if open then
    r.defer(main)
  end
end

main()
