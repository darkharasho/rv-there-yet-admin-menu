-- Builds the v0.1 menu tree for menu.lua. Engine-free: it only calls the
-- `actions` object it is given (actions.lua), so it is testable with a fake.
-- Static pages are plain tables; pages that depend on live game state
-- (players, loaded checkpoints, the item list) are `build` functions that
-- menu.lua calls when the submenu opens.
local M = {}

local function sub(id, label, page)
  return { id = id, label = label, kind = "submenu", target = page }
end

local function dyn(id, label, build)
  return { id = id, label = label, kind = "submenu", build = build }
end

local function act(id, label, target, destructive)
  return { id = id, label = label, kind = "action", target = target, destructive = destructive }
end

-- 0..15 checkpoint rows for a cheat-manager action.
local function numbered_page(id, title, action, destructive)
  local items = {}
  for n = 0, 15 do
    items[#items + 1] = act(action, "Checkpoint " .. n, n, destructive)
  end
  return { id = id, title = title, items = items }
end

-- Case-insensitive substring match on every space-separated word.
local function matches(name, query)
  local lname = name:lower()
  for word in query:gmatch("%S+") do
    if not lname:find(word, 1, true) then return false end
  end
  return true
end

local function item_page(actions, all, query, first)
  local per = actions.ITEMS_PER_PAGE or 15
  local list = all
  if query ~= "" then
    list = {}
    for _, it in ipairs(all) do
      if matches(it.name, query) then list[#list + 1] = it end
    end
  end
  local items = {}
  local last = math.min(first + per - 1, #list)
  for i = first, last do
    items[#items + 1] = act("spawn", list[i].name, list[i])
  end
  if last < #list then
    items[#items + 1] = dyn("spawn_next_" .. last, "Next page",
      function() return item_page(actions, all, query, last + 1) end)
  end
  local title
  if #list == 0 then
    title = "Spawn item: no matches"
  else
    title = string.format("Spawn item (%d-%d of %d)", first, last, #list)
  end
  return {
    id = "spawn_page",
    title = title,
    items = items,
    query = query,
    search = function(q) return item_page(actions, all, q, 1) end,
  }
end

local function player_page(actions, ref)
  return {
    id = "player",
    title = ref.name,
    items = {
      act("p_tp_to_me", "Teleport to me", ref),
      act("p_tp_me_to", "Teleport me to them", ref),
      act("p_send_rv", "Send to RV", ref),
      act("p_revive", "Revive", ref),
      act("p_heal", "Heal", ref),
      act("p_kill", "Kill", ref, true),
      act("p_free", "Free from grab", ref),
      act("p_unseat", "Force unseat", ref),
      { id = "p_god", label = "God mode", kind = "toggle", target = ref,
        value = function() return actions:player_god(ref) end },
      { id = "p_speed", label = "Speed x2", kind = "toggle", target = ref,
        value = function() return actions:player_speed(ref) end },
    },
  }
end

function M.build(actions)
  local function host_gate(builder)
    return function()
      if not actions:is_host() then return nil, "Host only" end
      return builder()
    end
  end

  local checkpoints_all = host_gate(function()
    local cps = actions:checkpoints()
    if #cps == 0 then return nil, "no checkpoints loaded" end
    local items = {}
    for _, c in ipairs(cps) do
      items[#items + 1] = act("tp_all_cp", "Checkpoint " .. c.index, c.index)
    end
    return { id = "tp_all_cp_page", title = "Everyone to checkpoint", items = items }
  end)

  local teleport = {
    id = "teleport",
    title = "Teleport",
    items = {
      act("tp_me_rv", "Me to RV"),
      act("tp_all_rv", "Everyone to RV"),
      sub("tp_me_cp_page", "Me to checkpoint",
        numbered_page("tp_me_cp_page", "Me to checkpoint", "tp_me_cp")),
      dyn("tp_all_cp_menu", "Everyone to checkpoint", checkpoints_all),
      sub("restart_cp_page", "Restart at checkpoint",
        numbered_page("restart_cp_page", "Restart at checkpoint", "restart_cp", true)),
      act("bring_all", "Bring everyone to me"),
      act("bring_rv", "Bring RV to me"),
    },
  }

  local players = dyn("players", "Players", host_gate(function()
    local list = actions:players()
    if #list == 0 then return nil, "no players found" end
    local items = {}
    for _, p in ipairs(list) do
      local ref = p.ref
      items[#items + 1] = dyn("player:" .. ref.name, ref.name,
        function() return player_page(actions, ref) end)
    end
    return { id = "players_page", title = "Players", items = items }
  end))

  local everyone = dyn("everyone", "Everyone", host_gate(function()
    return {
      id = "everyone_page",
      title = "Everyone",
      items = {
        act("all_revive", "Revive all"),
        act("all_heal", "Heal all"),
        act("all_free", "Free all from grabs"),
        { id = "all_god", label = "God mode all", kind = "toggle",
          value = function() return actions.god_all end },
      },
    }
  end))

  local me = {
    id = "me",
    title = "Me",
    items = {
      { id = "me_god", label = "God mode", kind = "toggle",
        value = function() return actions:me_god() end },
      act("me_revive", "Revive me"),
      act("me_heal", "Heal me"),
      act("me_unseat", "Unseat me"),
      act("me_epipens", "Give 5 epipens"),
    },
  }

  local spawn = dyn("spawn_menu", "Spawn item", function()
    local list, why = actions:item_list()
    if not list then return nil, why end
    return item_page(actions, list, "", 1)
  end)

  return {
    id = "root",
    title = "RV Admin",
    items = {
      sub("teleport", "Teleport", teleport),
      players,
      everyone,
      sub("me", "Me", me),
      spawn,
    },
  }
end

return M
