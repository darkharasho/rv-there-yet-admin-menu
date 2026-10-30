local M = {}

-- Spellings confirmed against UE4SS's own `Key` table (docs/game-objects.md
-- section 10): note INS and DEL, not INSERT/DELETE. ue.lua:bind_key still
-- refuses a name the Key table lacks, so a future rename surfaces as a
-- warning rather than a hotkey that silently never fires.
M.KEY_NAMES = {}
for i = 1, 12 do
  M.KEY_NAMES["F" .. i] = true
end
for _, name in ipairs({ "INS", "HOME", "END", "DEL", "PAGE_UP", "PAGE_DOWN" }) do
  M.KEY_NAMES[name] = true
end

local DEFAULTS = {
  hotkey = "F3",
  log_level = "INFO",
  confirm_destructive = true,
  heal_amount = 100,
  mouse = true,
}

local TRUE_VALUES = { ["1"] = true, ["true"] = true, ["yes"] = true, ["on"] = true }
local FALSE_VALUES = { ["0"] = true, ["false"] = true, ["no"] = true, ["off"] = true }
local LOG_LEVEL_NAMES = { DEBUG = true, INFO = true, WARN = true, ERROR = true }

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

function M.parse_ini(text)
  local t = {}
  for line in (text or ""):gmatch("[^\r\n]+") do
    local trimmed = trim(line)
    if trimmed ~= "" and not trimmed:match("^[;#]") and not trimmed:match("^%[.*%]$") then
      local key, value = trimmed:match("^([^=]+)=(.*)$")
      if key then
        t[trim(key):lower()] = trim(value)
      end
    end
  end
  return t
end

local function resolve_hotkey(ini, logger)
  local raw = ini.hotkey
  if raw == nil then
    return DEFAULTS.hotkey, true
  end
  local upper = tostring(raw):upper()
  if M.KEY_NAMES[upper] then
    return upper, true
  end
  logger:warn(string.format(
    "Invalid hotkey '%s' in config.ini; falling back to default '%s'",
    tostring(raw), DEFAULTS.hotkey))
  return DEFAULTS.hotkey, false
end

local function resolve_log_level(ini, logger)
  local raw = ini.loglevel
  if raw == nil then
    return DEFAULTS.log_level
  end
  local upper = tostring(raw):upper()
  if not LOG_LEVEL_NAMES[upper] then
    logger:warn(string.format(
      "Invalid LogLevel '%s' in config.ini; falling back to default '%s'",
      tostring(raw), DEFAULTS.log_level))
    return DEFAULTS.log_level
  end
  return upper
end

local function resolve_bool(ini, key, ini_name, default, logger)
  local raw = ini[key]
  if raw == nil then
    return default
  end
  local lowered = tostring(raw):lower()
  if TRUE_VALUES[lowered] then
    return true
  elseif FALSE_VALUES[lowered] then
    return false
  end
  logger:warn(string.format(
    "Invalid %s '%s' in config.ini; falling back to default '%s'",
    ini_name, tostring(raw), tostring(default)))
  return default
end

local function resolve_heal_amount(ini, logger)
  local raw = ini.healamount
  if raw == nil then
    return DEFAULTS.heal_amount
  end
  local n = tonumber(raw)
  if n == nil then
    logger:warn(string.format(
      "Invalid HealAmount '%s' in config.ini; falling back to default '%s'",
      tostring(raw), tostring(DEFAULTS.heal_amount)))
    return DEFAULTS.heal_amount
  end
  n = math.floor(n)
  if n < 1 then n = 1 end
  if n > 1000 then n = 1000 end
  return n
end

-- resolve's contract is to produce a fully validated cfg: every field is
-- a value the rest of the mod can use as-is, never a passed-through bad
-- one. A missing logger degrades to a no-op rather than erroring -- this
-- runs during mod load inside someone's live session.
local NULL_LOGGER = {
  debug = function() end,
  info = function() end,
  warn = function() end,
  error = function() end,
}

function M.resolve(ini, logger)
  ini = ini or {}
  if type(logger) ~= "table" or type(logger.warn) ~= "function" then
    logger = NULL_LOGGER
  end
  local hotkey, hotkey_valid = resolve_hotkey(ini, logger)
  return {
    hotkey = hotkey,
    hotkey_valid = hotkey_valid,
    log_level = resolve_log_level(ini, logger),
    confirm_destructive = resolve_bool(ini, "confirmdestructive", "ConfirmDestructive", DEFAULTS.confirm_destructive, logger),
    heal_amount = resolve_heal_amount(ini, logger),
    mouse = resolve_bool(ini, "mouse", "Mouse", DEFAULTS.mouse, logger),
  }
end

return M
