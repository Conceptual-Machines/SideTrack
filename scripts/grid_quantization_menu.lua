-- @description Grid Quantization Menu
-- @version 1.0.0
-- @author SideTrack
-- @about
--   Quick access popup menu for grid quantization settings.
--   Assign to a toolbar button or keyboard shortcut for fast grid changes.

local reaper = reaper

-- Grid division values (in quarter notes)
-- REAPER uses: 1 = quarter note, 0.5 = eighth, 0.25 = sixteenth, etc.
local GRID_DIVISIONS = {
  { label = "1 Bar",        value = 4.0,      triplet = 4.0 * 2/3,      dotted = 4.0 * 1.5 },
  { label = "1/2",          value = 2.0,      triplet = 2.0 * 2/3,      dotted = 2.0 * 1.5 },
  { label = "1/4",          value = 1.0,      triplet = 1.0 * 2/3,      dotted = 1.0 * 1.5 },
  { label = "1/8",          value = 0.5,      triplet = 0.5 * 2/3,      dotted = 0.5 * 1.5 },
  { label = "1/16",         value = 0.25,     triplet = 0.25 * 2/3,     dotted = 0.25 * 1.5 },
  { label = "1/32",         value = 0.125,    triplet = 0.125 * 2/3,    dotted = 0.125 * 1.5 },
  { label = "1/64",         value = 0.0625,   triplet = 0.0625 * 2/3,   dotted = 0.0625 * 1.5 },
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

-- Build menu string
local function build_menu()
  local current = get_current_grid()
  local menu_items = {}

  -- Header
  table.insert(menu_items, "#Grid Division|")

  -- Standard divisions
  table.insert(menu_items, ">Standard")
  for _, div in ipairs(GRID_DIVISIONS) do
    local checked = values_match(current, div.value) and "!" or ""
    table.insert(menu_items, checked .. div.label)
  end
  table.insert(menu_items, "<|")

  -- Triplet divisions
  table.insert(menu_items, ">Triplet")
  for _, div in ipairs(GRID_DIVISIONS) do
    local checked = values_match(current, div.triplet) and "!" or ""
    table.insert(menu_items, checked .. div.label .. " T")
  end
  table.insert(menu_items, "<|")

  -- Dotted divisions
  table.insert(menu_items, ">Dotted")
  for _, div in ipairs(GRID_DIVISIONS) do
    local checked = values_match(current, div.dotted) and "!" or ""
    table.insert(menu_items, checked .. div.label .. " .")
  end
  table.insert(menu_items, "<|")

  -- Separator and snap toggle
  table.insert(menu_items, "|")
  local snap_enabled = reaper.GetToggleCommandState(1157) == 1  -- Toggle snap
  local snap_check = snap_enabled and "!" or ""
  table.insert(menu_items, snap_check .. "Snap Enabled")

  return table.concat(menu_items, "|")
end

-- Parse menu selection and apply
local function handle_selection(selection)
  if selection <= 0 then return end

  -- Account for header (item 1)
  local adjusted = selection - 1

  -- Standard submenu: items 2-8 (indices 1-7 after header)
  -- Triplet submenu: items 10-16
  -- Dotted submenu: items 18-24
  -- Snap toggle: item 26

  local num_divisions = #GRID_DIVISIONS

  -- Submenu structure:
  -- 1 = header
  -- 2 = ">Standard" opener
  -- 3-9 = standard divisions (7 items)
  -- 10 = "<" closer + separator
  -- 11 = ">Triplet" opener
  -- 12-18 = triplet divisions
  -- 19 = "<" closer + separator
  -- 20 = ">Dotted" opener
  -- 21-27 = dotted divisions
  -- 28 = "<" closer + separator
  -- 29 = separator
  -- 30 = Snap toggle

  if adjusted >= 2 and adjusted <= 2 + num_divisions - 1 then
    -- Standard division selected
    local idx = adjusted - 2 + 1
    if GRID_DIVISIONS[idx] then
      set_grid(GRID_DIVISIONS[idx].value)
    end
  elseif adjusted >= 2 + num_divisions + 2 and adjusted <= 2 + num_divisions + 2 + num_divisions - 1 then
    -- Triplet division selected
    local idx = adjusted - (2 + num_divisions + 2) + 1
    if GRID_DIVISIONS[idx] then
      set_grid(GRID_DIVISIONS[idx].triplet)
    end
  elseif adjusted >= 2 + 2*num_divisions + 4 and adjusted <= 2 + 2*num_divisions + 4 + num_divisions - 1 then
    -- Dotted division selected
    local idx = adjusted - (2 + 2*num_divisions + 4) + 1
    if GRID_DIVISIONS[idx] then
      set_grid(GRID_DIVISIONS[idx].dotted)
    end
  elseif adjusted == 2 + 3*num_divisions + 7 then
    -- Snap toggle
    reaper.Main_OnCommand(1157, 0)  -- Toggle snap
  end
end

-- Main
local function main()
  local menu_str = build_menu()

  -- Show menu at mouse position (use dock=-1 to hide the gfx window)
  local x, y = reaper.GetMousePosition()
  gfx.init("", 0, 0, -1, x, y)

  local selection = gfx.showmenu(menu_str)
  gfx.quit()

  handle_selection(selection)
end

main()
