-- NodeTrail — the herb block's OWN panel (t_f4ff9ea6).
--
-- Three attempts to carry the block INSIDE Blizzard's tooltip failed the same
-- way, and this file exists because the failure is structural, not a bug we
-- could patch:
--
--   1. append the lines, then widen the frame  -> clipped again after 3 hovers;
--   2. measure the widest line and SetWidth/   -> the client's own width wins
--      SetHeight                                 back on the next show;
--   3. wrap each line to the client's width    -> after longer play the
--                                                 backdrop stopped covering our
--                                                 lines at all: `Your picks: 5`
--                                                 and the alchemy line sat on
--                                                 the raw map below the panel.
--
-- The client sizes the tooltip's backdrop at SHOW time and never re-derives it
-- for lines added afterwards; nothing we write survives the next show. So the
-- block stops living in Blizzard's frame. This module owns a small frame of
-- its own — created by us, filled by us, sized by us, hidden by us — and
-- merely READS the tooltip's rect to sit next to it.
--
-- Rules this file obeys, deliberately:
--   * no HookScript / SetScript / AddLine / SetWidth on anything Blizzard owns;
--     the tooltip is read-only here (GetLeft/GetRight/GetTop/GetBottom and the
--     GetPoint 5-tuple, all pcall-guarded);
--   * the panel is drawn with plain textures — a CreateTexture background plus
--     four 1px border textures — because that is the one primitive Blizzard
--     never re-derives (SetBackdrop/BackdropTemplate is not assumed to exist;
--     whether the client exposed it is recorded and reported by /nt ttdiag);
--   * the width comes from OUR lines only: measure each with the tooltip's own
--     font, take the widest, add padding, cap at ~45% of the screen and wrap
--     anything past the cap at `, ` / space / `: ` boundaries. A percentage is
--     a separate column of the same row and is never split from its item name;
--   * rows are rebuilt from scratch on every update, so the panel cannot
--     accumulate a duplicate block, and stale rows are cleared, not reused.
local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local P = {}
ns.TooltipPanel = P

P.NAME = "NodeTrailHerbPanel"

-- Geometry, in the panel's own (local) units. The panel adopts the tooltip's
-- effective scale, so local units and screen pixels are bridged by `scale`
-- where it matters (the cap and the placement).
P.PAD_X = 10 -- left/right padding inside the background
P.PAD_Y = 8 -- top/bottom padding inside the background
P.LINE_GAP = 2 -- between two of our rows
P.COL_GAP = 12 -- between the name column and the percentage column
P.TOOLTIP_GAP = 4 -- between the tooltip's edge and our panel
P.SCREEN_MARGIN = 10 -- keep the panel this far inside the screen edges
P.CAP_FRACTION = 0.45 -- wrap target: at most 45% of the screen width
P.MIN_WIDTH = 72
P.INDENT = "  " -- continuation indent

-- Column of the background and the 1px border. Dark and quiet: it has to read
-- as a tooltip continuation, not as a new window.
P.BG = { 0.05, 0.05, 0.07, 0.94 }
P.BORDER = { 0.42, 0.42, 0.48, 1 }

-- ── guarded reads ────────────────────────────────────────────────────────
-- Everything below the constants is defensive on purpose: this runs on a
-- client (Forever 16001) that is missing large parts of the frame API, and a
-- diagnostic that raises is worth less than one that says "absent".
local function fn(obj, name)
  if type(obj) ~= "table" then
    return nil
  end
  local f = obj[name]
  if type(f) ~= "function" then
    return nil
  end
  return f
end

local function call(obj, name, ...)
  local f = fn(obj, name)
  if not f then
    return nil
  end
  local ok, a, b, c, d = pcall(f, obj, ...)
  if not ok then
    return nil
  end
  return a, b, c, d
end

-- Did the method exist and run without raising? `SetText`/`Show`/`SetPoint`
-- return nothing on the real client, so their RESULT can never be the test.
local function works(obj, name, ...)
  local f = fn(obj, name)
  if not f then
    return false
  end
  return (pcall(f, obj, ...)) and true or false
end

local function num(obj, name)
  local v = call(obj, name)
  if type(v) == "number" then
    return v
  end
  return nil
end

local function screenSize()
  local sw = num(UIParent, "GetWidth")
  local sh = num(UIParent, "GetHeight")
  if type(sw) == "number" and type(sh) == "number" and sw > 0 and sh > 0 then
    return sw, sh
  end
  -- A client with no readable UIParent still gets a panel; the cap and the
  -- clamp then use the classic 4:3 window instead of an unmeasurable one.
  return 1024, 768
