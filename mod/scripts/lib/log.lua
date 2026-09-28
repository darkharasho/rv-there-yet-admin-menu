local M = {}
local LEVELS = { DEBUG = 10, INFO = 20, WARN = 30, ERROR = 40 }

local Logger = {}
Logger.__index = Logger

function Logger:set_level(name)
  self.level = LEVELS[tostring(name):upper()] or LEVELS.INFO
end

local function emit(self, level, msg)
  if LEVELS[level] < self.level then return end
  local ok, stamp = pcall(os.date, "%H:%M:%S")
  -- The default sink is UE4SS's overridden print, which can throw once
  -- the log handle is torn down. An unguarded throw here would escape
  -- through ue.lua's warn() -- called AFTER the adapter's own pcall has
  -- returned -- into a HUD hook or key-bind callback on the game thread.
  -- A logger is the last module allowed to crash the session.
  pcall(self.sink, string.format("[%s] [%s] [%s] %s",
    ok and stamp or "--:--:--", self.name, level, tostring(msg)))
end

function Logger:debug(m) emit(self, "DEBUG", m) end
function Logger:info(m)  emit(self, "INFO",  m) end
function Logger:warn(m)  emit(self, "WARN",  m) end
function Logger:error(m) emit(self, "ERROR", m) end

function M.new(opts)
  opts = opts or {}
  local self = setmetatable({
    name = opts.name or "RVAdminMenu",
    sink = opts.sink or print,
  }, Logger)
  self:set_level(opts.level)
  return self
end

return M
