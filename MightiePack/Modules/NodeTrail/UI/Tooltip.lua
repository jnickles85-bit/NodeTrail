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
    -- A scan that already ran (the Alchemy window was open, its recipes
    -- were read) but found no reagent slots is INCOMPLETE: re-promising
    -- "open Alchemy once" promises a step that was already taken, so say
    -- what actually happened instead (t_81da8886).
    local d = (ns.Recipes and type(ns.Recipes._diag) == "table") and ns.Recipes._diag or nil
    if d and d.gated == "no-reagents" then
      table.insert(lines, { left = "Alchemy scan found no reagents — none saved" })
    else
      table.insert(lines, { left = "Open Alchemy once to list recipe uses" })
    end
  end
  return lines
end

function T:GetHoveredNodeName(tooltip)
  -- A client whose tooltip object lacks GetOwner (or a caller passing no
  -- tooltip at all) is not a herb hover — answer "no" instead of raising.
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

function T:Relayout(tooltip, opts)
  local info = { showed = false, laidOut = false, clamped = false }
  if T._relaying then
    info.skipped = "re-entrant (the client's show path is already inside us)"
    return info
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
      info.showed = true
    end
    -- 2) Optional extra: clients that expose an explicit re-layout get
    --    it too. Never the sole mechanism — step 1 must already cover
    --    a client without it.
    if type(tooltip.Layout) == "function" then
      tooltip:Layout()
      info.laidOut = true
    end
    -- 3) Clamp once into the screen (10px margin) from MEASURED edges.
    --    This runs on append, not on a clock; the client keeps ownership
    --    of any subsequent repositioning.
    if type(UIParent) == "table" and type(UIParent.GetWidth) == "function"
      and type(UIParent.GetHeight) == "function" then
      local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
      info.clamped = clampIntoScreen(tooltip, sw, sh) and true or false
    end
  end)
  T._relaying = false
  if not ok then
    T._error = tostring(err)
    info.error = tostring(err)
  end
  T._lastRelayout = info
  return info
end

--- Clamp only: move the frame back inside the screen margin, WITHOUT calling
--- Show(). Used by the poll path, which must never hide/re-show the frame (a
--- show from a tick re-runs the client's show path under a tooltip the client
--- may be in the middle of rewriting — the minimap herb tooltip flashed and
--- vanished from exactly that). The backdrop re-layout is deferred to the next
--- real client show instead.
function T:ClampOnly(tooltip)
  if type(tooltip) ~= "table" then
    return false
  end
  local clamped = false
  pcall(function()
    if type(UIParent) == "table" and type(UIParent.GetWidth) == "function"
      and type(UIParent.GetHeight) == "function" then
      clamped = clampIntoScreen(tooltip, UIParent:GetWidth(), UIParent:GetHeight()) and true or false
    end
  end)
  return clamped
end