end

-- ── the tooltip's rect, read-only ────────────────────────────────────────
-- Measured edges (the client's own getters) are the reliable source. Only when
-- they are absent is the rect derived from the first anchor plus the frame
-- size, with GetPoint parsed in its documented order:
--   point, relativeTo, relativePoint, offsetX, offsetY.
-- Nothing is ever written back to the tooltip.
function P:TooltipRect(tooltip)
  if type(tooltip) ~= "table" then
    return nil, "no tooltip object"
  end
  local l = num(tooltip, "GetLeft")
  local r = num(tooltip, "GetRight")
  local b = num(tooltip, "GetBottom")
  local t = num(tooltip, "GetTop")
  if type(l) == "number" and type(r) == "number"
    and type(b) == "number" and type(t) == "number" then
    return { left = l, right = r, bottom = b, top = t }, "measured edges"
  end
  local getPoint = fn(tooltip, "GetPoint")
  local w = num(tooltip, "GetWidth")
  local h = num(tooltip, "GetHeight")
  if not getPoint or type(w) ~= "number" or type(h) ~= "number" then
    return nil, "no edge getters and no anchor to derive them from"
  end
  local ok, point, relativeTo, relativePoint, xOfs, yOfs = pcall(getPoint, tooltip, 1)
  if not ok or type(point) ~= "string" or type(relativePoint) ~= "string"
    or type(xOfs) ~= "number" or type(yOfs) ~= "number" then
    return nil, "GetPoint(1) did not return the documented 5-tuple"
  end
  local relW, relH
  if type(relativeTo) == "table" then
    relW, relH = num(relativeTo, "GetWidth"), num(relativeTo, "GetHeight")
  end
  if type(relW) ~= "number" or type(relH) ~= "number" then
    relW, relH = screenSize()
  end
  local ox = relativePoint:find("RIGHT") and relW
    or (relativePoint:find("CENTER") and relW * 0.5 or 0)
  local oy = relativePoint:find("TOP") and relH
    or (relativePoint:find("CENTER") and relH * 0.5 or 0)
  local cx, cy = ox + xOfs, oy + yOfs
  local left = cx - (point:find("RIGHT") and w or (point:find("CENTER") and w * 0.5 or 0))
  local right = cx + (point:find("LEFT") and w or (point:find("CENTER") and w * 0.5 or 0))
  local bottom = cy - (point:find("TOP") and h or (point:find("CENTER") and h * 0.5 or 0))
  local top = cy + (point:find("BOTTOM") and h or (point:find("CENTER") and h * 0.5 or 0))
  return { left = left, right = right, bottom = bottom, top = top }, "first anchor + size"
end

-- UIParent's effective scale: the coordinate space every rect we read and every
-- offset we write is expressed in. Our own frame inherits it, so the tooltip's
-- scale has to be divided by it before it can be applied to the frame.
function P:ParentScale()
  local s = num(UIParent, "GetEffectiveScale")
  if type(s) ~= "number" or s <= 0 then
    s = num(UIParent, "GetScale")
  end
  if type(s) ~= "number" or s <= 0 then
    s = 1
  end
  return s
end

function P:TooltipScale(tooltip)
  local s = num(tooltip, "GetEffectiveScale")
  if type(s) ~= "number" or s <= 0 then
    s = num(tooltip, "GetScale")
  end
  if type(s) ~= "number" or s <= 0 then
    s = 1
  end
  return s
end

-- ── frame + skin ─────────────────────────────────────────────────────────
-- Plain textures, always. `SetBackdrop` is only *measured*: a client that has
-- it would still be Blizzard's own widget, and the whole point of this file is
-- that the block's background is ours. ttdiag reports what was measured.
local function skin(frame)
  local bg = call(frame, "CreateTexture", nil, "BACKGROUND")
  if type(bg) == "table" then
    call(bg, "SetAllPoints")
    if not works(bg, "SetColorTexture", P.BG[1], P.BG[2], P.BG[3], P.BG[4]) then
      works(bg, "SetTexture", P.BG[1], P.BG[2], P.BG[3], P.BG[4])
    end
  end
  local edges = {
    { "TOPLEFT", "TOPRIGHT", "height" },
    { "BOTTOMLEFT", "BOTTOMRIGHT", "height" },
    { "TOPLEFT", "BOTTOMLEFT", "width" },
    { "TOPRIGHT", "BOTTOMRIGHT", "width" },
  }
  local borders = {}
  for i, e in ipairs(edges) do
    local tex = call(frame, "CreateTexture", nil, "BORDER")
    if type(tex) == "table" then
      call(tex, "SetPoint", e[1], frame, e[1], 0, 0)
      call(tex, "SetPoint", e[2], frame, e[2], 0, 0)
      if e[3] == "height" then
        call(tex, "SetHeight", 1)
      else
        call(tex, "SetWidth", 1)
      end
      if not works(tex, "SetColorTexture", P.BORDER[1], P.BORDER[2], P.BORDER[3], P.BORDER[4]) then
        works(tex, "SetTexture", P.BORDER[1], P.BORDER[2], P.BORDER[3], P.BORDER[4])
      end
      borders[i] = tex
    end
  end
  return bg, borders
end

function P:_Ensure()
  local frame = self.frame
  if type(frame) == "table" and self._hasRows then
    return frame
  end
  if type(CreateFrame) ~= "function" then
    self._error = "CreateFrame is not available on this client"
    return nil
  end
  local parent = (type(UIParent) == "table") and UIParent or nil
  local ok, f = pcall(CreateFrame, "Frame", P.NAME, parent)
  if not ok or type(f) ~= "table" then
    self._error = "CreateFrame refused the panel frame: " .. tostring(not ok and f or "not a table")
    return nil
  end
  call(f, "SetFrameStrata", "TOOLTIP")
  call(f, "SetFrameLevel", 0)
  call(f, "EnableMouse", false)
  works(f, "Hide")
  self.frame = f
  self.background, self.borders = skin(f)
  self.backdropAPI = (type(f.SetBackdrop) == "function") and "present (not used — the skin is our own textures)"
    or "absent (plain textures)"
  -- The measuring font string. It carries the tooltip's font so a width read
  -- from it is comparable to the client's own text, and it is NEVER written
  -- into a frame Blizzard owns.
  local meter = call(f, "CreateFontString", nil, "ARTWORK")
  if type(meter) == "table" then
    works(meter, "Hide")
    self.meter = meter
  end
  self._pool = {}
  self._hasRows = true
  return f
end

function P:_Row(i)
  local pool = self._pool
  local row = pool[i]
  if type(row) == "table" then
    return row
  end
  local frame = self.frame
  if type(frame) ~= "table" then
    return nil
  end
  local left = call(frame, "CreateFontString", nil, "ARTWORK")
  if type(left) ~= "table" then
    return nil
  end
  row = { left = left, right = call(frame, "CreateFontString", nil, "ARTWORK") }
  pool[i] = row
  if type(row.right) == "table" then
    call(row.right, "SetJustifyH", "RIGHT")
  end
  return row
end

-- The tooltip's font, applied to our own font strings. Returns a signature so
-- /nt ttdiag can show whether the measurement uses the client's font or a
-- fallback, and so a font change is a visible event rather than a silent one.
function P:AdoptFont(tooltip)
  local src = _G["GameTooltipTextLeft1"]
  local path, size, flags
  if type(src) == "table" then
    local getFont = fn(src, "GetFont")
    if getFont then
      local ok, a, b, c = pcall(getFont, src)
      if ok and type(a) == "string" then
        path, size, flags = a, b, c
      end
    end
  end
  local targets = {}
  if type(self.meter) == "table" then
    targets[#targets + 1] = self.meter
  end
  if type(self._pool) == "table" then
    for _, row in pairs(self._pool) do
      targets[#targets + 1] = row.left
      if type(row.right) == "table" then
        targets[#targets + 1] = row.right
      end
    end
  end
  local applied = false
  if path then
    for _, fs in ipairs(targets) do
      if type(fs) == "table" and works(fs, "SetFont", path, size, flags) then
        applied = true
      end
    end
  end
  if not applied and type(src) == "table" then
    local getFontObject = fn(src, "GetFontObject")
    if getFontObject then
      local ok, obj = pcall(getFontObject, src)
      if ok and type(obj) == "table" then
        for _, fs in ipairs(targets) do
          if type(fs) == "table" and works(fs, "SetFontObject", obj) then
            applied = true
          end
        end
        path = "fontobject:" .. tostring(call(obj, "GetName") or "?")
        size = nil
      end
    end
  end
  self._fontSig = tostring(path or "client default")
    .. (size and (" " .. tostring(size)) or "")
    .. (flags and (" " .. tostring(flags)) or "")
  self._fontApplied = applied
  return self._fontSig, applied
end

-- ── measuring and wrapping ────────────────────────────────────────────────
function P:_Measure()
  local meter = self.meter
  if type(meter) ~= "table" then
    return nil
  end
  local cache = {}
  local function measure(text)
    if type(text) ~= "string" then
      return nil
    end
    local cached = cache[text]
    if cached ~= nil then
      return cached
    end
    if not works(meter, "SetText", text) then
      return nil
    end
    local w = num(meter, "GetStringWidth")
    if type(w) ~= "number" then
      return nil
    end
    cache[text] = w
    return w
  end
  return measure
end

-- Break opportunities in `text`, each with the prefix that ends there and the
-- rest that follows it. Preference on a tie is comma (a real list boundary),
-- then a plain space, then `: ` last: breaking after a colon leaves a label
-- dangling on a line of its own, so it is only used when nothing else fits.
local function breakCandidates(text)
  local out = {}
  local i = 1
  local n = #text
  while i < n do
    local two = text:sub(i, i + 1)
    if two == ", " then
      out[#out + 1] = { endPos = i, restStart = i + 2, prio = 1 }
    elseif two == ": " then
      out[#out + 1] = { endPos = i + 1, restStart = i + 2, prio = 3 }
    elseif two:sub(1, 1) == " " and i > 1 then
      out[#out + 1] = { endPos = i - 1, restStart = i + 1, prio = 2 }
    end
    i = i + 1
  end
  return out
end

-- Greedy wrap of one string to `firstBudget` (and `laterBudget` for the
-- continuations, which carry the indent). A string with no break opportunity
-- wider than the budget is returned whole — the caller then lets the panel be
-- as wide as that line, which is what keeps "the panel is always at least as
-- wide as its widest line" true on every client.
local function wrapText(text, firstBudget, laterBudget, measure)
  local chunks = {}
  local rest = text
  local budget = firstBudget
  local guard = 0
  while true do
    guard = guard + 1
    local prefix = (#chunks > 0) and P.INDENT or ""
    local avail = budget - measure(prefix)
    if avail < 8 then
      avail = budget
    end
    if measure(prefix .. rest) <= avail or guard > 32 then
      chunks[#chunks + 1] = prefix .. rest
      return chunks
    end
    local best
    for _, c in ipairs(breakCandidates(rest)) do
      if c.endPos > 0 and measure(prefix .. rest:sub(1, c.endPos)) <= avail then
        if best == nil or c.prio < best.prio
          or (c.prio == best.prio and c.endPos > best.endPos) then
          best = c
        end
      end
    end
    if best == nil then
      -- Nothing fits: take the EARLIEST break so the overflow is one token,
      -- not the whole rest of the line.
      for _, c in ipairs(breakCandidates(rest)) do
        if c.endPos > 0 and (best == nil or c.endPos < best.endPos) then
          best = c
        end
      end
      if best == nil then
        chunks[#chunks + 1] = prefix .. rest
        return chunks
      end
    end
    chunks[#chunks + 1] = prefix .. rest:sub(1, best.endPos)
    rest = rest:sub(best.restStart)
    budget = laterBudget
    if rest == "" then
      return chunks
    end
  end
end

-- Wrap our block to the cap. A drop row is a name and a value in two columns:
-- the value ("100% (base)") is atomic and stays with the first line of its
-- name, so a percentage can never be separated from the item it belongs to.
function P:Wrap(lines, cap, measure)
  local rows = {}
  for i = 1, #lines do
    local line = lines[i]
    local left = tostring(line.left or "")
    local right = line.right and tostring(line.right) or nil
    if right then
      local rw = measure(right) or 0
      local firstBudget = cap - P.COL_GAP - rw
      if measure(left) <= firstBudget then
        rows[#rows + 1] = { left = left, right = right }
      else
        local chunks = wrapText(left, math.max(firstBudget, P.MIN_WIDTH * 0.5), cap, measure)
        for k, chunk in ipairs(chunks) do
          rows[#rows + 1] = { left = chunk, right = (k == 1) and right or nil, wrapped = true }
        end
      end
    else
      local chunks = wrapText(left, cap, cap, measure)
      for _, chunk in ipairs(chunks) do
        rows[#rows + 1] = { left = chunk, wrapped = #chunks > 1 }
      end
    end
  end
  return rows
end

-- ── visibility ───────────────────────────────────────────────────────────
function P:IsShown()
  local frame = self.frame
  if type(frame) ~= "table" then
    return false
  end
  local shown = call(frame, "IsShown")
  if shown ~= nil then
    return shown == true
  end
  return self._shown == true
end

function P:Hide(reason)
  local was = self:IsShown()
  self._shown = false
  self._hideReason = reason
  if type(self.frame) == "table" then
    call(self.frame, "Hide")
  end
  return was
end

-- ── the update: rebuild, size, place ─────────────────────────────────────
-- Called by the tooltip poller for every hovered herb. Rows are rebuilt from
-- scratch (every pooled row is cleared first), so repeating an update for the
-- same node can never duplicate a line.
function P:Update(lines, tooltip)
  local info = { rows = 0, shown = false }
  if type(lines) ~= "table" or #lines == 0 then
    self:Hide("no lines")
    info.skip = "no lines to show"
    return info
  end
  local frame = self:_Ensure()
  if not frame then
    info.skip = self._error or "no frame factory on this client"
    return info
  end
  local measure = self:_Measure()
  if not measure then
    info.skip = "no measuring font string on this client"
    self:Hide("unmeasurable")
    return info
  end
  local sw, sh = screenSize()
  -- Our frame is parented to UIParent, so it already inherits UIParent's scale.
  -- The number to apply is the RATIO that makes our effective scale equal the
  -- tooltip's; applying the tooltip's absolute scale would double it on a UI
  -- that is itself scaled, and the panel would overflow the tooltip's text.
  local parentScale = self:ParentScale()
  local scale = self:TooltipScale(tooltip) / parentScale
  if type(scale) ~= "number" or scale <= 0 then
    scale = 1
  end
  call(frame, "SetScale", scale)
  -- Draw above the tooltip it follows: same strata, one level higher. Guarded —
  -- a client without GetFrameLevel keeps the strata order.
  local tooltipLevel = num(tooltip, "GetFrameLevel")
  if type(tooltipLevel) == "number" then
    call(frame, "SetFrameLevel", tooltipLevel + 5)
  end
  -- `scale` is now the frame's local scale, and `width * scale` is a width in
  -- UIParent's coordinate space — the same space as the tooltip's rect.

  local budgetScreen = sw * P.CAP_FRACTION
  local cap = budgetScreen / scale
  local fontSig = self:AdoptFont(tooltip)

  local rows = self:Wrap(lines, cap, measure)

  -- Lay the rows out: text first (so a width read is the width drawn), then
  -- the panel's own size from the widest of OUR rows plus the padding.
  local widest, widestText = 0, nil
  local lineH = 0
  local pool = self._pool
  for i = 1, #pool do
    call(pool[i].left, "SetText", "")
    if type(pool[i].right) == "table" then
      call(pool[i].right, "SetText", "")
    end
  end
  for i, row in ipairs(rows) do
    local slot = self:_Row(i)
    if not slot then
      info.skip = "no font strings on this client"
      self:Hide("unrenderable")
      return info
    end
    call(slot.left, "SetText", row.left)
    if type(slot.right) == "table" then
      call(slot.right, "SetText", row.right or "")
    end
    works(slot.left, "Show")
    if type(slot.right) == "table" then
      if row.right then
        call(slot.right, "Show")
      else
        call(slot.right, "Hide")
      end
    end
    local lw = num(slot.left, "GetStringWidth") or 0
    local rw = row.right and (num(slot.right, "GetStringWidth") or 0) or 0
    local w = lw + (row.right and (P.COL_GAP + rw) or 0)
    row.width = w
    if w > widest then
      widest, widestText = w, row.left .. (row.right and (" | " .. row.right) or "")
    end
    local h = num(slot.left, "GetHeight") or 0
    if h > lineH then
      lineH = h
    end
  end
  for i = #rows + 1, #pool do
    call(pool[i].left, "Hide")
    call(pool[i].left, "SetText", "")
    if type(pool[i].right) == "table" then
      call(pool[i].right, "Hide")
      call(pool[i].right, "SetText", "")
    end
  end
  if lineH <= 0 then
    lineH = 14
  end

  -- Place the rows. A font string with no anchor does not sit where it was
  -- "meant" to go on this client — it lands at the frame's centre and the block
  -- becomes an unreadable pile — so every row is anchored explicitly: the left
  -- column at the padding inset, the right column at the opposite inset, one
  -- line height per row.
  for i = 1, #rows do
    local slot = pool[i]
    local y = -(P.PAD_Y + (i - 1) * (lineH + P.LINE_GAP))
    call(slot.left, "ClearAllPoints")
    call(slot.left, "SetPoint", "TOPLEFT", frame, "TOPLEFT", P.PAD_X, y)
    if type(slot.right) == "table" then
      call(slot.right, "ClearAllPoints")
      call(slot.right, "SetPoint", "TOPRIGHT", frame, "TOPRIGHT", -P.PAD_X, y)
    end
  end

  local width = math.max(P.MIN_WIDTH, widest + 2 * P.PAD_X)
  local height = 2 * P.PAD_Y + #rows * lineH + math.max(0, #rows - 1) * P.LINE_GAP
  if not works(frame, "SetSize", width, height) then
    call(frame, "SetWidth", width)
    call(frame, "SetHeight", height)
  end
  self.width, self.height = width, height
  self.rows = rows
  self.widest, self.widestText = widest, widestText
  self.capScreen = budgetScreen
  self.fontSig = fontSig
  info.rows, info.width, info.height = #rows, width, height
  info.widest, info.widestText = widest, widestText
  info.cap = cap
  info.font = fontSig

  -- Position from the tooltip's geometry, read-only.
  local rect, how = self:TooltipRect(tooltip)
  if not rect then
    info.skip = "panel built but the tooltip rect is unreadable (" .. tostring(how) .. ")"
    info.position = "unreadable"
    self:Hide("tooltip rect unreadable")
    return info
  end
  local screenW, screenH = width * scale, height * scale
  local left = rect.left
  local top = rect.bottom - P.TOOLTIP_GAP
  local placement, clampedX, clampedY = "below", false, false
  if top - screenH < P.SCREEN_MARGIN then
    -- No room under the tooltip: sit above it instead.
    placement = "above"
    top = rect.top + P.TOOLTIP_GAP + screenH
  end
  if top > sh - P.SCREEN_MARGIN then
    top = sh - P.SCREEN_MARGIN
    clampedY = true
  end
  if top - screenH < P.SCREEN_MARGIN then
    top = P.SCREEN_MARGIN + screenH
    clampedY = true
  end
  if left + screenW > sw - P.SCREEN_MARGIN then
    left = sw - P.SCREEN_MARGIN - screenW
    clampedX = true
  end
  if left < P.SCREEN_MARGIN then
    left = P.SCREEN_MARGIN
    clampedX = true
  end
  local bottom = top - screenH
  call(frame, "ClearAllPoints")
  local anchored = works(frame, "SetPoint", "BOTTOMLEFT",
    (type(UIParent) == "table") and UIParent or nil, "BOTTOMLEFT", left, bottom)
  self.rect = { left = left, bottom = bottom, right = left + screenW, top = top }
  self.placement = placement
  self.clamped = { x = clampedX, y = clampedY }
  info.rect, info.placement = self.rect, placement
  info.clamped = clampedX or clampedY
  info.position = how

  if not anchored then
    info.skip = "panel built but it has no anchor to sit on"
    self:Hide("no anchor")
    return info
  end
  works(frame, "Show")
  self._shown = true
  self._hideReason = nil
  info.shown = true
  info.skip = nil
  return info
end

-- ── reporting ────────────────────────────────────────────────────────────
-- The rendered rows, as the player sees them ("name | value" for a drop row).
-- This is the single source of truth for the specs and for the diag's
-- "widest of our lines" figure.
function P:TextLines()
  local out = {}
  if type(self.rows) ~= "table" then
    return out
  end
  for i, row in ipairs(self.rows) do
    out[i] = row.right and (row.left .. " | " .. row.right) or row.left
  end
  return out
end

function P:Diag()
  local d = {
    created = type(self.frame) == "table",
    shown = self:IsShown(),
    rows = type(self.rows) == "table" and #self.rows or 0,
    widest = self.widest,
    widestText = self.widestText,
    width = self.width,
    height = self.height,
    cap = self.capScreen,
    font = self.fontSig,
    fontApplied = self._fontApplied,
    backdrop = self.backdropAPI,
    placement = self.placement,
    hideReason = self._hideReason,
  }
  if type(self.rect) == "table" then
    d.left, d.bottom, d.right, d.top = self.rect.left, self.rect.bottom, self.rect.right, self.rect.top
  end
  if type(self.clamped) == "table" then
    d.clampedX, d.clampedY = self.clamped.x, self.clamped.y
  end
  return d
end

function P:Reset()
  self:Hide("reset")
  self.rows = nil
  self.rect = nil
end
