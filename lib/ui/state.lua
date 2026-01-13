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
}

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
