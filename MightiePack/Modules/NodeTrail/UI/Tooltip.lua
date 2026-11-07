local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local T = {}
ns.Tooltip = T

local HEADER = "NodeTrail"
local POLL_INTERVAL = 0.2 -- at most ~5 refresh evaluations per second

-- "Open Alchemy once to list recipe uses" is only truthful while a scan
-- is actually POSSIBLE. On a client with no trade-skill API at all (both
-- the legacy globals and C_TradeSkillUI absent — the Forever 16001
-- report: the hint sat up forever with no way to clear it), printing it
-- promises a step the player can never complete, so the line is dropped;
-- `/nt status` carries the explanation instead (t_0d5badc3).
local function recipeAPIAvailable()
  if type(ns.Recipes) ~= "table" or type(ns.Recipes.APIInfo) ~= "function" then
    return false
  end
  local ok, info = pcall(ns.Recipes.APIInfo, ns.Recipes)
  if not ok or type(info) ~= "table" then
    return false
  end
  return info.available == true
end

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
  elseif NodeTrailDB and NodeTrailDB.recipes and NodeTrailDB.recipes.alchemyScanned == nil
    and recipeAPIAvailable() then
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
-- The client sizes the tooltip's backdrop and anchors the frame at Show,
-- THEN fires the OnShow hook, and it does not redo either while we are
-- appending late — that is why the in-game block sat on no background
-- and ran off the right/bottom edge. A late append therefore pulls the
-- client through its OWN show path again: the show path re-runs the
-- padding/backdrop sizing, which is the re-layout we can rely on.
-- `Layout()` is kept only as an optional extra (some clients expose it);
-- it is never the sole mechanism, so a client without it still re-sizes
-- — a method guarded by `type(...) == "function"` is a coin flip, and
-- this design does not take it.
--
-- Re-entrancy: the show path fires the OnShow hook, which re-enters
-- Refresh. Two gates keep that safe: the content guard above refuses a
-- second append (the block is intact by then), and the `_relaying` lock
-- drops a nested re-layout — no hook loop, no duplicate block. A hostile
-- show that wipes and re-pays content is absorbed too: the hook re-enters
-- Refresh, re-appends once (the block was genuinely gone), and its
-- re-layout is dropped by the lock.
--
-- After the re-layout, the frame is clamped ONCE into UIParent using
-- MEASURED screen coordinates (the client's own edge getters when
-- present), and the shift is applied through the first anchor — never on
-- a clock, never fighting the client's later positioning.
--
-- API contract (real client, Frame) — the model the code and the spec
-- share, not a guess:
--   GetPoint(index)             -> point, relativeTo, relativePoint,
--                                  offsetX, offsetY                  (5 values)
--   SetPoint(point, relativeTo, relativePoint, x, y)
--   GetLeft()/GetRight()/GetTop()/GetBottom()
--                               -> screen-space edges, y-up, bottom-left
--                                  origin (the tooltip's parent is
--                                  UIParent, which spans the screen)
-- GetPoint is NOT a 7-return and is not parsed in any other order; the
-- spec pins that shape on the client model (the contract checks at the
-- top of the layout section) so a green run stays evidence.
local MARGIN = 10 -- clamp inset; kept in sync with NT_MARGIN in tests/tooltip_refresh_spec.lua

