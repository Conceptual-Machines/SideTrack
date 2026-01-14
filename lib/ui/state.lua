-- Shared UI state for SideTrack

local Pattern = require('pattern')
local MidiOutput = require('midi_output')

local State = {}

-- ImGui context (set by main script)
State.ctx = nil

-- Current view
State.view = "drums"  -- "drums", "piano", "steps"

-- Pattern management
State.patterns = {}
State.current_pattern_idx = 1

-- Linked MIDI item
State.linked_take = nil
State.link_enabled = true
State.clip_prefix = "ST: "  -- Prefix for SideTrack-created clips

-- Initialize default pattern
function State.init()
  State.patterns[1] = Pattern.new("Pattern 1", 4)
end

-- Sync pattern length with linked MIDI item
function State.sync_with_midi_item()
  local r = reaper
  if not State.link_enabled then return end

  local pattern = State.get_pattern()
  if not pattern then return end

  -- Get selected MIDI item
  local item = r.GetSelectedMediaItem(0, 0)
  if not item then
    -- Don't unlink if we have a SideTrack clip - it might just be deselected
    if not State.is_sidetrack_clip() then
      State.linked_take = nil
    end
    return
  end

  local take = r.GetActiveTake(item)
  if not take or not r.TakeIsMIDI(take) then
    if not State.is_sidetrack_clip() then
      State.linked_take = nil
    end
    return
  end

  -- Check if this is a SideTrack clip
  local _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  local is_st_clip = name and name:sub(1, #State.clip_prefix) == State.clip_prefix

  -- If selecting a different item
  if take ~= State.linked_take then
    if is_st_clip then
      -- Link to ST clip, read source length
      State.linked_take = take
      local source_bars = MidiOutput.get_source_length_bars(take)
      if source_bars and source_bars > 0 then
        pattern.length_bars = math.max(1, math.floor(source_bars + 0.5))
      end
    elseif not State.is_sidetrack_clip() then
      -- Link to regular clip, read length from item
      State.linked_take = take
      local item_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      local tempo = r.Master_GetTempo()
      local sec_per_bar = 4 * 60 / tempo
      local length_bars = item_length / sec_per_bar
      pattern.length_bars = math.max(1, math.floor(length_bars + 0.5))
    end
  -- Removed: was overwriting pattern.length_bars every frame
  -- For ST clips, pattern controls the length, not the other way around
  end
end

-- Update linked MIDI item length from pattern
function State.update_linked_item_length()
  local r = reaper
  if not State.link_enabled or not State.linked_take then return end

  local pattern = State.get_pattern()
  if not pattern then return end

  local item = r.GetMediaItemTake_Item(State.linked_take)
  if not item then return end

  local tempo = r.Master_GetTempo()
  local sec_per_bar = 4 * 60 / tempo
  local new_length = pattern.length_bars * sec_per_bar

  r.SetMediaItemInfo_Value(item, "D_LENGTH", new_length)
  r.UpdateArrange()
end

-- Sync pattern notes to linked MIDI item (auto-print on edit)
-- Recreates the MIDI item to set the correct source loop length
function State.sync_to_midi_item()
  local r = reaper

  if not State.link_enabled or not State.linked_take then return end

  local pattern = State.get_pattern()
  if not pattern then return end

  -- Validate take is still valid
  local item = r.GetMediaItemTake_Item(State.linked_take)
  if not item then
    State.linked_take = nil
    return
  end

  local track = r.GetMediaItemTake_Track(State.linked_take)
  if not track then
    State.linked_take = nil
    return
  end

  -- Calculate target source loop length
  local tempo = r.Master_GetTempo()
  local sec_per_bar = 4 * 60 / tempo
  local target_length = pattern.length_bars * sec_per_bar

  local old_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  local was_looping = r.GetMediaItemInfo_Value(item, "B_LOOPSRC")
  local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")

  -- Get the clip name before any modifications
  local _, clip_name = r.GetSetMediaItemTakeInfo_String(State.linked_take, "P_NAME", "", false)

  r.Undo_BeginBlock()

  -- Clear linked_take before deleting to prevent other code from accessing it
  State.linked_take = nil

  r.DeleteTrackMediaItem(track, item)

  -- Create new item with SOURCE LOOP length
  local new_item = r.CreateNewMIDIItemInProj(track, item_pos, item_pos + target_length, false)
  if not new_item then
    r.Undo_EndBlock("SideTrack: Update clip (failed)", -1)
    return
  end

  local new_take = r.GetActiveTake(new_item)
  if not new_take then
    r.Undo_EndBlock("SideTrack: Update clip (failed)", -1)
    return
  end

  -- Restore name
  if clip_name and clip_name ~= "" then
    r.GetSetMediaItemTakeInfo_String(new_take, "P_NAME", clip_name, true)
  end

  -- Enable loop BEFORE extending (so the source loop is set)
  if was_looping == 1 then
    r.SetMediaItemInfo_Value(new_item, "B_LOOPSRC", 1)
  end

  -- Restore original item length (keep total length, source loop is now target_length)
  if old_length > target_length then
    r.SetMediaItemInfo_Value(new_item, "D_LENGTH", old_length)
  end

  -- Update linked take reference
  State.linked_take = new_take

  -- Print notes to new item
  MidiOutput.print_to_item(pattern, new_take, "replace")

  -- Select the new item
  r.SetMediaItemSelected(new_item, true)

  r.Undo_EndBlock("SideTrack: Update clip", -1)
  r.UpdateArrange()
end

-- Create a new SideTrack-managed MIDI clip
function State.create_clip()
  local r = reaper
  local pattern = State.get_pattern()
  if not pattern then return false end

  local track = r.GetSelectedTrack(0, 0)
  if not track then
    r.ShowMessageBox("Select a track first", "SideTrack", 0)
    return false
  end

  local cursor_pos = r.GetCursorPosition()
  local tempo = r.Master_GetTempo()
  local sec_per_bar = 4 * 60 / tempo
  local source_length = pattern.length_bars * sec_per_bar

  r.Undo_BeginBlock()

  -- Create MIDI item (start with source length, user can extend later)
  local item = r.CreateNewMIDIItemInProj(track, cursor_pos, cursor_pos + source_length, false)
  if not item then
    r.Undo_EndBlock("SideTrack: Create clip (failed)", -1)
    return false
  end

  local take = r.GetActiveTake(item)
  if not take then
    r.Undo_EndBlock("SideTrack: Create clip (failed)", -1)
    return false
  end

  -- Set clip name with prefix
  local clip_name = State.clip_prefix .. pattern.name
  r.GetSetMediaItemTakeInfo_String(take, "P_NAME", clip_name, true)

  -- Enable loop source
  r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 1)

  -- Link to this new clip
  State.linked_take = take

  -- Sync pattern to clip
  State.sync_to_midi_item()

  r.Undo_EndBlock("SideTrack: Create clip", -1)
  r.UpdateArrange()

  return true
