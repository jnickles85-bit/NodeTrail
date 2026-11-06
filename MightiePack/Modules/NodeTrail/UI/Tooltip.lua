local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local T = {}
ns.Tooltip = T

function T.BuildLines(name)
  local node = ns.HerbData.GetNode(name)
  if not node then return nil end
  local lines = {}
  table.insert(lines, { left = "NodeTrail" })
  local drops, gathers = ns.HerbData.GetDropLines(name)
  if drops then
    for _, d in ipairs(drops) do
      local itemName = ns.HerbData.ITEM_NAMES[d.id] or ("item " .. d.id)
      local right = d.pct .. "%" .. (d.source == "base" and " (base)" or "")
      table.insert(lines, { left = itemName, right = right })
    end
  end
  if gathers and gathers > 0 then
    table.insert(lines, { left = "Your picks: " .. gathers })
  else
    table.insert(lines, { left = "Your picks: none yet" })
  end
  local uses = ns.Recipes:GetUses(node.item)
  if uses and #uses > 0 then
    local display = uses
    if #uses > 4 then
      display = {}
      for i = 1, 4 do
        table.insert(display, uses[i])
      end
      table.insert(display, "+" .. (#uses - 4) .. " more")
    end
    table.insert(lines, { left = "Alchemy: " .. table.concat(display, ", ") })
  elseif NodeTrailDB and NodeTrailDB.recipes and NodeTrailDB.recipes.alchemyScanned == nil then
    table.insert(lines, { left = "Open Alchemy once to list recipe uses" })
  end
  return lines
end

function T:GetHoveredNodeName(tooltip)
  if UnitExists and UnitExists("mouseover") then
    return nil
  end
  local owner = tooltip:GetOwner()
  if owner ~= UIParent and owner ~= WorldFrame and owner ~= nil then
    return nil
  end
  local fs = _G["GameTooltipTextLeft1"]
  local text = fs and fs:GetText()
  if text and ns.HerbData.GetNode(text) then
    return text
  end
  return nil
end

function T:OnShow(tooltip)
  if self.added then return end
  local name = self:GetHoveredNodeName(tooltip)
  if not name then return end
  local lines = T.BuildLines(name)
  if not lines then return end
  self.added = true
  for _, line in ipairs(lines) do
    if line.right then
      tooltip:AddDoubleLine(line.left, line.right, 0.6, 0.8, 1, 1, 1, 1)
    else
      tooltip:AddLine(line.left, 0.6, 0.8, 1)
    end
  end
  tooltip:Show()
end

function T:Enable()
  if self._enabled then return end
  self._enabled = true
  if not GameTooltip or not GameTooltip.HookScript then return end
  GameTooltip:HookScript("OnShow", function(tt)
    local ok, err = pcall(T.OnShow, T, tt)
    if not ok then
      T._error = tostring(err)
    end
  end)
  GameTooltip:HookScript("OnTooltipCleared", function()
    T.added = false
  end)
end
