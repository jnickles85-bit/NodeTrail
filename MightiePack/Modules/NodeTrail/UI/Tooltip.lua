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
--
-- BOTH sources are only accepted as a plain string. `GameTooltip:GetLine`
-- is not a verified method on this client (Forever 16001); if it exists but
-- returns a different shape (a table of segments, a colour-wrapped object —
-- anything non-string), treating it as line text would make `headerPresent`
-- never match, so `Refresh` would conclude the block is gone and append
-- another one every poll tick (~5/s). A non-string from `GetLine` is simply
-- discarded and the font string is used instead; the font-string path is
-- type-checked the same way.
local function isStringLine(x)
  return type(x) == "string"
end

local function lineText(tooltip, i)
  local text
  if type(tooltip.GetLine) == "function" then
    local candidate = tooltip:GetLine(i)
    if isStringLine(candidate) then
      text = candidate
    end
  end
  if text == nil then
    local fs = _G["GameTooltipTextLeft" .. i]
    if fs and type(fs.GetText) == "function" then
      local t = fs:GetText()
      if isStringLine(t) then
        text = t
      end
    end
  end
  return text
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

-- ── Layout (backdrop + on-screen clamp) ────────────────────────────────
-- The client sizes the tooltip's backdrop and anchors the frame when it
-- populates/shows an item, and it does not redo either while we are
-- appending late — that is why the in-game block sat on no background
-- and ran off the right/bottom edge. Late appends therefore have to
-- re-layout themselves: `Layout()` (the client's own re-layout) re-sizes
-- the backdrop, and we clamp the anchor once so the frame fits
-- UIParent. We do not own subsequent client repositioning — the clamp
-- happens on append, not on a clock. Re-entrancy: a Layout that re-fires
-- a hook (re-entering Refresh) is dropped by the lock below; the
-- content guard above (since 14c1c30) already stops duplicate appends.

local MARGIN = 10 -- clamp inset; kept in sync with NT_MARGIN in tests/tooltip_refresh_spec.lua

-- Screen-space rect {left, bottom, right, top} (y-up, bottom-left origin)
-- of the frame's first anchor point, or nil when unanchored/unsized.
local function screenRect(g, relW, relH)
  if type(g.GetPoint) ~= "function" then return nil end
  -- GetPoint returns (relX, relY, xOfs, yOfs, relativeTo, point1, point2)
  local _, _, xOfs, yOfs, relativeTo, point1, point2 = g:GetPoint(1)
  if xOfs == nil or yOfs == nil or type(point1) ~= "string" or type(point2) ~= "string" then
    return nil
  end
  local w = type(g.GetWidth) == "function" and g:GetWidth() or nil
  local h = type(g.GetHeight) == "function" and g:GetHeight() or nil
  if type(w) ~= "number" or type(h) ~= "number" then return nil end
  local ox = point2:find("RIGHT") and relW or (point2:find("CENTER") and relW * 0.5 or 0)
  local oy = point2:find("TOP") and relH or (point2:find("CENTER") and relH * 0.5 or 0)
  local cx, cy = ox + xOfs, oy + yOfs
  return {
    left = cx - (point1:find("RIGHT") and w or (point1:find("CENTER") and w * 0.5 or 0)),
    right = cx + (point1:find("LEFT") and w or (point1:find("CENTER") and w * 0.5 or 0)),
    bottom = cy - (point1:find("TOP") and h or (point1:find("CENTER") and h * 0.5 or 0)),
    top = cy + (point1:find("BOTTOM") and h or (point1:find("CENTER") and h * 0.5 or 0)),
  }
end

function T:Relayout(tooltip)
  if T._relaying then
    return
  end
  T._relaying = true
  local ok, err = pcall(function()
    if type(tooltip.Layout) == "function" then
      tooltip:Layout()
    end
    if type(UIParent) == "table" and type(UIParent.GetWidth) == "function"
      and type(UIParent.GetHeight) == "function" then
      local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
      local rect = screenRect(tooltip, sw, sh)
      if rect and type(tooltip.SetPoint) == "function" then
        local dx = 0
        if rect.left < MARGIN then dx = dx + (MARGIN - rect.left) end
        if rect.right > sw - MARGIN then dx = dx - (rect.right - (sw - MARGIN)) end
        local dy = 0
        if rect.bottom < MARGIN then dy = dy + (MARGIN - rect.bottom) end
        if rect.top > sh - MARGIN then dy = dy - (rect.top - (sh - MARGIN)) end
        if dx ~= 0 or dy ~= 0 then
          local _, _, xOfs, yOfs, relativeTo, point1, point2 = tooltip:GetPoint(1)
          tooltip:SetPoint(point1, relativeTo, point2, xOfs + dx, yOfs + dy)
        end
      end
    end
  end)
  T._relaying = false
  if not ok then
    T._error = tostring(err)
  end
end

-- /nt ttdiag — the in-client evidence channel for tooltip layout. Prints
-- only what is live: NumLines and frame size, every anchor point, the
-- computed screen rect vs UIParent, and whether the current block was
-- added pre- or post-Show. Cheap: a few API calls, no loops beyond
-- GetNumPoints.
function T:Diag()
  local function say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail ttdiag: " .. msg)
  end
  local gt = GameTooltip
  if type(gt) ~= "table" then
    say("GameTooltip unavailable")
    return
  end
  local last = T.last
  local function blockState()
    if last then
      return ("block: title=%s after=%d added=%s"):format(
        tostring(last.title),
        last.after or -1,
        last.shown and "post-Show (late path, relayout ran)" or "pre-Show (populate path)")
    end
    return "block: none (no append recorded for the current title)"
  end
  if T._error then
    say("error: " .. tostring(T._error))
  end
  local shown = type(gt.IsShown) == "function" and gt:IsShown() or false
  if not shown then
    say("tooltip hidden; " .. blockState())
    return
  end
  local n = type(gt.NumLines) == "function" and gt:NumLines() or -1
  local w = type(gt.GetWidth) == "function" and gt:GetWidth()
  local h = type(gt.GetHeight) == "function" and gt:GetHeight()
  say(("NumLines=%d W=%s H=%s"):format(
    n,
    type(w) == "number" and string.format("%.0f", w) or "?",
    type(h) == "number" and string.format("%.0f", h) or "?"))
  local npts = type(gt.GetNumPoints) == "function" and gt:GetNumPoints() or 0
  for i = 1, npts do
    local xOfs, yOfs, relTo, p1, p2 = select(3, gt:GetPoint(i))
    say(("point %d: %s of %s (%s) xOfs=%s yOfs=%s"):format(
      i,
      p1 or "?",
      type(relTo) == "table" and (type(relTo.GetName) == "function" and tostring(relTo:GetName()) or "frame") or "?",
      p2 or "?",
      tostring(xOfs),
      tostring(yOfs)))
  end
  if type(UIParent) == "table" and type(UIParent.GetWidth) == "function"
    and type(UIParent.GetHeight) == "function" then
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local rect = screenRect(gt, sw, sh)
    if rect then
      local outside = rect.left < 0 or rect.right > sw or rect.bottom < 0 or rect.top > sh
      local offMargin = rect.left < MARGIN or rect.right > sw - MARGIN
        or rect.bottom < MARGIN or rect.top > sh - MARGIN
      say(("screen %.0fx%.0f rect L=%.1f B=%.1f R=%.1f T=%.1f (%s, %s)"):format(
        sw, sh,
        rect.left, rect.bottom, rect.right, rect.top,
        outside and "OFF-SCREEN" or "on screen",
        offMargin and "OUTSIDE MARGIN" or "within margin"))
    else
      say(("screen %.0fx%.0f rect = unanchored or unsized frame"):format(sw, sh))
    end
  end
  say(blockState())
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
  local shown = type(tooltip.IsShown) == "function" and tooltip:IsShown() or false
  self.last = { title = name, after = tooltip:NumLines(), shown = shown }
  self.dirty = false
  if shown then
    -- Late append: the client sized and anchored the tooltip BEFORE our
    -- lines existed, so its layout decisions don't account for them.
    -- Re-layout once (backdrop grows to cover us) and clamp the frame
    -- into the screen; the client keeps ownership of any subsequent
    -- repositioning.
    self:Relayout(tooltip)
  end
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
