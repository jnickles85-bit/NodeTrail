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

-- Re-ensure the NodeTrail block for the tooltip's current content. Appends at
-- most one fresh block, and only when it is due:
--   * title is a known herb node, otherwise own nothing;
--   * we have not appended for this title yet, or the client rewrote the
--     tooltip content since our last append (self-heal after a repopulate).
-- Safe to call as many times as the client's hooks fire: with no client
-- writes in between, the block is already present and the call is a no-op,
-- so several hooks on one tooltip never produce duplicate headers.
function T:Refresh(tooltip)
  local name = self:GetHoveredNodeName(tooltip)
  if not name then
    -- Not a herb tooltip (unknown object, unit tooltip, some other window):
    -- whatever is in there is the client's, own nothing.
    self.last = nil
    return
  end
  local lines = T.BuildLines(name)
  if not lines then
    self.last = nil
    return
  end
  if self.last and self.last.title == name and not self.dirty then
    return
  end
  for _, line in ipairs(lines) do
    if line.right then
      tooltip:AddDoubleLine(line.left, line.right, 0.6, 0.8, 1, 1, 1, 1)
    else
      tooltip:AddLine(line.left, 0.6, 0.8, 1)
    end
  end
  self.last = { title = name }
  self.dirty = false
end

-- Deferred flush. The client may repopulate a visible tooltip (ClearLines +
-- new content) without firing OnTooltipCleared and without calling Show
-- again; while the tooltip is shown, the client ticks OnUpdate on visible
-- frames, so that clock is where a stale state gets re-evaluated.
function T:Flush(tip)
  if not self.dirty or not tip then return end
  self:Refresh(tip)
end

function T:Enable()
  if self._enabled then return end
  self._enabled = true
  self.last = nil
  self.dirty = false
  if not GameTooltip or not GameTooltip.HookScript then return end
  GameTooltip:HookScript("OnShow", function(tt)
    local ok, err = pcall(T.Refresh, T, tt)
    if not ok then
      T._error = tostring(err)
    end
  end)
  GameTooltip:HookScript("OnTooltipCleared", function()
    T.dirty = true
  end)
  -- A repopulate (SetUnit/SetGameObject-style refresh) clears through the
  -- tooltip's clear method WITHOUT firing OnTooltipCleared — treat any such
  -- clear as an invalidation so the next Refresh/Flush re-appends the block.
  for _, name in ipairs({ "ClearLines", "Clear" }) do
    local orig = GameTooltip[name]
    if type(orig) == "function" and not GameTooltip["__ntWrapped" .. name] then
      GameTooltip[name] = function(self, ...)
        local r1, r2, r3, r4 = orig(self, ...)
        T.dirty = true
        return r1, r2, r3, r4
      end
      GameTooltip["__ntWrapped" .. name] = true
    end
  end
  if type(GameTooltip.SetScript) == "function" then
    GameTooltip:SetScript("OnUpdate", function(self)
      local ok, err = pcall(T.Flush, T, self)
      if not ok then
        T._error = tostring(err)
      end
    end)
  end
end