-- ── Content fit: size the frame from MEASURED text ─────────────────────
-- Live client evidence (build 16e7954, /nt ttdiag):
--   eval #1424..#1431 src=poll name=Silverleaf lines=6-> intact=yes show=- …
--   last relayout: show=ran layout=no clamp=ran
--   skipped scripts: OnTooltipSetUnit, OnTooltipSetItem
-- `layout=no` is the finding: this client has no Frame:Layout(), and its
-- Show() does NOT re-run the padding/backdrop sizing. So the relayout could
-- never size the panel for our block, and the clamp cannot either —
-- GetRight() measures the FRAME, not the text overflowing it. The panel
-- stayed as wide as the client's own lines and our longest line ran past
-- the backdrop and off the screen edge.
--
-- The frame is therefore sized from what the client's own font strings
-- measure, never from an assumption about the client's show path:
--   * widest row = GetStringWidth of the left + right line fontstrings, our
--     block included (rows are left+right, like the client's double lines);
--   * padding    = frameWidth minus the widest CLIENT row — the client sized
--     the frame for its own lines before our block existed, so that
--     difference is this tooltip's real padding, not a constant;
--   * grow only  = SetWidth/SetHeight run only when the content exceeds the
--     frame, and never on a tooltip that holds no NodeTrail block;
--   * height     = the LAST line's measured bottom edge against the frame's,
--     so a clipped tail grows the frame by the real overflow.
-- No Show() anywhere on this path: it is SetWidth/SetHeight and reads.
local MAX_TOOLTIP_LINES = 40

local function readNum(obj, method)
  if type(obj) ~= "table" or type(obj[method]) ~= "function" then
    return nil
  end
  local ok, value = pcall(obj[method], obj)
  if ok and type(value) == "number" then
    return value
  end
  return nil
end

local function stringWidth(fontString)
  if type(fontString) ~= "table" or type(fontString.GetStringWidth) ~= "function" then
    return nil
  end
  local ok, width = pcall(fontString.GetStringWidth, fontString)
  if ok and type(width) == "number" and width >= 0 then
    return width
  end
  return nil
end

--- Measure what the tooltip holds now. Pure reads (pcall-guarded), no
--- writes: `FitContent` applies the result and /nt ttdiag prints it, so the
--- in-game run proves the numbers instead of looking plausible.
function T:Measure(tooltip)
  local m = { present = false, rows = 0, widest = 0 }
  if type(tooltip) ~= "table" then
    return m
  end
  local n = MAX_TOOLTIP_LINES
  local ok, count = pcall(function() return tooltip:NumLines() end)
  if ok and type(count) == "number" and count > 0 then
    n = math.min(count, MAX_TOOLTIP_LINES)
  end
  local widestAll, widestAllText = 0, nil
  local widestClient, widestClientText = 0, nil
  local headerIndex, lastIndex
  for i = 1, n do
    local text = lineText(tooltip, i)
    local left = _G["GameTooltipTextLeft" .. i]
    local right = _G["GameTooltipTextRight" .. i]
    local lw = stringWidth(left)
    local rw = stringWidth(right)
    if type(text) == "string" and text ~= "" then
      lastIndex = i
      if text == HEADER and headerIndex == nil then
        headerIndex = i
      end
    end
    if lw ~= nil or rw ~= nil then
      local row = (lw or 0) + (rw or 0)
      m.rows = m.rows + 1
      if row > widestAll then
        widestAll, widestAllText = row, text
      end
      -- Rows before our header are the client's own: they are what the
      -- frame was sized for, so they carry the padding measurement.
      if headerIndex == nil and row > widestClient then
        widestClient, widestClientText = row, text
      end
    end
  end
  m.frameW = readNum(tooltip, "GetWidth")
  m.frameH = readNum(tooltip, "GetHeight")
  m.widest = widestAll
  m.widestText = widestAllText
  m.hasBlock = headerIndex ~= nil
  m.clientRow = widestClient
  m.clientText = widestClientText
  m.pad = 0
  m.padFrom = "unmeasured (no row to measure it from)"
  if type(m.frameW) == "number" then
    if m.frameW >= widestAll then
      -- The frame ALREADY encloses every row (the client re-sized after our
      -- block, or a previous fit did): its padding is the difference between
      -- the frame and the widest row, and neededW == frameW, so nothing is
      -- widened. This is what keeps a second fit from ratcheting the width.
      m.pad = m.frameW - widestAll
      m.padFrom = "frame width minus the widest row (the frame already encloses the content)"
    elseif widestClient > 0 and m.frameW > widestClient then
      -- The frame was sized for the client's own rows, before our block
      -- existed: this difference is the tooltip's real padding.
      m.pad = m.frameW - widestClient
      m.padFrom = "frame width minus the widest client row (frame sized before our block)"
    end
  end
  m.neededW = widestAll + m.pad
  -- Height: the last line's measured bottom against the frame's bottom edge.
  m.neededH = nil
  m.heightMeasured = false
  if lastIndex then
    local last = _G["GameTooltipTextLeft" .. lastIndex]
    local lastBottom = last and readNum(last, "GetBottom")
    local frameBottom = readNum(tooltip, "GetBottom")
    if lastBottom and frameBottom then
      m.heightMeasured = true
      m.lastLineBottom = lastBottom
      m.frameBottom = frameBottom
      if type(m.frameH) == "number" and lastBottom < frameBottom - 0.5 then
        m.neededH = m.frameH + (frameBottom - lastBottom)
        m.tailOverflow = frameBottom - lastBottom
      end
    end
  end
  m.present = m.rows > 0
  return m
end

--- Grow the frame to enclose the measured content. Never shrinks, never
--- Shows, never touches a tooltip without our block. Returns what it did so
--- the ring and /nt ttdiag can report it.
function T:FitContent(tooltip)
  local info = { ran = false }
  local m = self:Measure(tooltip)
  info.measure = m
  if not m.present then
    info.skip = "no measurable content on this client (no line fontstrings / GetStringWidth)"
    self._lastFit = info
    return info
  end
  if not m.hasBlock then
    info.skip = "no NodeTrail block in this tooltip — not touched"
    self._lastFit = info
    return info
  end
  info.ran = true
  info.beforeW, info.beforeH = m.frameW, m.frameH
  info.widest, info.pad, info.neededW, info.neededH = m.widest, m.pad, m.neededW, m.neededH
  if type(m.frameW) == "number" and m.neededW > m.frameW + 0.5 then
    local ok = pcall(tooltip.SetWidth, tooltip, m.neededW)
    info.widened = ok or nil
  end
  if type(m.frameH) == "number" and type(m.neededH) == "number"
    and m.neededH > m.frameH + 0.5 then
    local ok = pcall(tooltip.SetHeight, tooltip, m.neededH)
    info.grew = ok or nil
  end
  info.afterW = readNum(tooltip, "GetWidth")
  info.afterH = readNum(tooltip, "GetHeight")
  self._lastFit = info
  return info
end

-- ── Refresh decision ring ──────────────────────────────────────────────
-- The in-client flicker report ("the block appears, then goes away super
-- fast") cannot be diagnosed from a screenshot: what matters is who evaluated
-- the tooltip, what it found, and whether the evaluation touched the frame.
-- The last eight decisions are kept and printed by /nt ttdiag AFTER the fact.
local RING_MAX = 8
local RING = {}
local evalCount = 0

--- The sequence number is taken when an evaluation STARTS, and the entry is
--- stored when it finishes: a relayout can re-enter Refresh synchronously, and
--- the operator has to read the outer evaluation first.
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

function T:Ring()  -- compat alias, returns the same table
  return RING
end


-- /nt ttdiag — the in-client evidence channel for tooltip layout. Prints
-- only what is live: the refresh-decision ring (who evaluated the tooltip,
-- what it found, and whether the evaluation touched the frame), line count +
-- frame size, every anchor in the REAL GetPoint order (point, relativeTo,
-- relativePoint, offsetX, offsetY), the measured screen edges, the
-- screen-vs-rect verdict, and whether the current block was added after the
-- client's layout. Cheap: a handful of API calls, no loops beyond
-- GetNumPoints — and every read is pcall-guarded, because this command is
-- also the one that has to work on a client missing most of these APIs.
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

  -- The ring goes first: it is the evidence for the flicker even when the
  -- tooltip is closed by the time /nt ttdiag is typed.
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
      local fitFlag = "-"
      local fitFrame = "-"
      if type(e.fit) == "table" then
        if e.fit.ran and (e.fit.widened or e.fit.grew) then
          fitFlag = (e.fit.widened and "widened" or "") .. (e.fit.grew and (e.fit.widened and "+grew" or "grew") or "")
        elseif e.fit.ran then
          fitFlag = "fits"
        else
          fitFlag = "no"
        end
        if e.fit.ran then
          local function px(v)
            return type(v) == "number" and string.format("%.0f", v) or "?"
          end
          fitFrame = px(e.fit.beforeW) .. "x" .. px(e.fit.beforeH) .. "->"
            .. px(e.fit.afterW) .. "x" .. px(e.fit.afterH)
        end
      end
      say(("eval #%s src=%s name=%s lines=%s->%s intact=%s appended=%s shown=%s show=%s clamp=%s fit=%s frame=%s — %s"):format(
        tostring(e.n or "?"), tostring(e.source or "?"), tostring(e.name or "-"),
        tostring(e.before or "-"), tostring(e.after or "-"),
        flag(e.intact), flag(e.appended), flag(e.shown), flag(e.show), flag(e.clamp),
        fitFlag, fitFrame,
        tostring(e.skip or "")))
    end
  end
  if type(T._lastRelayout) == "table" then
    local r = T._lastRelayout
    say(("last relayout: show=%s layout=%s clamp=%s%s"):format(
      r.showed and "ran" or "no", r.laidOut and "ran" or "no",
      r.clamped and "ran" or "no", r.skipped and (" (" .. tostring(r.skipped) .. ")") or ""))
  end

  local gt = GameTooltip
  if type(gt) ~= "table" then
    say("GameTooltip unavailable")
    return
  end
  -- Content fit: what the tooltip holds NOW (measured) plus what the last fit
  -- did. This is the evidence that the panel is sized from measured text and
  -- not from an assumption about the client's show path — the live client
  -- printed show=ran layout=no while the block still overflowed.
  local function fmtPx(v)
    if type(v) == "number" then
      return string.format("%.0f", v)
    end
    return "absent"
  end
  local measure = T:Measure(gt)
  if type(measure) == "table" and measure.present then
    say(("content: frame=%sx%s widest row=%s%s pad=%s (%s) needs width=%s%s"):format(
      fmtPx(measure.frameW), fmtPx(measure.frameH), fmtPx(measure.widest),
      type(measure.widestText) == "string" and (" \"" .. measure.widestText .. "\"") or "",
      fmtPx(measure.pad), tostring(measure.padFrom or "?"), fmtPx(measure.neededW),
      measure.hasBlock and "" or " — no NodeTrail block, this tooltip is never resized"))
    if type(measure.neededH) == "number" then
      say(("content height: last line %.0fpx below the frame bottom -> needs height=%s"):format(
        measure.tailOverflow or 0, fmtPx(measure.neededH)))
    end
  else
    say("content: not measurable on this client (no line font strings with GetStringWidth)")
  end
  if type(T._lastFit) == "table" then
    local f = T._lastFit
    say(("last fit: frame %sx%s -> %sx%s widest=%s pad=%s widened=%s grew=%s%s"):format(
      fmtPx(f.beforeW), fmtPx(f.beforeH), fmtPx(f.afterW), fmtPx(f.afterH),
      fmtPx(f.widest), fmtPx(f.pad),
      f.widened and "yes" or "no", f.grew and "yes" or "no",
      f.skip and (" (" .. tostring(f.skip) .. ")") or ""))
  else
    say("last fit: none yet (no evaluation measured the content)")
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
  if type(T._skippedScripts) == "table" and #T._skippedScripts > 0 then
    -- Name the skipped hooks (printed before the hidden-early return so
    -- the operator sees it even when the tooltip is currently closed,
    -- t_81da8886).
    say("skipped scripts: " .. table.concat(T._skippedScripts, ", ")
      .. " (this client does not expose them — their fast paths are off)")
  end
  -- Reader helpers: every one of them answers "absent" rather than raising.
  local function readNum(method)
    local fn = gt[method]
    if type(fn) ~= "function" then
      return nil
    end
    local ok, value = pcall(fn, gt)
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
  -- Measured screen edges (the client's own getters when present).
  if type(gt.GetLeft) == "function" and type(gt.GetRight) == "function"
    and type(gt.GetTop) == "function" and type(gt.GetBottom) == "function" then
    local okE, l, r, t, b = pcall(gt.GetLeft, gt)
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
    else
      say("screen: UIParent size unavailable")
    end
  else
    say("screen: UIParent absent")
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
--
-- `source` says who is asking: "show" (the client's OnShow), "setunit",
-- "setitem", or "poll" (our private clock). It decides whether a late append
-- may pull the client through its show path: a poll tick must NEVER Show the
-- frame (that is the minimap herb flash), so it clamps the position only and
-- leaves the backdrop re-layout to the next real client show.
function T:Refresh(tooltip, source)
  source = source or "poll"
  local entry = { n = nextSeq(), source = source, when = type(GetTime) == "function" and GetTime() or nil }
  local name = self:GetHoveredNodeName(tooltip)
  entry.name = name
  if type(tooltip.NumLines) == "function" then
    entry.before = tooltip:NumLines()
  end
  entry.shown = type(tooltip.IsShown) == "function" and tooltip:IsShown() or false

  if not name then
    -- Not a herb tooltip (unknown object, unit tooltip, some other window):
    -- whatever is in there is the client's, own nothing.
    self.last = nil
    entry.skip = "not a herb tooltip"
    ringPush(entry)
    return
  end
  local lines = T.BuildLines(name)
  if not lines then
    self.last = nil
    entry.skip = "no lines for this node"
    ringPush(entry)
    return
  end
  entry.intact = blockIntact(tooltip, name)
  if entry.intact then
    -- While the same node is hovered the block must stay put: no line is
    -- touched. A deferred relayout from an earlier append is flushed here, on
    -- a real client evaluation, where a Show is safe.
    if self._layoutPending and source ~= "poll" then
      self._layoutPending = false
      local info = self:Relayout(tooltip)
      entry.show = info and info.showed or false
      entry.clamp = info and info.clamped or false
      entry.skip = "block intact; flushed a deferred relayout"
    elseif source ~= "poll" then
      -- Event evaluations are rare (one per client populate), so the panel is
      -- re-measured here too: a client that re-shows the tooltip with our
      -- block still in it must not leave the frame sized for its own lines.
      -- Reads + SetWidth/SetHeight only — this never Shows the frame.
      local fit = self:FitContent(tooltip)
      entry.fit = fit
      if fit and (fit.widened or fit.grew) then
        entry.clamp = self:ClampOnly(tooltip)
      end
      entry.skip = "block intact (no line touched); frame re-checked against the measured content"
    else
      entry.skip = "block intact (nothing touched)"
    end
    ringPush(entry)
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
  entry.appended = true
  entry.after = self.last.after
  if shown then
    -- Late append: the client sized and anchored the tooltip BEFORE our
    -- lines existed, so its layout decisions don't account for them.
    if source == "poll" then
      -- A poll tick never hides/re-shows the frame. It DOES size the panel
      -- from the measured text (SetWidth/SetHeight — no Show, no flash), then
      -- clamps using the measured edges: GetRight() measures the frame, so
      -- the clamp has to run AFTER the width changed.
      entry.fit = self:FitContent(tooltip)
      entry.clamp = self:ClampOnly(tooltip)
      entry.show = false
      -- Kept from the relayout design: on a client whose Show DOES re-run the
      -- padding sizing, the next real client evaluation still gets one. The
      -- panel no longer depends on it (the fit above already sized it).
      self._layoutPending = true
      entry.skip = "poll append; frame fitted to measured content, no Show"
    else
      -- Pull the client through its own show path once. On this client that
      -- show does NOT re-run the padding sizing (ttdiag: show=ran
      -- layout=no), so the frame is then sized from the measured text and
      -- clamped again for the new width. The client keeps ownership of any
      -- subsequent repositioning.
      local info = self:Relayout(tooltip)
      entry.show = info and info.showed or false
      entry.clamp = info and info.clamped or false
      entry.fit = self:FitContent(tooltip)
      if entry.fit and (entry.fit.widened or entry.fit.grew) then
        entry.clamp = self:ClampOnly(tooltip)
      end
      entry.skip = "appended on " .. source .. "; relayout ran, frame fitted to measured content"
    end
  else
    entry.skip = "appended while hidden (client lays out on show)"
  end
  ringPush(entry)
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
  local function onPopulate(tt, source)
    local ok, err = pcall(T.Refresh, T, tt, source)
    if not ok then
      T._error = tostring(err)
    end
  end
  GameTooltip:HookScript("OnShow", function(tt)
    onPopulate(tt, "show")
  end)

  -- SetUnit / SetItem fire on client builds that expose the events; a
  -- client that lacks one loses that fast path rather than breaking
  -- Enable. Forbidden by the live client's own usage error (t_81da8886):
  --   bad argument #2 to '?' (Usage: local success = self:HookScript(
  --   scriptTypeName, script[, bindingType]))
  -- so ask HasScript first when the client offers it, keep the pcall as
  -- the backstop either way, record the skipped script for /nt ttdiag,
  -- and never write _error — a missing optional script is not a module
  -- error and masking it would hide the real ones.
  self._skippedScripts = {}
  for _, event in ipairs({ "OnTooltipSetUnit", "OnTooltipSetItem" }) do
    local skip = false
    if type(GameTooltip.HasScript) == "function" then
      local okH, has = pcall(GameTooltip.HasScript, GameTooltip, event)
      if okH and has == false then
        skip = true
      end
    end
    if not skip then
      local ok = pcall(GameTooltip.HookScript, GameTooltip, event,
        function(tt)
          onPopulate(tt, event == "OnTooltipSetUnit" and "setunit" or "setitem")
        end)
      if not ok then
        skip = true
      end
    end
    if skip then
      table.insert(self._skippedScripts, event)
    end
  end

  -- Dirty tracking is a hint only: the clears we CAN observe (clear event)
  -- mark content as rewritten, but self-heal never relies on it — the
  -- repopulate that matters bypasses all of these.
  GameTooltip:HookScript("OnTooltipCleared", function()
    T.dirty = true
  end)
  -- NEVER replace a GameTooltip method. An earlier build wrapped ClearLines and
  -- Clear in Lua to set a flag; the client then reported, on every action-bar
  -- hover:
  --   SharedTooltipTemplates.lua:167: attempt to index local 'color'
  --   (a secret table value, while execution tainted by 'MightiePack')
  -- because Blizzard's own tooltip pipeline called the replaced (tainted)
  -- method, and a tainted execution path may not touch secret values. The flag
  -- was only a hint, so the wrapper is gone rather than narrowed.

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
          -- "poll": this tick may append content, but it must not Show the
          -- frame (see T:Refresh / T:ClampOnly).
          local ok2, err2 = pcall(T.Refresh, T, GameTooltip, "poll")
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
