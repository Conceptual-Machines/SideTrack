-- Shared UI state for SideTrack

local Pattern = require('pattern')

local State = {}

-- ImGui context (set by main script)
State.ctx = nil

-- Current view
State.view = "drums"  -- "drums", "piano", "steps"

-- Pattern management
State.patterns = {}
State.current_pattern_idx = 1

-- Initialize default pattern
function State.init()
  State.patterns[1] = Pattern.new("Pattern 1", 2)
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
}

-- Playback state (synced to REAPER transport)
State.playback = {
  playing = false,
  position = 0,  -- in bars (relative to pattern)
  last_position = -1,
  active_notes = {},  -- {pitch = true} for notes currently on
  live_mode = true,  -- send MIDI during playback
}

-- Update playback state from REAPER transport
function State.update_playback()
  local r = reaper
  local MidiOutput = require('midi_output')
  local play_state = r.GetPlayState()
  local was_playing = State.playback.playing
  State.playback.playing = (play_state & 1) == 1  -- bit 0 = playing

  -- If stopped, turn off any active notes
  if was_playing and not State.playback.playing then
    for pitch, _ in pairs(State.playback.active_notes) do
      MidiOutput.note_off(pitch, 0)
    end
    State.playback.active_notes = {}
    State.playback.last_position = -1
    return
  end

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

      -- Detect loop wraparound
      local looped = State.playback.position < prev_pos and prev_pos > 0

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
            local crossed_start = (prev_pos < note_start and State.playback.position >= note_start)
                                  or (looped and State.playback.position >= note_start)

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
