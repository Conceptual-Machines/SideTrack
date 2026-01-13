-- @description Grid Quantization Menu
-- @version 1.1.0
-- @author SideTrack
-- @about
--   Quick access popup menu for grid quantization settings.
--   Assign to a toolbar button or keyboard shortcut for fast grid changes.

local reaper = reaper

-- Grid division values (in fractions of a bar/measure)
local GRID_DIVISIONS = {
  { label = "1 Bar",  value = 1.0 },
  { label = "1/2",    value = 0.5 },
  { label = "1/4",    value = 0.25 },
  { label = "1/8",    value = 0.125 },
  { label = "1/16",   value = 0.0625 },
  { label = "1/32",   value = 0.03125 },
  { label = "1/64",   value = 0.015625 },
}

-- Get current grid division
local function get_current_grid()
  local _, division = reaper.GetSetProjectGrid(0, false)
  return division
end

-- Set grid division
local function set_grid(division)
  reaper.GetSetProjectGrid(0, true, division)
  reaper.UpdateArrange()
end

-- Check if value matches (with tolerance for floating point)
local function values_match(a, b)
  return math.abs(a - b) < 0.0001
end

-- Build menu and action list
local function build_menu()
  local current = get_current_grid()
  local menu_parts = {}
  local actions = {}  -- Parallel list of actions

  -- Standard divisions submenu
  menu_parts[#menu_parts + 1] = ">Standard"
  for _, div in ipairs(GRID_DIVISIONS) do
    local checked = values_match(current, div.value) and "!" or ""
    menu_parts[#menu_parts + 1] = checked .. div.label
    actions[#actions + 1] = { type = "grid", value = div.value }
  end
  menu_parts[#menu_parts + 1] = "<"

  -- Triplet divisions submenu
  menu_parts[#menu_parts + 1] = ">Triplet"
  for _, div in ipairs(GRID_DIVISIONS) do
    local triplet_val = div.value * 2/3
    local checked = values_match(current, triplet_val) and "!" or ""
    menu_parts[#menu_parts + 1] = checked .. div.label .. " T"
    actions[#actions + 1] = { type = "grid", value = triplet_val }
  end
  menu_parts[#menu_parts + 1] = "<"

  -- Dotted divisions submenu
  menu_parts[#menu_parts + 1] = ">Dotted"
  for _, div in ipairs(GRID_DIVISIONS) do
    local dotted_val = div.value * 1.5
    local checked = values_match(current, dotted_val) and "!" or ""
    menu_parts[#menu_parts + 1] = checked .. div.label .. " ."
    actions[#actions + 1] = { type = "grid", value = dotted_val }
  end
  menu_parts[#menu_parts + 1] = "<"

  -- Separator
  menu_parts[#menu_parts + 1] = ""

  -- Snap toggle
  local snap_enabled = reaper.GetToggleCommandState(1157) == 1
  local snap_check = snap_enabled and "!" or ""
  menu_parts[#menu_parts + 1] = snap_check .. "Snap Enabled"
  actions[#actions + 1] = { type = "snap" }

  return table.concat(menu_parts, "|"), actions
end

-- Main
local function main()
  local menu_str, actions = build_menu()

  -- Show menu at mouse position (position tiny window off-screen)
  local x, y = reaper.GetMousePosition()
  gfx.init("", 1, 1, 0, x, y - 1000)
  gfx.x, gfx.y = gfx.screentoclient(x, y)

  local selection = gfx.showmenu(menu_str)
  gfx.quit()

  -- Handle selection
  if selection > 0 and actions[selection] then
    local action = actions[selection]
    if action.type == "grid" then
      set_grid(action.value)
    elseif action.type == "snap" then
      reaper.Main_OnCommand(1157, 0)  -- Toggle snap
    end
  end
end

main()
