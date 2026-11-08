local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local H = {}
ns.HerbData = H

-- Secondary percentages are rough placeholders, not researched Forever data.
-- Personal data replaces them as the sample grows.
-- Forever rare mats to be added.

H.NODES = {
  ["Peacebloom"] = { item = 2447, drops = { [2447] = 100 } },
  ["Silverleaf"] = { item = 765, drops = { [765] = 100 } },
  ["Earthroot"] = { item = 2449, drops = { [2449] = 100 } },
  ["Mageroyal"] = { item = 785, drops = { [785] = 100, [2452] = 10 } },
  ["Briarthorn"] = { item = 2450, drops = { [2450] = 100, [2452] = 10 } },
  ["Stranglekelp"] = { item = 3820, drops = { [3820] = 100 } },
  ["Bruiseweed"] = { item = 2453, drops = { [2453] = 100 } },
  ["Wild Steelbloom"] = { item = 3355, drops = { [3355] = 100 } },
  ["Grave Moss"] = { item = 3369, drops = { [3369] = 100 } },
  ["Kingsblood"] = { item = 3356, drops = { [3356] = 100 } },
  ["Liferoot"] = { item = 3357, drops = { [3357] = 100 } },
  ["Fadeleaf"] = { item = 3818, drops = { [3818] = 100 } },
  ["Goldthorn"] = { item = 3821, drops = { [3821] = 100 } },
  ["Khadgar's Whisker"] = { item = 3358, drops = { [3358] = 100 } },
  ["Wintersbite"] = { item = 3819, drops = { [3819] = 100 } },
  ["Firebloom"] = { item = 4625, drops = { [4625] = 100 } },
  ["Purple Lotus"] = { item = 8831, drops = { [8831] = 100, [8153] = 5 } },
  ["Arthas' Tears"] = { item = 8836, drops = { [8836] = 100 } },
  ["Sungrass"] = { item = 8838, drops = { [8838] = 100 } },
  ["Blindweed"] = { item = 8839, drops = { [8839] = 100 } },
  ["Ghost Mushroom"] = { item = 8845, drops = { [8845] = 100 } },
  ["Gromsblood"] = { item = 8846, drops = { [8846] = 100 } },
  ["Golden Sansam"] = { item = 13464, drops = { [13464] = 100 } },
  ["Dreamfoil"] = { item = 13463, drops = { [13463] = 100 } },
  ["Mountain Silversage"] = { item = 13465, drops = { [13465] = 100 } },
  ["Plaguebloom"] = { item = 13466, drops = { [13466] = 100 } },
  ["Icecap"] = { item = 13467, drops = { [13467] = 100 } },
  ["Black Lotus"] = { item = 13468, drops = { [13468] = 100 } },
}

H.ITEM_NAMES = {
  [2447] = "Peacebloom",
  [765] = "Silverleaf",
  [2449] = "Earthroot",
  [785] = "Mageroyal",
  [2452] = "Swiftthistle",
  [2450] = "Briarthorn",
  [3820] = "Stranglekelp",
  [2453] = "Bruiseweed",
  [3355] = "Wild Steelbloom",
  [3369] = "Grave Moss",
  [3356] = "Kingsblood",
  [3357] = "Liferoot",
  [3818] = "Fadeleaf",
  [3821] = "Goldthorn",
  [3358] = "Khadgar's Whisker",
  [3819] = "Wintersbite",
  [4625] = "Firebloom",
  [8831] = "Purple Lotus",
  [8153] = "Wildvine",
  [8836] = "Arthas' Tears",
  [8838] = "Sungrass",
  [8839] = "Blindweed",
  [8845] = "Ghost Mushroom",
  [8846] = "Gromsblood",
  [13464] = "Golden Sansam",
  [13463] = "Dreamfoil",
  [13465] = "Mountain Silversage",
  [13466] = "Plaguebloom",
  [13467] = "Icecap",
  [13468] = "Black Lotus",
}

function H.GetNode(name)
  if not name then return nil end
  return H.NODES[name]
end

-- ── item labels (t_04c983cc) ────────────────────────────────────────────────
-- Mightie's panel showed `item 249399  4%` — a drop row that printed the bare
-- id where a name belongs. The id was real; the LABEL was the bug. Resolution
-- order:
--   1. our own table (the 29 herb ids — offline, always right for herbs),
--   2. GetItemInfo(id), the client's own answer,
--   3. `unknown item <id>` — an honest label that also keeps the row
--      identifiable in a report. Never a bare number passing as a name.
-- The state is recorded for /nt ttdiag (NameProbeLines below): "answered" vs
-- "answered nothing" is the question the operator needs answered.
local function isSecret(v)
  if type(issecretvalue) ~= "function" then
    return false
  end
  local ok, s = pcall(issecretvalue, v)
  return ok and s == true
end

H._diag = H._diag or {}

