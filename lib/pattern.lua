-- Pattern data structure and operations
-- Core module for SideTrack sketchpad

local Pattern = {}
Pattern.__index = Pattern

-- Default drum map (General MIDI)
Pattern.DEFAULT_DRUM_MAP = {
  {pitch = 36, name = "Kick"},
  {pitch = 38, name = "Snare"},
  {pitch = 42, name = "HH Closed"},
  {pitch = 46, name = "HH Open"},
  {pitch = 45, name = "Tom Low"},
  {pitch = 48, name = "Tom Mid"},
  {pitch = 50, name = "Tom High"},
  {pitch = 49, name = "Crash"},
  {pitch = 51, name = "Ride"},
  {pitch = 37, name = "Rimshot"},
  {pitch = 39, name = "Clap"},
  {pitch = 56, name = "Cowbell"},
}

-- Create new pattern
function Pattern.new(name, length_bars)
  local self = setmetatable({}, Pattern)
  self.name = name or "New Pattern"
  self.length_bars = length_bars or 2
  self.notes = {}  -- {pitch, start, length, vel, muted}
  self.grid_division = 0.25  -- 1/16 note (in bars)
  self.swing = 0  -- -1 to 1
  self.channel = 0  -- MIDI channel (0-15)
  self.drum_map = Pattern.copy_drum_map(Pattern.DEFAULT_DRUM_MAP)
  return self
end

-- Deep copy drum map
function Pattern.copy_drum_map(map)
  local copy = {}
  for i, row in ipairs(map) do
    copy[i] = {pitch = row.pitch, name = row.name}
  end
  return copy
end

-- Add a note
function Pattern:add_note(pitch, start, length, vel, muted)
  table.insert(self.notes, {
    pitch = pitch,
    start = start,  -- in bars (0 = start of pattern)
    length = length or self.grid_division,
    vel = vel or 100,
    muted = muted or false,
  })
  return #self.notes
end

-- Remove note by index
function Pattern:remove_note(idx)
  if idx > 0 and idx <= #self.notes then
    table.remove(self.notes, idx)
    return true
  end
  return false
end

-- Find note at position
function Pattern:find_note_at(pitch, time, tolerance)
  tolerance = tolerance or 0.01
  for i, note in ipairs(self.notes) do
    if note.pitch == pitch then
      if time >= note.start - tolerance and time < note.start + note.length + tolerance then
        return i, note
      end
    end
  end
  return nil
end

-- Find all notes for a pitch
function Pattern:get_notes_for_pitch(pitch)
  local result = {}
  for i, note in ipairs(self.notes) do
    if note.pitch == pitch then
      table.insert(result, {idx = i, note = note})
    end
  end
  return result
end

-- Toggle note at grid position (for drum editor)
function Pattern:toggle_note(pitch, grid_pos, vel)
  vel = vel or 100
  local idx = self:get_note_at_grid(pitch, grid_pos)

  if idx then
    self:remove_note(idx)
    return nil
  else
    local start = grid_pos * self.grid_division
    return self:add_note(pitch, start, self.grid_division, vel)
  end
end

-- Get note at grid position (checks if note START is at this grid cell)
function Pattern:get_note_at_grid(pitch, grid_pos)
  local cell_start = grid_pos * self.grid_division
  local cell_end = cell_start + self.grid_division
  -- Find note whose start falls within this cell
  for i, note in ipairs(self.notes) do
    if note.pitch == pitch then
      if note.start >= cell_start and note.start < cell_end then
        return i, note
      end
    end
  end
  return nil
end

-- Set note velocity
function Pattern:set_velocity(idx, vel)
  if self.notes[idx] then
    self.notes[idx].vel = math.max(1, math.min(127, vel))
    return true
  end
  return false
end

-- Get grid steps count
function Pattern:get_grid_steps()
  return math.floor(self.length_bars / self.grid_division + 0.5)
end

-- Apply swing to time position
function Pattern:apply_swing(time)
  if self.swing == 0 then return time end

  local grid = self.grid_division
  local beat_pos = time / grid
  local beat_idx = math.floor(beat_pos)

  -- Only swing off-beat notes (odd positions)
  if beat_idx % 2 == 1 then
    local swing_amount = self.swing * grid * 0.5
    return time + swing_amount
  end

  return time
end

-- Clear all notes
function Pattern:clear()
  self.notes = {}
end

-- Clone pattern
function Pattern:clone(new_name)
  local copy = Pattern.new(new_name or (self.name .. " (copy)"), self.length_bars)
  copy.grid_division = self.grid_division
  copy.swing = self.swing
  copy.channel = self.channel
  copy.drum_map = Pattern.copy_drum_map(self.drum_map)

  for _, note in ipairs(self.notes) do
    copy:add_note(note.pitch, note.start, note.length, note.vel, note.muted)
  end

  return copy
end

-- Serialize to table (for saving)
function Pattern:serialize()
  return {
    name = self.name,
    length_bars = self.length_bars,
    grid_division = self.grid_division,
    swing = self.swing,
    channel = self.channel,
    drum_map = self.drum_map,
    notes = self.notes,
  }
end

-- Deserialize from table
function Pattern.deserialize(data)
  local p = Pattern.new(data.name, data.length_bars)
  p.grid_division = data.grid_division or 0.25
  p.swing = data.swing or 0
  p.channel = data.channel or 0
  p.drum_map = data.drum_map or Pattern.copy_drum_map(Pattern.DEFAULT_DRUM_MAP)
  p.notes = data.notes or {}
  return p
end

return Pattern
