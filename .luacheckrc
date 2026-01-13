-- Luacheck configuration for REAPER scripts

-- Global objects provided by REAPER
globals = {
    "reaper",
    "gfx",
    "package",  -- Need write access for package.path
}

-- Read-only globals
read_globals = {
    "string",
    "table",
    "math",
    "pairs",
    "ipairs",
    "tonumber",
    "tostring",
    "type",
    "print",
    "pcall",
    "require",
    "error",
    "assert",
}

-- Ignore warnings
ignore = {
    "212",  -- Unused argument
    "213",  -- Unused loop variable
    "611",  -- Line contains only whitespace
    "612",  -- Line contains trailing whitespace
    "614",  -- Trailing whitespace in comment
}

-- Max line length
max_line_length = 120

-- Allow self
self = false
