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
  self.sink(string.format("[%s] [%s] [%s] %s\n",
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