-- Screen-space rect {left, bottom, right, top} (y-up, bottom-left origin)
-- for the frame, or nil when it cannot be determined on this client.
-- Measured edges (the client's own getters) are the reliable source; only
-- when they are absent do we derive the rect from the first anchor plus
-- the frame size, parsing GetPoint with the documented 5-tuple.
local function screenRect(g)
  if type(g.GetLeft) == "function" and type(g.GetRight) == "function"
    and type(g.GetTop) == "function" and type(g.GetBottom) == "function" then
    local l, r, b, t = g:GetLeft(), g:GetRight(), g:GetBottom(), g:GetTop()
    if type(l) == "number" and type(r) == "number"
      and type(b) == "number" and type(t) == "number" then
      return { left = l, right = r, bottom = b, top = t }
    end
  end
  if type(g.GetPoint) ~= "function" then return nil end
  -- Documented order: point, relativeTo, relativePoint, offsetX, offsetY.
  local point, relativeTo, relativePoint, xOfs, yOfs = g:GetPoint(1)
  if type(point) ~= "string" or type(relativeTo) ~= "table"
    or type(relativePoint) ~= "string"
    or type(xOfs) ~= "number" or type(yOfs) ~= "number" then
    return nil
  end
  local w = type(g.GetWidth) == "function" and g:GetWidth() or nil
  local h = type(g.GetHeight) == "function" and g:GetHeight() or nil
  if type(w) ~= "number" or type(h) ~= "number" then return nil end
  local relW = type(relativeTo.GetWidth) == "function" and relativeTo:GetWidth() or nil
  local relH = type(relativeTo.GetHeight) == "function" and relativeTo:GetHeight() or nil
  if type(relW) ~= "number" or type(relH) ~= "number" then
    if type(UIParent) == "table" and type(UIParent.GetWidth) == "function"
      and type(UIParent.GetHeight) == "function" then
      relW, relH = UIParent:GetWidth(), UIParent:GetHeight()
    else
      return nil
    end
  end
  local ox = relativePoint:find("RIGHT") and relW
    or (relativePoint:find("CENTER") and relW * 0.5 or 0)
  local oy = relativePoint:find("TOP") and relH
    or (relativePoint:find("CENTER") and relH * 0.5 or 0)
  local cx, cy = ox + xOfs, oy + yOfs
  return {
    left = cx - (point:find("RIGHT") and w or (point:find("CENTER") and w * 0.5 or 0)),
    right = cx + (point:find("LEFT") and w or (point:find("CENTER") and w * 0.5 or 0)),
    bottom = cy - (point:find("TOP") and h or (point:find("CENTER") and h * 0.5 or 0)),
    top = cy + (point:find("BOTTOM") and h or (point:find("CENTER") and h * 0.5 or 0)),
  }
end

-- Shift the frame by (dx, dy) through its first anchor — the real
-- SetPoint signature, with the anchor fields read back through the real
-- GetPoint 5-tuple. Returns nil (and touches nothing) when the anchor
-- does not come back in that shape: a made-up shape must not be written
-- back as a "clamp".
local function shiftAnchor(g, dx, dy)
  if type(g.GetPoint) ~= "function" or type(g.SetPoint) ~= "function" then
    return nil
  end
  local point, relativeTo, relativePoint, xOfs, yOfs = g:GetPoint(1)
  if type(point) ~= "string" or type(relativeTo) ~= "table"
    or type(relativePoint) ~= "string"
    or type(xOfs) ~= "number" or type(yOfs) ~= "number" then
    return nil
  end
  g:SetPoint(point, relativeTo, relativePoint, xOfs + dx, yOfs + dy)
  return true
end

-- Clamp the frame into the UIParent margin box once. Returns false when
-- the rect cannot be determined or the anchor is not writeable.
local function clampIntoScreen(g, sw, sh)
  local rect = screenRect(g)
  if not rect then return false end
  local dx = 0
  if rect.left < MARGIN then dx = dx + (MARGIN - rect.left) end
  if rect.right > sw - MARGIN then dx = dx - (rect.right - (sw - MARGIN)) end
  local dy = 0
  if rect.bottom < MARGIN then dy = dy + (MARGIN - rect.bottom) end
  if rect.top > sh - MARGIN then dy = dy - (rect.top - (sh - MARGIN)) end
  if dx == 0 and dy == 0 then
    return true
  end
  return shiftAnchor(g, dx, dy) == true
end

function T:Relayout(tooltip)
  if T._relaying then
    return
  end
  T._relaying = true
  local ok, err = pcall(function()
    -- 1) The client's own show path: it re-runs the padding/backdrop
    --    sizing that was frozen before our lines existed. If the show
    --    re-fires the OnShow hook, onPopulate re-enters Refresh: the
    --    content guard refuses a second append (the block is intact),
    --    and a nested re-layout is dropped by the lock above — no loop.
    if type(tooltip.Show) == "function" then
      tooltip:Show()
    end
    -- 2) Optional extra: clients that expose an explicit re-layout get
    --    it too. Never the sole mechanism — step 1 must already cover
    --    a client without it.
    if type(tooltip.Layout) == "function" then
      tooltip:Layout()
    end
    -- 3) Clamp once into the screen (10px margin) from MEASURED edges.
    --    This runs on append, not on a clock; the client keeps ownership
    --    of any subsequent repositioning.
    if type(UIParent) == "table" and type(UIParent.GetWidth) == "function"
      and type(UIParent.GetHeight) == "function" then
      local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
      clampIntoScreen(tooltip, sw, sh)
    end
  end)
  T._relaying = false
  if not ok then
    T._error = tostring(err)
  end
