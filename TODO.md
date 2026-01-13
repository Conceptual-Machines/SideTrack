# SideTrack Development Notes

## Current Status
- Drum editor working with pattern data model
- Print to track functionality complete
- Preview playback working

## Next Steps

### 1. Move main script to root (like SideFX)
- Move `scripts/sketchpad.lua` → `SideTrack.lua` in root
- Update package.path accordingly
- Keep utility scripts in `scripts/`

### 2. Piano Roll View
- Horizontal note bars
- Piano keyboard on left
- Zoom/scroll
- Note drag to move/resize

### 3. Step Sequencer View
- Fixed step grid
- Toggle cells per pitch
- Good for melodic patterns

### 4. Additional Features
- Pattern library/presets
- Save/load patterns to file
- Multiple patterns with switching
- Copy/paste patterns
- Swing control UI

## File Structure (planned)
```
SideTrack/
  SideTrack.lua          # Main entry point
  lib/
    pattern.lua          # Pattern data model
    midi_output.lua      # Print to track
    ui/
      drum_editor.lua    # Drum grid view
      piano_roll.lua     # Piano roll view
      step_seq.lua       # Step sequencer view
  scripts/
    velocity_curve.lua   # Standalone tool
    note_repeat.lua      # Standalone tool
    grid_quantization_menu.lua
```
