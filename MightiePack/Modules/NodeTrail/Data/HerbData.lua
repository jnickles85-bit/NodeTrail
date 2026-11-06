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
