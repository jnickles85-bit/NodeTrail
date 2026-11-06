local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local Rc = {}
ns.Recipes = Rc

function ns.GetRecipeDB()
  if type(NodeTrailDB) ~= "table" then
    ns.GetDB()
  end
  NodeTrailDB.recipes = NodeTrailDB.recipes or {}
  NodeTrailDB.recipes.alchemy = NodeTrailDB.recipes.alchemy or {}
  return NodeTrailDB.recipes
end

function Rc:IsAlchemyOpen()
  local line = GetTradeSkillLine and GetTradeSkillLine()
  local alch = GetSpellInfo and GetSpellInfo(2259) or "Alchemy"
  return line ~= nil and (line == alch or line == "Alchemy")
end

function Rc:Scan()
  if not self:IsAlchemyOpen() then
    return false
  end
  local newMap = {}
  local numSkills = GetNumTradeSkills and GetNumTradeSkills() or 0
  for i = 1, numSkills do
    local name, skillType = GetTradeSkillInfo(i)
    if name and skillType ~= "header" then
      local numReagents = GetTradeSkillNumReagents and GetTradeSkillNumReagents(i) or 0
      for r = 1, numReagents do
        local link = GetTradeSkillReagentItemLink(i, r)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then
          newMap[id] = newMap[id] or {}
          table.insert(newMap[id], name)
        end
      end
    end
  end
  local finalMap = {}
  for id, names in pairs(newMap) do
    local unique = {}
    local seen = {}
    for _, n in ipairs(names) do
      if not seen[n] then
        seen[n] = true
        table.insert(unique, n)
      end
    end
    table.sort(unique)
    finalMap[id] = unique
  end
  local db = ns.GetRecipeDB()
  db.alchemy = finalMap
  NodeTrailDB.recipes.alchemyScanned = time()
  return true
end

function Rc:GetUses(itemID)
  return ns.GetRecipeDB().alchemy[itemID]
end

function Rc:Enable()
  if self._enabled then return end
  self._enabled = true
  local frame = CreateFrame("Frame")
  frame:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
      local ok, err = pcall(Rc.Scan, Rc)
      if not ok then
        Rc._error = tostring(err)
      end
    end
  end)
  pcall(function() frame:RegisterEvent("TRADE_SKILL_SHOW") end)
  pcall(function() frame:RegisterEvent("TRADE_SKILL_UPDATE") end)
end