end

-- /nt ttdiag — the in-client evidence channel for tooltip layout. Prints
-- only what is live: line count + frame size, every anchor in the REAL
-- GetPoint order (point, relativeTo, relativePoint, offsetX, offsetY),
-- the measured screen edges, the screen-vs-rect verdict, and whether the
-- current block was added after the client's layout. Cheap: a handful of
-- API calls, no loops beyond GetNumPoints.
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
        last.shown and "post-Show (appended after client layout; relayout ran)"
          or "pre-Show (client layout ran after the append)")
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
  local w = type(gt.GetWidth) == "function" and gt:GetWidth() or nil
  local h = type(gt.GetHeight) == "function" and gt:GetHeight() or nil
  say(("NumLines=%s W=%s H=%s"):format(
    tostring(n),
    type(w) == "number" and string.format("%.0f", w) or "?",
    type(h) == "number" and string.format("%.0f", h) or "?"))
  local npts = type(gt.GetNumPoints) == "function" and gt:GetNumPoints() or 0
  if npts > 0 then
    for i = 1, npts do
      -- Real GetPoint contract: point, relativeTo, relativePoint, x, y.
      local point, relativeTo, relativePoint, xOfs, yOfs = gt:GetPoint(i)
      local relName = "?"
      if type(relativeTo) == "table" then
        if type(relativeTo.GetName) == "function" then
          local okn, nm = pcall(relativeTo.GetName, relativeTo)
          if okn and type(nm) == "string" then
            relName = nm
          end
        end
        if relName == "?" then relName = "frame" end
      end
      say(("point %d: %s of %s %s xOfs=%s yOfs=%s"):format(
        i,
        type(point) == "string" and point or "?",
        relName,
        type(relativePoint) == "string" and relativePoint or "?",
        type(xOfs) == "number" and string.format("%.0f", xOfs) or tostring(xOfs),
        type(yOfs) == "number" and string.format("%.0f", yOfs) or tostring(yOfs)))
    end
  else
    say("points: none (frame unanchored)")
  end
  -- Measured screen edges (the client's own getters when present).
  if type(gt.GetLeft) == "function" and type(gt.GetRight) == "function"
    and type(gt.GetTop) == "function" and type(gt.GetBottom) == "function" then
    local l, r, t, b = gt:GetLeft(), gt:GetRight(), gt:GetTop(), gt:GetBottom()
    if type(l) == "number" and type(r) == "number" and type(t) == "number" and type(b) == "number" then
      say(("measured: left=%.0f right=%.0f top=%.0f bottom=%.0f"):format(l, r, t, b))
    else
      say("measured: edge getters present but returned non-numbers")
    end
  end
  if type(UIParent) == "table" and type(UIParent.GetWidth) == "function"
    and type(UIParent.GetHeight) == "function" then
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local rect = screenRect(gt)
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
    -- Pull the client through its own show path once (that re-runs the
    -- padding/backdrop sizing), then clamp the frame into the screen;
    -- the client keeps ownership of any subsequent repositioning.
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