end

-- Check if current linked clip is a SideTrack clip (has prefix)
function State.is_sidetrack_clip()
  if not State.linked_take then return false end

  local r = reaper
  local _, name = r.GetSetMediaItemTakeInfo_String(State.linked_take, "P_NAME", "", false)
  return name and name:sub(1, #State.clip_prefix) == State.clip_prefix
end

-- Update linked clip name when pattern name changes
function State.update_clip_name()
  if not State.linked_take or not State.is_sidetrack_clip() then return end

  local r = reaper
  local pattern = State.get_pattern()
  if not pattern then return end

  local clip_name = State.clip_prefix .. pattern.name
  r.GetSetMediaItemTakeInfo_String(State.linked_take, "P_NAME", clip_name, true)
  r.UpdateArrange()
end

-- Get current pattern
function State.get_pattern()
  return State.patterns[State.current_pattern_idx]
end

-- Drum editor state
State.drums = {
  hover_row = -1,
  hover_col = -1,
  last_click_time = 0,
  last_click_row = -1,
  last_click_col = -1,
  zoom_x = 1.0,
  selected_notes = {},  -- {[note_idx] = true}
}

-- Playback state (synced to REAPER transport)
State.playback = {
  playing = false,
  position = 0,  -- in bars (relative to pattern)
  last_position = -1,
  active_notes = {},  -- {pitch = true} for notes currently on
  live_mode = false,  -- disabled: MIDI item handles playback via sync
}

-- Update playback state from REAPER transport
function State.update_playback()
  local r = reaper
  local play_state = r.GetPlayState()
  local was_playing = State.playback.playing
  State.playback.playing = (play_state & 1) == 1  -- bit 0 = playing

  -- If stopped, turn off any active notes and reset position
  if was_playing and not State.playback.playing then
    for pitch, _ in pairs(State.playback.active_notes) do
      MidiOutput.note_off(pitch, 0)
    end
    State.playback.active_notes = {}
    State.playback.position = -1
    State.playback.last_position = -1
    return
  end

  -- Detect just started playing
  local just_started = not was_playing and State.playback.playing

  if State.playback.playing then
    local pattern = State.get_pattern()
    if pattern then
      -- Get play position in beats, convert to bars
      local play_pos = r.GetPlayPosition()
      local tempo = r.Master_GetTempo()
      local sec_per_bar = 4 * 60 / tempo
      local pos_in_bars = play_pos / sec_per_bar

      -- Loop within pattern length
      local prev_pos = State.playback.position
      State.playback.position = pos_in_bars % pattern.length_bars

      -- Detect loop wraparound (position jumped backwards significantly)
      local looped = prev_pos >= 0 and
                     (State.playback.position < prev_pos - 0.1) and
                     prev_pos > 0.5

      -- Live MIDI output
      if State.playback.live_mode then
        -- Turn off notes that ended
        for pitch, note_end in pairs(State.playback.active_notes) do
          if State.playback.position >= note_end or looped then
            MidiOutput.note_off(pitch, pattern.channel)
            State.playback.active_notes[pitch] = nil
          end
        end

        -- Turn on notes that started
        for _, note in ipairs(pattern.notes) do
          if not note.muted then
            local note_start = note.start
            local note_end = note.start + note.length

            -- Check if we just crossed into this note
            -- Handle: normal crossing, loop wrap, or just started playing
            local crossed_start

            if just_started or looped then
              -- On start or loop: trigger notes at or before current position
              -- but only up to a small window to avoid triggering all notes
              crossed_start = note_start <= State.playback.position and
                              State.playback.position < note_start + pattern.grid_division
            else
              -- Normal: detect crossing from prev to current
              crossed_start = prev_pos < note_start and State.playback.position >= note_start
            end

            if crossed_start and not State.playback.active_notes[note.pitch] then
              MidiOutput.note_on(note.pitch, note.vel, pattern.channel)
              State.playback.active_notes[note.pitch] = note_end
            end
          end
        end
      end

      State.playback.last_position = State.playback.position
    end
  end
end

-- Piano roll state
State.piano = {
  note_min = 48,  -- C3
  note_max = 72,  -- C5
  zoom_x = 1.0,
  dragging = nil,
  selected_note = nil,
  hover_note = nil,
}

-- Step sequencer state
State.steps = {
  base_pitch = 60,  -- C4
  num_rows = 12,
  hover_row = -1,
  hover_col = -1,
}

return State
