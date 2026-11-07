local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local T = {}
ns.Tooltip = T

local HEADER = "NodeTrail"
local POLL_INTERVAL = 0.2 -- at most ~5 refresh evaluations per second

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

-- Content is the truth: the header line ("NodeTrail") is what marks our
-- block as intact, so read what the tooltip actually holds — prefer the
-- per-line text API, falling back to the font strings this addon already
-- relies on for the title.
local function lineText(tooltip, i)
  if type(tooltip.GetLine) == "function" then
    local text = tooltip:GetLine(i)
    if text ~= nil then return text end
    return nil
  end
  local fs = _G["GameTooltipTextLeft" .. i]
  if fs and type(fs.GetText) == "function" then
    return fs:GetText()
  end
  return nil
end

local function headerPresent(tooltip)
  local n = tooltip:NumLines()
  for i = 1, n do
    if lineText(tooltip, i) == HEADER then
      return true
    end
  end
  return false
end

-- The block is intact only while our header is still in the tooltip, we
-- last appended it for the current title, and the tooltip still holds at
-- least as many lines as right after that append. A matching title with
-- no header means the client rewrote content through a path we never saw
-- (a C-side SetUnit / SetGameObject) — treat the block as gone, no matter
-- what our own clear wrappers recorded.
local function blockIntact(tooltip, title)
  if T.last == nil or T.last.title ~= title or T.last.after == nil then
    return false
  end
  return tooltip:NumLines() >= T.last.after and headerPresent(tooltip)
end

-- Re-ensure the NodeTrail block for the tooltip's current content. Appends
-- at most one fresh block, and only when it is actually due:
--   * the title is a known herb node, otherwise own nothing;
--   * the block is considered present only if the tooltip still contains
--     our header under the matching title — so a repopulate on ANY path
--     self-heals, and repeated calls with no client writes in between are
--     a no-op, so several hooks on one tooltip never produce duplicate
--     headers.
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
  if blockIntact(tooltip, name) then
    return
  end
  for _, line in ipairs(lines) do
    if line.right then
      tooltip:AddDoubleLine(line.left, line.right, 0.6, 0.8, 1, 1, 1, 1)
    else
      tooltip:AddLine(line.left, 0.6, 0.8, 1)
    end
  end
  self.last = { title = name, after = tooltip:NumLines() }
  self.dirty = false
end

function T:Enable()
  if self._enabled then return end
  self._enabled = true
  self.last = nil
  self.dirty = false
  if not GameTooltip or not GameTooltip.HookScript then return end

  -- Fast path: fires on every populate that goes through the client — the
  -- fresh Show plus the repopulate events. The content is settled by then,
  -- so a single Refresh suffices. Never calls tooltip:Show() itself.
  local function onPopulate(tt)
    local ok, err = pcall(T.Refresh, T, tt)
    if not ok then
      T._error = tostring(err)
    end
  end
  GameTooltip:HookScript("OnShow", onPopulate)

  -- SetUnit / SetItem fire on client builds that expose the events; a
  -- client that lacks one (or the hooking method) loses that fast path
  -- rather than breaking Enable.
  for _, event in ipairs({ "OnTooltipSetUnit", "OnTooltipSetItem" }) do
    local ok, err = pcall(GameTooltip.HookScript, GameTooltip, event, onPopulate)
    if not ok then
      T._error = tostring(err)
    end
  end

  -- Dirty tracking is a hint only: the clears we CAN observe (clear event,
  -- a wrapped clear method) mark content as rewritten, but self-heal never
  -- relies on it — the repopulate that matters bypasses all of these.
  GameTooltip:HookScript("OnTooltipCleared", function()
    T.dirty = true
  end)
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

  -- Backstop clock: a private, visually inert helper frame (a bare Frame
  -- has no texture; Show only subscribes it to OnUpdate ticks).
  -- GameTooltip keeps its own client update behaviour — we never touch its
  -- scripts. The poll evaluates the refresh at most ~5x/second and does no
  -- work at all while the tooltip is hidden. A client without a
  -- visibility API keeps the fast path only.
  if type(GameTooltip.IsShown) == "function" and type(CreateFrame) == "function" then
    local ok, poll = pcall(CreateFrame, "Frame", "NodeTrailTooltipPoll")
    if ok and type(poll) == "table" and type(poll.SetScript) == "function" then
      self.poller = poll
      local accum = 0
      poll:SetScript("OnUpdate", function(_, elapsed)
        if not GameTooltip:IsShown() then
          -- Hidden: stop doing work.
          accum = 0
          return
        end
        accum = accum + (elapsed or POLL_INTERVAL)
        if accum >= POLL_INTERVAL then
          accum = 0
          local ok2, err2 = pcall(T.Refresh, T, GameTooltip)
          if not ok2 then
            T._error = tostring(err2)
          end
        end
      end)
      if type(poll.Show) == "function" then
        poll:Show()
      end
    end
  end
end