-- Ask the client what item id N is called. Returns name, why — `why` always
-- says which answer this was, so a nil name is never mistaken for a name.
function H.ClientItemName(id)
  if type(GetItemInfo) ~= "function" then
    return nil, "GetItemInfo is not a function on this client"
  end
  local ok, n = pcall(GetItemInfo, id)
  if not ok then
    return nil, "GetItemInfo raised"
  end
  if isSecret(n) then
    return nil, "GetItemInfo answered a secret string"
  end
  if type(n) ~= "string" or n == "" then
    return nil, "GetItemInfo answered nothing"
  end
  return n, nil
end

function H.ItemLabel(idOrRow)
  local id = idOrRow
  if type(idOrRow) == "table" then
    id = idOrRow.id
  end
  id = tonumber(id)
  if id ~= nil and H.ITEM_NAMES[id] then
    return H.ITEM_NAMES[id]
  end
  if id ~= nil then
    local name = H.ClientItemName(id)
    if name then
      return name
    end
    return "unknown item " .. tostring(id)
  end
  return "unknown item"
end

H.PERSONAL_MIN = 10

function H.GetPersonalStats(primaryItem)
  local db = ns.GetHerbDB()
  local gathers = 0
  local perItem = {}
  if db and db.maps then
    for _, mapData in pairs(db.maps) do
      for _, rec in ipairs(mapData) do
        local isGather = false
        if rec.items then
          for _, it in ipairs(rec.items) do
            if it.id == primaryItem then
              isGather = true
              break
            end
          end
        end
        if isGather then
          gathers = gathers + 1
          local counted = {}
          if rec.items then
            for _, it in ipairs(rec.items) do
              if it.id and not counted[it.id] then
                counted[it.id] = true
                perItem[it.id] = (perItem[it.id] or 0) + 1
              end
            end
          end
        end
      end
    end
  end
  return gathers, perItem
end

function H.GetDropLines(name)
  local node = H.GetNode(name)
  if not node then return nil end
  local gathers, perItem = H.GetPersonalStats(node.item)
  local list = {}
  local seen = {}
  local function add(id, pct, source)
    if not seen[id] then
      seen[id] = true
      table.insert(list, { id = id, pct = pct, source = source })
    end
  end
  for id, basePct in pairs(node.drops) do
    if gathers >= H.PERSONAL_MIN then
      local p = perItem[id] and math.floor(perItem[id] / gathers * 100 + 0.5) or 0
      add(id, p, "you")
    else
      add(id, basePct, "base")
    end
  end
  for id, count in pairs(perItem) do
    if not node.drops[id] then
      if gathers >= H.PERSONAL_MIN then
        local p = math.floor(count / gathers * 100 + 0.5)
        add(id, p, "you")
      else
        local p = math.floor(count / gathers * 100 + 0.5)
        add(id, p, "you")
      end
    end
  end
  table.sort(list, function(a, b)
    if a.pct ~= b.pct then return a.pct > b.pct end
    return a.id < b.id
  end)
  return list, gathers
end

-- ── id -> name evidence (t_04c983cc) ────────────────────────────────────────
-- Every drop id the panel can print that OUR table does not name, resolved the
-- way the panel resolves it: `item id: 249399 -> GetItemInfo answered nothing ·
-- shown as "unknown item 249399"`. A player reporting "this row says unknown
-- item" and an operator reading /nt ttdiag are then looking at the same ids.
-- Ids come from the researched drop tables AND from this account's recorded
-- gathers (a herb drops rare mats we never listed). Output is sorted by id, so
-- the same store always prints the same lines.
local function unresolvedDropIDs()
  local seen, order = {}, {}
  local function add(id)
    id = tonumber(id)
    if id ~= nil and H.ITEM_NAMES[id] == nil and not seen[id] then
      seen[id] = true
      order[#order + 1] = id
    end
  end
  for _, node in pairs(H.NODES) do
    if type(node.drops) == "table" then
      for id in pairs(node.drops) do
        add(id)
      end
    end
  end
  local db = ns.GetHerbDB()
  if type(db) == "table" and type(db.maps) == "table" then
    for _, mapData in pairs(db.maps) do
      if type(mapData) == "table" then
        for _, rec in ipairs(mapData) do
          if type(rec) == "table" and type(rec.items) == "table" then
            for _, it in ipairs(rec.items) do
              if type(it) == "table" then
                add(it.id)
              end
            end
          end
        end
      end
    end
  end
  table.sort(order)
  return order
end

function H.NameProbeLines()
  local ids = unresolvedDropIDs()
  local out = {}
  if #ids == 0 then
    out[1] = "item names: every drop id we can print is named by our own table or the client"
    return out
  end
  out[1] = ("item names: %d drop id(s) are not in our herb table"):format(#ids)
  for _, id in ipairs(ids) do
    local name, why = H.ClientItemName(id)
    if name then
      out[#out + 1] = ('item id: %d -> "%s" (GetItemInfo) · the panel uses that name'):format(id, name)
    else
      out[#out + 1] = ('item id: %d -> %s · the panel prints "unknown item %d"'):format(id, why, id)
    end
  end
  return out
end

return H
