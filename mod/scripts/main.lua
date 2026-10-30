-- RVAdminMenu entry point. UE4SS runs <Mod>/scripts/main.lua with no
-- package.path for our modules, so work out our own directory the same way
-- MoreRVers does and prepend it.
local MOD_NAME, MOD_VERSION = "RVAdminMenu", "0.2.12"

local dir = debug.getinfo(1, "S").source:match("^@?(.*)[/\\][^/\\]*$")
if dir then
  package.path = dir .. "/?.lua;" .. package.path
end

local ok, err = pcall(function()
  local config = require("lib.config")
  local log = require("lib.log")
  local ue = require("lib.ue")
  local app = require("lib.app")

  local logger = log.new({ name = MOD_NAME })

  -- config.ini sits one level above scripts/, at the mod root.
  local ini = {}
  local f = dir and io.open(dir .. "/../config.ini", "r")
  if f then
    ini = config.parse_ini(f:read("a"))
    f:close()
  else
    logger:warn("config.ini not found; using defaults")
  end
  local cfg = config.resolve(ini, logger)
  logger:set_level(cfg.log_level)

  local adapter = ue.new(logger)
  local instance = app.new({ ue = adapter, logger = logger, cfg = cfg })
  instance:bind_keys()
  logger:info(string.format("v%s loaded; hotkey %s", MOD_VERSION, cfg.hotkey))
  -- One line of what the UE4SS globals look like from here, for diagnosing
  -- the overlay without another round trip.
  local types = {}
  for _, name in ipairs({ "StaticFindObject", "StaticConstructObject", "FName", "FText", "LoopAsync", "ExecuteInGameThread" }) do
    local okg, v = pcall(function() return _G[name] end)
    types[#types + 1] = string.format("%s=%s/%s", name, okg and type(v) or "err", type(rawget(_G, name)))
  end
  logger:info("globals: " .. table.concat(types, " "))
end)
if not ok then
  print(string.format("[%s] failed to start: %s", MOD_NAME, tostring(err)))
end
