-- NodeTrail — the herb tooltip path (t_f4ff9ea6).
--
-- This module no longer writes anything into Blizzard's tooltip. It answers one
-- question for the poller — "is the hovered thing one of OUR herb nodes?" — and
-- then hands the block to `ns.TooltipPanel`, which owns a frame of its own.
--
-- The append path is gone on purpose, and so are the three workarounds built on
-- top of it (widen the frame, measure-and-size the frame, wrap our lines to the
-- client's width). All three lost the same race: this client sizes the
-- tooltip's backdrop at SHOW time and re-derives it on every subsequent show, so
-- anything we did to the frame was reset — or, worse, the backdrop stopped
-- covering our lines while our text stayed on the raw map. Nothing that writes
-- into GameTooltip is kept here, because nothing that writes into GameTooltip
-- can be made to hold.
--
-- What remains is read-only: GetOwner, the line font strings' text and font, and
-- the frame's geometry. No HookScript, no SetScript, no AddLine, no SetWidth, no
-- Show on the tooltip — the panel is ours from creation to hide.
local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local T = {}
ns.Tooltip = T

-- At most ~5 refresh evaluations per second. The panel is redrawn from this
-- tick; nothing else drives it.
local POLL_INTERVAL = 0.2

-- "Open Alchemy once to list recipe uses" is only truthful while a scan is
-- actually POSSIBLE. On a client with no trade-skill API at all (both the
-- legacy globals and C_TradeSkillUI absent — the Forever 16001 report: the hint
-- sat up forever with no way to clear it), printing it promises a step the
-- player can never complete, so the line is dropped; `/nt status` carries the
-- explanation instead (t_0d5badc3).
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

--- The block's content, as data. Rows are { left = <name>, right = <value> } —
--- two columns, exactly like the client's own double lines. No header line: the
--- block opens with the node name (the left column of the node's own drop row).
function T.BuildLines(name)
  local node = ns.HerbData.GetNode(name)
  if not node then return nil end
  local lines = {}
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
    -- A scan that already ran (the Alchemy window was open, its recipes were
    -- read) but found no reagent slots is INCOMPLETE: re-promising "open
    -- Alchemy once" promises a step that was already taken, so say what
    -- actually happened instead (t_81da8886).
    local d = (ns.Recipes and type(ns.Recipes._diag) == "table") and ns.Recipes._diag or nil
    if d and d.gated == "no-reagents" then
      table.insert(lines, { left = "Alchemy scan found no reagents — none saved" })
    else
      table.insert(lines, { left = "Open Alchemy once to list recipe uses" })
    end
  end
  return lines
end

--- Is the hovered object one of our herb nodes? Reads only: the owner test and
--- the client's first line of text. A client whose tooltip object lacks
--- GetOwner (or a caller passing no tooltip at all) is not a herb hover —
--- answer "no" instead of raising.
function T:GetHoveredNodeName(tooltip)
  if type(tooltip) ~= "table" or type(tooltip.GetOwner) ~= "function" then
    return nil
  end
  if UnitExists and UnitExists("mouseover") then
    return nil
  end
  local owner = tooltip:GetOwner()
  if owner ~= UIParent and owner ~= WorldFrame and owner ~= nil then
    return nil
  end
  local fs = _G["GameTooltipTextLeft1"]
  local text = fs and fs.GetText and fs:GetText()
  if text and ns.HerbData.GetNode(text) then
    return text
  end
  return nil
end

-- ── refresh decision ring ────────────────────────────────────────────────
-- The in-client flicker report ("the block appears, then goes away super
-- fast") cannot be diagnosed from a screenshot: what matters is who evaluated
-- the tooltip, what it found, and whether the panel was touched. The last eight
-- decisions are kept and printed by /nt ttdiag AFTER the fact.
local RING_MAX = 8
local RING = {}
local evalCount = 0

--- The sequence number is taken when an evaluation STARTS, and the entry is
--- stored when it finishes: the operator has to read the outer evaluation
--- first.
local function nextSeq()
  evalCount = evalCount + 1
  return evalCount
end

local function ringPush(entry)
  RING[#RING + 1] = entry
  while #RING > RING_MAX do
    table.remove(RING, 1)
  end
end

function T.RingEntries()
  local out = {}
  for i = 1, #RING do
    out[i] = RING[i]
  end
  table.sort(out, function(a, b)
    return (a.n or 0) < (b.n or 0)
  end)
  return out
end

function T:Ring() -- compat alias, returns the same table
  return RING
end

-- ── the one writer: our own panel ─────────────────────────────────────────
local function panelModule()
  local panel = ns.TooltipPanel
  if type(panel) ~= "table" or type(panel.Update) ~= "function" then
    return nil
  end
  return panel
end

--- Evaluate the tooltip and bring the panel in line with it. This is the ONLY
--- caller of the panel, and it never touches the tooltip: the tooltip is read
--- for the hovered name and its rect, and nothing else.
function T:Refresh(tooltip, source)
  source = source or "poll"
  local entry = {
    n = nextSeq(),
    source = source,
    when = type(GetTime) == "function" and GetTime() or nil,
  }
  local panel = panelModule()
  local name = self:GetHoveredNodeName(tooltip)
  entry.name = name
  if not name then
    -- Not a herb tooltip (unknown object, unit tooltip, some other window):
    -- whatever is in there is the client's, and our panel must not linger.
    if type(panel) == "table" then
      panel:Hide("not a herb tooltip")
    end
    entry.panelShown = false
    entry.skip = "not a herb tooltip"
    ringPush(entry)
    return
  end
  local lines = T.BuildLines(name)
  if not lines then
    if type(panel) == "table" then
      panel:Hide("no lines for this node")
    end
    entry.panelShown = false
    entry.skip = "no lines for this node"
    ringPush(entry)
    return
  end
  if panel == nil then
    entry.skip = "panel module not loaded (UI/TooltipPanel.lua)"
    ringPush(entry)
    return
  end
  local info = panel:Update(lines, tooltip)
  entry.panelShown = type(info) == "table" and info.shown or false
  entry.rows = type(info) == "table" and info.rows or nil
  entry.width = type(info) == "table" and info.width or nil
  entry.widest = type(info) == "table" and info.widest or nil
  entry.skip = (type(info) == "table" and info.skip)
    or ("panel shows " .. tostring(entry.rows or "?") .. " row(s)")
  ringPush(entry)
end

-- ── the poller ────────────────────────────────────────────────────────────
--- One poll step, callable directly (the specs drive it; the addon's private
--- frame calls it on a clock). While the tooltip is hidden the panel is hidden
--- and no evaluation is spent; while it is shown the panel is rebuilt from the
--- hovered node's lines.
function T:Poll(tooltip)
  tooltip = tooltip or GameTooltip
  if type(tooltip) ~= "table" then
    return nil
  end
  local shown = false
  if type(tooltip.IsShown) == "function" then
    local ok, value = pcall(tooltip.IsShown, tooltip)
    shown = ok and value == true
  end
  local panel = panelModule()
  if not shown then
    -- The tooltip went away: the panel goes with it. Nothing else to do, and
    -- no ring entry — a hidden tooltip is not an evaluation.
    if type(panel) == "table" and type(panel.IsShown) == "function" and panel:IsShown() then
      panel:Hide("tooltip hidden")
      T._hiddenHides = (T._hiddenHides or 0) + 1
    end
    return false
  end
  self:Refresh(tooltip, "poll")
  return true
end

-- ── /nt ttdiag ─────────────────────────────────────────────────────────────
-- The in-client evidence channel. It prints, in this order: the refresh ring
-- (who evaluated the tooltip and what was decided), the PANEL's own rect /
-- width budget / widest line, and then what the tooltip itself holds — line
-- count, anchors, measured edges and the screen verdict. Cheap (a handful of
-- pcall-guarded reads) and safe on a client missing most of the API.
function T:Diag()
  local function say(msg)
    local line = "NodeTrail ttdiag: " .. tostring(msg)
    if type(DEFAULT_CHAT_FRAME) == "table" and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
      local ok = pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, line)
      if ok then
        return
      end
    end
    pcall(print, line)
  end

  local function px(v)
    if type(v) == "number" then
      return string.format("%.0f", v)
    end
    return "absent"
  end

  -- 1) The ring goes first: it is the evidence even when the tooltip is closed
  --    by the time /nt ttdiag is typed.
  local ring = T.RingEntries()
  if type(ring) ~= "table" or #ring == 0 then
    say("refresh ring: empty (no evaluation recorded yet)")
  else
    say(("refresh ring: last %d evaluation(s), oldest first"):format(#ring))
    for i = 1, #ring do
      local e = ring[i] or {}
      local function flag(v)
        if v == nil then
          return "-"
        end
        return v and "yes" or "no"
      end
      say(("eval #%s src=%s name=%s panel=%s rows=%s width=%s widest=%s — %s"):format(
        tostring(e.n or "?"), tostring(e.source or "?"), tostring(e.name or "-"),
        flag(e.panelShown), tostring(e.rows or "-"), px(e.width), px(e.widest),
        tostring(e.skip or "")))
    end
  end

  -- 2) The panel: its rect, the width budget it computed against, whether it
  --    is on screen, and the widest of OUR lines. These are the numbers the
  --    next report has to quote.
  local panel = ns.TooltipPanel
  if type(panel) == "table" and type(panel.Diag) == "function" then
    local okP, d = pcall(panel.Diag, panel)
    if not okP or type(d) ~= "table" then
      say("panel: diag raised — " .. tostring(d))
    elseif not d.created then
      say("panel: not created yet (no herb has been hovered since login)")
    else
      say(("panel: %s rows=%s rect L=%s B=%s R=%s T=%s (%.0fx%.0f local)"):format(
        d.shown and "SHOWN" or ("hidden — " .. tostring(d.hideReason or "?")),
        tostring(d.rows), px(d.left), px(d.bottom), px(d.right), px(d.top),
        tonumber(d.width) or 0, tonumber(d.height) or 0))
      say(("panel: width budget=%s (45%% of the screen) widest of our lines=%s%s placement=%s%s"):format(
        px(d.cap), px(d.widest),
        type(d.widestText) == "string" and (" \"" .. d.widestText .. "\"") or "",
        tostring(d.placement or "?"), (d.clampedX or d.clampedY) and " (clamped into the screen)" or ""))
      say(("panel: font=%s applied=%s backdrop=%s"):format(
        tostring(d.font or "absent"), d.fontApplied and "yes" or "no",
        tostring(d.backdrop or "?")))
      if type(d.width) == "number" and type(d.needWidth) == "number" then
        -- The verdict compares the panel against an INDEPENDENT measurement
        -- (the meter, at the adopted font), not against the GetStringWidth that
        -- produced the width. Both figures are printed so a mismatch is visible.
        local how
        if type(d.widestMeasured) == "number" then
          how = ("text %s + padding %s = %s, measured independently with %s"):format(
            px(d.widestMeasured), px(2 * (d.padX or 0)), px(d.needWidth), tostring(d.font or "?"))
        else
          how = ("no independent measurement on this client; rows report %s"):format(px(d.widest))
        end
        say(("panel: covers its widest line=%s (panel %s vs %s; drawn rows report %s)"):format(
          d.covers and "yes" or "NO", px(d.width), how, px(d.widest)))
      end
    end
  else
    say("panel: module not loaded (UI/TooltipPanel.lua)")
  end

  -- 3) What the tooltip itself holds. Read-only, every read pcall-guarded.
  local gt = GameTooltip
  local function blockState()
    if type(panel) == "table" and type(panel.TextLines) == "function" then
      local okT, lines = pcall(panel.TextLines, panel)
      if okT and type(lines) == "table" and #lines > 0 then
        return ("block: %d row(s) in the panel (nothing is appended to the tooltip)"):format(#lines)
      end
    end
    return "block: none (the panel carries the herb block; the tooltip only holds the client's lines)"
  end
  if type(gt) ~= "table" then
    say("GameTooltip unavailable")
    return
  end
  local function readNum(method)
    local f = gt[method]
    if type(f) ~= "function" then
      return nil
    end
    local ok, value = pcall(f, gt)
    if ok and type(value) == "number" then
      return value
    end
    return nil
  end
  local shown = false
  if type(gt.IsShown) == "function" then
    local ok, value = pcall(gt.IsShown, gt)
    shown = ok and value == true
  end
  if not shown then
    say("tooltip hidden; " .. blockState())
    return
  end
  local n = readNum("NumLines")
  local w = readNum("GetWidth")
  local h = readNum("GetHeight")
  say(("NumLines=%s W=%s H=%s"):format(
    n and tostring(n) or "?",
    w and string.format("%.0f", w) or "?",
    h and string.format("%.0f", h) or "?"))
  local npts = readNum("GetNumPoints") or 0
  if npts > 0 and type(gt.GetPoint) == "function" then
    for i = 1, npts do
      -- Real GetPoint contract: point, relativeTo, relativePoint, x, y.
      local okP, point, relativeTo, relativePoint, xOfs, yOfs = pcall(gt.GetPoint, gt, i)
      if not okP then
        say(("point %d: GetPoint error"):format(i))
      else
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
    end
  else
    say("points: none (frame unanchored)")
  end
  if type(gt.GetLeft) == "function" and type(gt.GetRight) == "function"
    and type(gt.GetTop) == "function" and type(gt.GetBottom) == "function" then
    local okE, l = pcall(gt.GetLeft, gt)
    local r, t, b
    if okE then
      local okR, rr = pcall(gt.GetRight, gt)
      local okT, tt = pcall(gt.GetTop, gt)
      local okB, bb = pcall(gt.GetBottom, gt)
      if okR then r = rr end
      if okT then t = tt end
      if okB then b = bb end
    end
    if type(l) == "number" and type(r) == "number" and type(t) == "number" and type(b) == "number" then
      say(("measured: left=%.0f right=%.0f top=%.0f bottom=%.0f"):format(l, r, t, b))
    else
      say("measured: edge getters present but returned non-numbers")
    end
  end
  if type(UIParent) == "table" and type(UIParent.GetWidth) == "function"
    and type(UIParent.GetHeight) == "function" then
    local okS, sw, sh = pcall(function()
      return UIParent:GetWidth(), UIParent:GetHeight()
    end)
    if okS and type(sw) == "number" and type(sh) == "number" then
      say(("screen %.0fx%.0f"):format(sw, sh))
    else
      say("screen: UIParent size unavailable")
    end
  else
    say("screen: UIParent absent")
  end
  if T._error then
    say("error: " .. tostring(T._error))
  end
  say(blockState())
end

--- Enable the poller. There is nothing to hook: the panel is driven by this
--- clock alone, and the tooltip is never written to, never hooked and never
--- shown. A client without GameTooltip:IsShown cannot drive the panel at all,
--- and says so instead of half-working.
function T:Enable()
  if self._enabled then return end
  self._enabled = true
  if type(GameTooltip) ~= "table" then
    self._noPoll = "GameTooltip is not available on this client"
    return
  end
  if type(GameTooltip.IsShown) ~= "function" then
    self._noPoll = "GameTooltip:IsShown is not available on this client — the panel cannot be driven"
    return
  end
  if type(CreateFrame) ~= "function" then
    self._noPoll = "CreateFrame is not available on this client — no poll clock"
    return
  end
  local ok, poll = pcall(CreateFrame, "Frame", "NodeTrailTooltipPoll")
  if not ok or type(poll) ~= "table" or type(poll.SetScript) ~= "function" then
    self._noPoll = "CreateFrame refused the poll frame"
    return
  end
  self.poller = poll
  local accum = 0
  poll:SetScript("OnUpdate", function(_, elapsed)
    accum = accum + (elapsed or POLL_INTERVAL)
    if accum < POLL_INTERVAL then
      return
    end
    accum = 0
    local okPoll, err = pcall(T.Poll, T, GameTooltip)
    if not okPoll then
      T._error = tostring(err)
    end
  end)
  -- Show the clock frame: a bare Frame has no texture, so this is invisible —
  -- it only subscribes the OnUpdate above.
  if type(poll.Show) == "function" then
    poll:Show()
  end
end
