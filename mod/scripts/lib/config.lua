local M = {}

M.KEY_NAMES = {}
for i = 1, 12 do
  M.KEY_NAMES["F" .. i] = true
end
for _, name in ipairs({ "INSERT", "HOME", "END", "DELETE", "PAGE_UP", "PAGE_DOWN" }) do
  M.KEY_NAMES[name] = true
end

local DEFAULTS = {
  hotkey = "F3",
  log_level = "INFO",
  confirm_destructive = true,
  heal_amount = 100,
}

local TRUE_VALUES = { ["1"] = true, ["true"] = true, ["yes"] = true, ["on"] = true }
local FALSE_VALUES = { ["0"] = true, ["false"] = true, ["no"] = true, ["off"] = true }

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

local function resolve_log_level(ini)
  local raw = ini.loglevel
  if raw == nil then
    return DEFAULTS.log_level
  end
  return tostring(raw):upper()
end

local function resolve_bool(ini, key, default)
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
  return default
end

local function resolve_heal_amount(ini)
  local raw = ini.healamount
  if raw == nil then
    return DEFAULTS.heal_amount
  end
  local n = tonumber(raw)
  if n == nil then
    return DEFAULTS.heal_amount
  end
  n = math.floor(n)
  if n < 1 then n = 1 end
  if n > 1000 then n = 1000 end
  return n
end

function M.resolve(ini, logger)
  ini = ini or {}
  local hotkey, hotkey_valid = resolve_hotkey(ini, logger)
  return {
    hotkey = hotkey,
    hotkey_valid = hotkey_valid,
    log_level = resolve_log_level(ini),
    confirm_destructive = resolve_bool(ini, "confirmdestructive", DEFAULTS.confirm_destructive),
    heal_amount = resolve_heal_amount(ini),
  }
end

return M
