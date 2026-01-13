-- MIDI output module
-- Handles printing patterns to REAPER tracks

local r = reaper

local MidiOutput = {}

-- Get PPQ (pulses per quarter note) for a take
function MidiOutput.get_ppq(take)
  if not take then return 960 end  -- Default
  local item = r.GetMediaItemTake_Item(take)
  local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local ppq_start = r.MIDI_GetPPQPosFromProjTime(take, item_pos)
  local ppq_quarter = r.MIDI_GetPPQPosFromProjTime(take, item_pos + (60 / r.Master_GetTempo()))
  return ppq_quarter - ppq_start
end

-- Convert bars to PPQ
function MidiOutput.bars_to_ppq(bars, ppq_per_quarter)
  -- Assuming 4/4 time: 1 bar = 4 quarter notes
  return bars * 4 * ppq_per_quarter
end

-- Print pattern to selected MIDI item
function MidiOutput.print_to_item(pattern, take, mode)
  if not take then
    r.ShowMessageBox("No MIDI item selected", "SideTrack", 0)
    return false
  end

  mode = mode or "replace"  -- "replace", "merge", "append"

  local ppq = MidiOutput.get_ppq(take)

  r.Undo_BeginBlock()
  r.MIDI_DisableSort(take)

  -- Clear existing notes if replace mode
  if mode == "replace" then
    local _, note_count = r.MIDI_CountEvts(take)
    for i = note_count - 1, 0, -1 do
      r.MIDI_DeleteNote(take, i)
    end
  end

  -- Get item start for append mode
  local append_offset = 0
  if mode == "append" then
    local _, note_count = r.MIDI_CountEvts(take)
    local max_end = 0
    for i = 0, note_count - 1 do
      local _, _, _, _, endppq = r.MIDI_GetNote(take, i)
      if endppq > max_end then max_end = endppq end
    end
    append_offset = max_end
  end

  -- Insert pattern notes
  local notes_added = 0
  for _, note in ipairs(pattern.notes) do
    if not note.muted then
      local start_ppq = MidiOutput.bars_to_ppq(pattern:apply_swing(note.start), ppq) + append_offset
      local end_ppq = start_ppq + MidiOutput.bars_to_ppq(note.length, ppq)

      r.MIDI_InsertNote(take, false, false, start_ppq, end_ppq,
        pattern.channel, note.pitch, note.vel, true)
      notes_added = notes_added + 1
    end
  end

  r.MIDI_Sort(take)

  -- Extend item if needed
  local item = r.GetMediaItemTake_Item(take)
  local pattern_length_sec = pattern.length_bars * (4 * 60 / r.Master_GetTempo())
  local current_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")

  if mode == "append" then
    r.SetMediaItemInfo_Value(item, "D_LENGTH", current_length + pattern_length_sec)
  elseif pattern_length_sec > current_length then
    r.SetMediaItemInfo_Value(item, "D_LENGTH", pattern_length_sec)
  end

  r.MarkTrackItemsDirty(r.GetMediaItemTake_Track(take), item)
  r.Undo_EndBlock("Print SideTrack pattern", -1)

  return notes_added
end

-- Create new MIDI item and print pattern
function MidiOutput.print_to_new_item(pattern, track)
  if not track then
    track = r.GetSelectedTrack(0, 0)
  end

  if not track then
    r.ShowMessageBox("No track selected", "SideTrack", 0)
    return false
  end

  local cursor_pos = r.GetCursorPosition()
  local pattern_length_sec = pattern.length_bars * (4 * 60 / r.Master_GetTempo())

  -- Create new MIDI item
  local item = r.CreateNewMIDIItemInProj(track, cursor_pos, cursor_pos + pattern_length_sec, false)
  local take = r.GetActiveTake(item)

  if take then
    return MidiOutput.print_to_item(pattern, take, "replace")
  end

  return false
end

-- Get selected MIDI take
function MidiOutput.get_selected_midi_take()
  -- First try MIDI editor
  local midi_editor = r.MIDIEditor_GetActive()
  if midi_editor then
    return r.MIDIEditor_GetTake(midi_editor)
  end

  -- Then try selected item
  local item = r.GetSelectedMediaItem(0, 0)
  if item then
    local take = r.GetActiveTake(item)
    if take and r.TakeIsMIDI(take) then
      return take
    end
  end

  return nil
end

-- MIDI output mode: 0=VKB, 1=control/track input, 2=hardware output
local MIDI_MODE = 1

-- Preview note (trigger MIDI output)
function MidiOutput.preview_note(pitch, vel, channel, duration_ms)
  vel = vel or 100
  channel = channel or 0
  duration_ms = duration_ms or 200

  -- Note on
  r.StuffMIDIMessage(MIDI_MODE, 0x90 + channel, pitch, vel)

  -- Schedule note off (using defer)
  local start_time = r.time_precise()
  local function check_off()
    if (r.time_precise() - start_time) * 1000 >= duration_ms then
      r.StuffMIDIMessage(MIDI_MODE, 0x80 + channel, pitch, 0)
    else
      r.defer(check_off)
    end
  end
  r.defer(check_off)
end

-- Send note on (for live playback)
function MidiOutput.note_on(pitch, vel, channel)
  vel = vel or 100
  channel = channel or 0
  r.StuffMIDIMessage(MIDI_MODE, 0x90 + channel, pitch, vel)
end

-- Send note off
function MidiOutput.note_off(pitch, channel)
  channel = channel or 0
  r.StuffMIDIMessage(MIDI_MODE, 0x80 + channel, pitch, 0)
end

-- Playback state reference (set by main script)
MidiOutput.playback_state = nil

-- Preview pattern with playhead
function MidiOutput.preview_pattern(pattern, bpm)
  bpm = bpm or r.Master_GetTempo()
  local sec_per_bar = 4 * 60 / bpm
  local pattern_length = pattern.length_bars

  -- Sort notes by start time
  local sorted = {}
  for _, note in ipairs(pattern.notes) do
    if not note.muted then
      table.insert(sorted, note)
    end
  end
  table.sort(sorted, function(a, b) return a.start < b.start end)

  -- Set playback state
  local start_time = r.time_precise()
  local note_idx = 1

  if MidiOutput.playback_state then
    MidiOutput.playback_state.playing = true
    MidiOutput.playback_state.start_time = start_time
    MidiOutput.playback_state.position = 0
  end

  local function play_loop()
    local now = r.time_precise() - start_time
    local position_bars = now / sec_per_bar

    -- Update playhead position
    if MidiOutput.playback_state then
      MidiOutput.playback_state.position = position_bars
    end

    -- Check if pattern finished
    if position_bars >= pattern_length then
      if MidiOutput.playback_state then
        MidiOutput.playback_state.playing = false
        MidiOutput.playback_state.position = 0
      end
      return
    end

    -- Play notes that are due
    while note_idx <= #sorted do
      local note = sorted[note_idx]
      local note_time = pattern:apply_swing(note.start) * sec_per_bar

      if now >= note_time then
        local dur_ms = note.length * sec_per_bar * 1000
        MidiOutput.preview_note(note.pitch, note.vel, pattern.channel, dur_ms)
        note_idx = note_idx + 1
      else
        break
      end
    end

    r.defer(play_loop)
  end

  r.defer(play_loop)
end

-- Stop playback
function MidiOutput.stop_playback()
  if MidiOutput.playback_state then
    MidiOutput.playback_state.playing = false
    MidiOutput.playback_state.position = 0
  end
end

return MidiOutput
