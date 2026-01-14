-- Mouse handler utility for SideTrack
-- Handles click vs drag detection, selection rectangles, etc.

local Mouse = {}

-- Drag threshold in pixels
local DRAG_THRESHOLD = 5

-- States
Mouse.STATE_IDLE = "idle"
Mouse.STATE_PENDING = "pending"      -- Mouse down, waiting to see if drag
Mouse.STATE_SELECTING = "selecting"  -- Dragging selection rectangle
Mouse.STATE_DRAGGING = "dragging"    -- Dragging something (velocity, note move, etc.)

-- Click areas
Mouse.AREA_NONE = "none"
Mouse.AREA_GRID = "grid"
Mouse.AREA_HEADER = "header"
Mouse.AREA_LABELS = "labels"
Mouse.AREA_MODIFIERS = "modifiers"

-- Click types
Mouse.CLICK_LEFT = 0
Mouse.CLICK_RIGHT = 1
Mouse.CLICK_MIDDLE = 2

-- Current state
Mouse.state = Mouse.STATE_IDLE

-- Mouse positions
Mouse.down_x = 0
Mouse.down_y = 0
Mouse.current_x = 0
Mouse.current_y = 0

-- Grid cell where mouse went down
Mouse.down_row = -1
Mouse.down_col = -1

-- Click metadata
Mouse.click_area = Mouse.AREA_NONE
Mouse.click_type = Mouse.CLICK_LEFT
Mouse.modifiers = {
  ctrl = false,
  shift = false,
  alt = false,
}

-- Selection rectangle (in screen coords)
Mouse.selection = {
  x1 = 0, y1 = 0,
  x2 = 0, y2 = 0,
}

-- Drag context (what we're dragging, original value, etc.)
Mouse.drag_context = nil

-- Called when mouse button pressed
-- opts: {row, col, area, click_type, ctrl, shift, alt}
function Mouse.on_down(x, y, opts)
  opts = opts or {}
  Mouse.state = Mouse.STATE_PENDING
  Mouse.down_x = x
  Mouse.down_y = y
  Mouse.current_x = x
  Mouse.current_y = y
  Mouse.down_row = opts.row or -1
  Mouse.down_col = opts.col or -1
  Mouse.click_area = opts.area or Mouse.AREA_NONE
  Mouse.click_type = opts.click_type or Mouse.CLICK_LEFT
  Mouse.modifiers.ctrl = opts.ctrl or false
  Mouse.modifiers.shift = opts.shift or false
  Mouse.modifiers.alt = opts.alt or false
  Mouse.drag_context = nil
end

-- Called every frame while mouse is down
-- Returns true if we crossed the drag threshold
function Mouse.on_drag(x, y)
  Mouse.current_x = x
  Mouse.current_y = y

  if Mouse.state == Mouse.STATE_PENDING then
    local dx = math.abs(x - Mouse.down_x)
    local dy = math.abs(y - Mouse.down_y)

    if dx > DRAG_THRESHOLD or dy > DRAG_THRESHOLD then
      -- Crossed threshold - start selecting
      Mouse.state = Mouse.STATE_SELECTING
      Mouse.selection.x1 = Mouse.down_x
      Mouse.selection.y1 = Mouse.down_y
      Mouse.selection.x2 = x
      Mouse.selection.y2 = y
      return true
    end
  elseif Mouse.state == Mouse.STATE_SELECTING then
    -- Update selection rectangle
    Mouse.selection.x2 = x
    Mouse.selection.y2 = y
  end

  return false
end

-- Called when mouse button released
-- Returns the final state before reset
function Mouse.on_up(x, y)
  local final_state = Mouse.state
  Mouse.current_x = x
  Mouse.current_y = y

  -- Finalize selection bounds
  if Mouse.state == Mouse.STATE_SELECTING then
    Mouse.selection.x2 = x
    Mouse.selection.y2 = y
  end

  return final_state
end

-- Reset to idle state
function Mouse.reset()
  Mouse.state = Mouse.STATE_IDLE
  Mouse.down_row = -1
  Mouse.down_col = -1
  Mouse.click_area = Mouse.AREA_NONE
  Mouse.click_type = Mouse.CLICK_LEFT
  Mouse.modifiers.ctrl = false
  Mouse.modifiers.shift = false
  Mouse.modifiers.alt = false
  Mouse.drag_context = nil
end

-- Check if a point is inside the selection rectangle
function Mouse.point_in_selection(x, y)
  local x1 = math.min(Mouse.selection.x1, Mouse.selection.x2)
  local x2 = math.max(Mouse.selection.x1, Mouse.selection.x2)
  local y1 = math.min(Mouse.selection.y1, Mouse.selection.y2)
  local y2 = math.max(Mouse.selection.y1, Mouse.selection.y2)

  return x >= x1 and x <= x2 and y >= y1 and y <= y2
end

-- Check if a rectangle overlaps the selection rectangle
function Mouse.rect_in_selection(rx1, ry1, rx2, ry2)
  local x1 = math.min(Mouse.selection.x1, Mouse.selection.x2)
  local x2 = math.max(Mouse.selection.x1, Mouse.selection.x2)
  local y1 = math.min(Mouse.selection.y1, Mouse.selection.y2)
  local y2 = math.max(Mouse.selection.y1, Mouse.selection.y2)

  -- Check for overlap
  return rx1 < x2 and rx2 > x1 and ry1 < y2 and ry2 > y1
end

-- Get normalized selection bounds (x1 < x2, y1 < y2)
function Mouse.get_selection_bounds()
  return {
    x1 = math.min(Mouse.selection.x1, Mouse.selection.x2),
    y1 = math.min(Mouse.selection.y1, Mouse.selection.y2),
    x2 = math.max(Mouse.selection.x1, Mouse.selection.x2),
    y2 = math.max(Mouse.selection.y1, Mouse.selection.y2),
  }
end

-- Was it a click (no drag)?
function Mouse.was_click()
  return Mouse.state == Mouse.STATE_PENDING
end

-- Is currently selecting?
function Mouse.is_selecting()
  return Mouse.state == Mouse.STATE_SELECTING
end

-- Is currently dragging?
function Mouse.is_dragging()
  return Mouse.state == Mouse.STATE_DRAGGING
end

-- Start a drag operation with context
function Mouse.start_drag(context)
  Mouse.state = Mouse.STATE_DRAGGING
  Mouse.drag_context = context
end

return Mouse
