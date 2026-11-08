local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

local pkg = {}
local function loadFile(path)
  local f = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path))
  f("MightiePack", pkg)
end

-- Client model (as observed in Mightie's smoke test):
--  * a repopulate of an already-visible tooltip may rewrite the content
--    directly — a C-side SetUnit / SetGameObject path that never calls the
--    Lua ClearLines method and never fires a hook the addon can wrap;
--  * a repopulate replaces content without necessarily calling Show again;
--  * while a tooltip is visible the client ticks the update clock.
loadFile("locale/enUS.lua")
loadFile("Config.lua")
loadFile("Data/Recorder.lua")
loadFile("Data/HerbData.lua")
loadFile("Data/Recipes.lua")
loadFile("UI/Tooltip.lua")

local ns = pkg.NodeTrail
local T = ns.Tooltip

time = time or os.time
CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == table and CopyTable(v) or v end return c end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
GetSpellInfo = function() return nil end
local mouseoverUnit = false
UnitExists = function(u) return u == "mouseover" and mouseoverUnit end
UIParent = {}
WorldFrame = {}

-- Private helper frames the addon may create (the v2 poller lives here).
local frames = {}
CreateFrame = function(kind, name)
  local f = { kind = kind, name = name, scripts = {}, shown = false }
  f.SetScript = function(self, n, fn) self.scripts[n] = fn end
  f.GetScript = function(self, n) return self.scripts[n] end
  f.Show = function(self) self.shown = true end
  f.Hide = function(self) self.shown = false end
  frames[#frames + 1] = f
  return f
end

local GT = {
  lines = {},
  hooks = {},
  scripts = {},
  shown = false,
  owner = UIParent,
}
GT.HookScript = function(self, name, fn)
  self.hooks[name] = self.hooks[name] or {}
  table.insert(self.hooks[name], fn)
end
GT.SetScript = function(self, name, fn) self.scripts[name] = fn end
GT.GetOwner = function(self) return self.owner end
GT.IsShown = function(self) return self.shown end
GT.Show = function(self)
  self.shown = true
  for _, fn in ipairs(self.hooks.OnShow or {}) do
    fn(self)
  end
end
GT.Hide = function(self)
  self.shown = false
  for _, fn in ipairs(self.hooks.OnHide or {}) do
    fn(self)
  end
end
GT.NumLines = function(self) return #self.lines end
GT.GetLine = function(self, i)
  local l = self.lines[i]
  if type(l) == "string" then return l end
  return nil
end
GT.AddLine = function(self, t) table.insert(self.lines, t) end
GT.AddDoubleLine = function(self, l, r) table.insert(self.lines, l .. " | " .. r) end
-- Client clear: wipes every line and deliberately does NOT fire
-- OnTooltipCleared (the behaviour this spec guards against).
GT.ClearLines = function(self)
  self.lines = {}
end
if type(GT.Clear) ~= "function" then
  GT.Clear = function(self) self.lines = {} end
end
-- Restore points for the taint guard: Enable must not swap these out.
GT.__origClearLines = GT.ClearLines
GT.__origClear = GT.Clear
GameTooltip = GT
local origGetLine = GT.GetLine -- restore point for tests that swap the stub

-- Font strings: the proven line-reading path the addon falls back to.
-- Provide a full map (title at index 1, real content at the rest) so the
-- font-string path holds the real text at any index — the title lookup and
-- the whole block are visible exactly as the lines array holds them.
local function makeFontString(i)
  local fs = { GetText = function() return GT.lines[i] end }
  -- The client's own text measurement — what the frame has to enclose. 7px per
  -- character, the same scale the client model below uses to size the frame
  -- (contentSizeOf), so a fit is measurable rather than a guess.
  fs.GetStringWidth = function()
    local t = GT.lines[i]
    return type(t) == "string" and (#t * 7) or 0
  end
  return fs
end
for _ = 1, 40 do
  local idx = _
  _G["GameTooltipTextLeft" .. idx] = makeFontString(idx)
end

-- Refresh spy: counts every time the addon evaluates a refresh, whether or
-- not it ends up a no-op. The source argument is forwarded: it decides whether
-- an append may Show the frame (event) or must stay inert (poll).
local refreshCalls = 0
local origRefresh = T.Refresh
T.Refresh = function(self, tt, source)
  refreshCalls = refreshCalls + 1
  return origRefresh(self, tt, source)
end

-- Client driver
local function clientRepopulate(name, viaApi)
  if viaApi then
    -- repopulate through the Lua API: ClearLines + new content, no
    -- OnTooltipCleared — the path the v1 fix could see.
    GT:ClearLines()
    GT:AddLine(name)
    GT:AddLine("Herbalism")
  else
    -- the C-side repopulate path: content is assigned directly, no Lua
    -- clear call, no hook — the clear the addon never sees.
    GT.lines = { name, "Herbalism" }
  end
end

local function hover(name, viaApi)
  clientRepopulate(name, viaApi)
  GT:Show()
end

local function fire(event)
  for _, fn in ipairs(GT.hooks[event] or {}) do
    fn(GT)
  end
end

-- Backstop clock: tick the addon's private poller when it exists; fall back
-- to the v1 GameTooltip OnUpdate so this spec can also run against pre-v2
-- code (where the unseen-clear tests must come out red).
local function pollTick(elapsed)
  local e = elapsed or 0.2
  local poller = T.poller
  if poller and poller.scripts and poller.scripts.OnUpdate then
    poller.scripts.OnUpdate(poller, e)
  elseif GT.scripts and GT.scripts.OnUpdate then
    GT.scripts.OnUpdate(GT, e)
  end
end

-- The block no longer opens with the addon's name (t_c2e67619), so it is
-- counted by a line every block carries exactly once and the client never
-- does: the picks line, which BuildLines always appends ("Your picks: N" or
-- "Your picks: none yet").
local function blockCount()
  local n = 0
  for _, l in ipairs(GT.lines) do
    if type(l) == "string" and l:find("^Your picks: ") then n = n + 1 end
  end
  return n
end

local function has(line)
  for _, l in ipairs(GT.lines) do
    if l == line then return true end
  end
  return false
end

-- Test 1: loading adds no hooks; Enable is idempotent (one OnShow hook)
check(GT.hooks.OnShow == nil or #GT.hooks.OnShow == 0, "Test 1: no OnShow hooks at load")
ns.Tooltip:Enable()
ns.Tooltip:Enable()
check(GT.hooks.OnShow and #GT.hooks.OnShow == 1, "Test 1: Enable idempotent — exactly one OnShow hook")
check(T.poller ~= nil, "Test 1: private poller frame created in Enable")
-- Taint guard: replacing a GameTooltip method makes Blizzard's own tooltip
-- pipeline run tainted, and the client then refuses to index secret values
-- ("execution tainted by 'MightiePack'"). Enable must leave the methods alone.
check(GT.ClearLines == GT.__origClearLines and GT.Clear == GT.__origClear,
  "Test 1: Enable never replaces GameTooltip.ClearLines/Clear (taint)")
check(GT.__ntWrappedClearLines == nil and GT.__ntWrappedClear == nil,
  "Test 1: no wrapper bookkeeping keys left on GameTooltip")
check(GT.scripts.OnUpdate == nil, "Test 1: GameTooltip keeps its own scripts (no OnUpdate clobber)")

-- Test 2: baseline hover still works (the first hover of the session)
hover("Peacebloom")
check(blockCount() == 1, "Test 2: block present exactly once on first hover")
check(has("Peacebloom | 100% (base)"), "Test 2: Peacebloom drop line present")
check(has("Your picks: none yet"), "Test 2: picks line present")

-- Test 3: the client re-populates the SAME herb (the in-game 'flash'):
-- no OnTooltipCleared, and no new Show. The block must be back exactly once.
clientRepopulate("Peacebloom", true)
pollTick()
check(has("Peacebloom | 100% (base)"), "Test 3: block self-heals after same-herb repopulate")
check(blockCount() == 1, "Test 3: block exactly once after same-herb repopulate")

-- Test 4: move to a DIFFERENT herb after a repopulate (the 'Briarthorn shows
-- nothing' symptom). New herb's block must appear, old lines must be gone.
clientRepopulate("Briarthorn", false)
pollTick()
check(has("Briarthorn | 100% (base)"), "Test 4: Briarthorn drop line present")
check(has("Swiftthistle | 10% (base)"), "Test 4: Briarthorn Swiftthistle line present")
check(not has("Peacebloom | 100%"), "Test 4: stale Peacebloom line gone")
check(blockCount() == 1, "Test 4: block exactly once after herb switch")

-- Test 5: duplicate-hook case — the same population fires the OnShow hook(s)
-- again (several hooks for one tooltip); no duplicate blocks may appear.
for _, fn in ipairs(GT.hooks.OnShow or {}) do fn(GT) end
for _, fn in ipairs(GT.hooks.OnShow or {}) do fn(GT) end
pollTick()
check(blockCount() == 1, "Test 5: no duplicate block when several hooks fire")
check(has("Briarthorn | 100% (base)"), "Test 5: Briarthorn line still present")

-- Test 6: unknown object adds nothing
hover("Stone Vein")
pollTick()
check(not has("NodeTrail"), "Test 6: unknown object adds no NodeTrail lines")
check(#GT.lines == 2, "Test 6: only client lines remain")

-- Test 7: unit tooltip still ignored, and that does not poison the next herb
mouseoverUnit = true
hover("Peacebloom")
pollTick()
check(not has("NodeTrail"), "Test 7: unit tooltip ignored")
mouseoverUnit = false
hover("Peacebloom")
check(has("Peacebloom | 100% (base)"), "Test 7: block returns on the next real herb hover")
check(blockCount() == 1, "Test 7: block exactly once")

-- Test 8: repeated clock ticks must not duplicate the block
pollTick()
pollTick()
check(blockCount() == 1, "Test 8: clock pump is idempotent")

-- Test 9: UNSEEN CLEAR — the client wipes the tooltip without going through
-- anything the addon wrapped: no ClearLines call, no clear hook, no Show.
-- Content is the truth: one poll tick must re-append the block exactly once.
check(blockCount() == 1, "Test 9: precondition — block present before unseen wipe")
GT.lines = { "Peacebloom", "Herbalism" }
check(blockCount() == 0, "Test 9: unseen wipe took our block (block gone)")
local callsBefore9 = refreshCalls
pollTick()
check(refreshCalls == callsBefore9 + 1,
  "Test 9: one recovery tick = exactly one append evaluation (a poll tick no longer re-enters: it does not Show the frame)")
check(has("Peacebloom | 100% (base)"), "Test 9: Peacebloom drop line present after unseen wipe")
check(blockCount() == 1, "Test 9: block present exactly once after one poll tick")

-- Test 10: POPULATE-EVENT FAST PATH — firing OnTooltipSetUnit /
-- OnTooltipSetItem after a client repopulate restores the block without
-- waiting for a poll tick.
GT.lines = { "Peacebloom", "Herbalism" }
check(blockCount() == 0, "Test 10: unseen wipe took our block (block gone)")
fire("OnTooltipSetUnit")
check(blockCount() == 1, "Test 10: OnTooltipSetUnit restores the block without a poll")
check(has("Peacebloom | 100% (base)"), "Test 10: block content correct after SetUnit restore")
GT.lines = { "Peacebloom", "Herbalism" }
fire("OnTooltipSetItem")
check(blockCount() == 1, "Test 10: OnTooltipSetItem restores the block without a poll")

-- Test 11: the poll must do nothing while the tooltip is hidden
check(blockCount() == 1, "Test 11: precondition — block present")
GT:Hide()
local callsBefore11 = refreshCalls
local linesBefore11 = #GT.lines
pollTick(0.2)
pollTick(0.2)
check(refreshCalls == callsBefore11, "Test 11: poll does nothing while tooltip hidden")
check(#GT.lines == linesBefore11, "Test 11: hidden — no lines change")
GT:Show()
check(blockCount() == 1, "Test 11: re-show keeps exactly one block")

-- Test 12: polling is capped at ~5x/second
local callsBefore12 = refreshCalls
for i = 1, 8 do
  pollTick(0.05)
end
check(refreshCalls == callsBefore12 + 2, "Test 12: 0.4s of ticks evaluates the refresh at most ~5x/s (exactly 2)")
check(blockCount() == 1, "Test 12: no duplicate block from throttled polls")

-- Test 13: GetLine returns a TABLE instead of line text (the likely shape if
-- this client's unverified GameTooltip:GetLine is segment-based). lineText
-- must reject the non-string and fall through to the font strings, which
-- still hold the real text — otherwise blockPresent never matches and
-- every poll tick appends another NodeTrail block.
GT.GetLine = function() return { "segments" } end
hover("Peacebloom")
check(blockCount() == 1, "Test 13: precondition — block exactly once after hover (table GetLine)")
for i = 1, 5 do pollTick() end
check(blockCount() == 1, "Test 13: table-returning GetLine — block exactly once after five poll ticks")
check(has("Peacebloom | 100% (base)"), "Test 13: Peacebloom drop line present with table GetLine")
check(has("Your picks: none yet"), "Test 13: picks line present with table GetLine")
GT.GetLine = origGetLine

-- Test 14: GetLine absent entirely — the font-string path alone must resolve
-- both the title and the block and stay idempotent across ticks.
GT.GetLine = nil
hover("Peacebloom")
check(blockCount() == 1, "Test 14: precondition — block exactly once after hover (no GetLine)")
for i = 1, 5 do pollTick() end
check(blockCount() == 1, "Test 14: missing GetLine — block exactly once via the font-string path")
check(has("Peacebloom | 100% (base)"), "Test 14: Peacebloom drop line present via font strings")
GT.GetLine = origGetLine

-- Test 15: nothing errored along the way
check(T._error == nil, "Test 15: ns.Tooltip._error == nil")

-- ─────────────────────────────────────────────────────────────────────────
-- Tests 16–21: LAYOUT (the laptop report — block shows but the backdrop
-- stops above it and the frame clips at the screen edge).
--
-- Client model, as observed in game (a build the 14c1c30 fast-path
-- comment allows that lacks the SetUnit/SetItem events): the client
-- sizes the backdrop and anchors the frame at Show, THEN fires the
-- OnShow hook — and does not re-size for late appends. This section
-- replaces the bare stub above with a client model that speaks the REAL
-- client's contract, with nothing invented:
--   * SetPoint(point, relativeTo, relativePoint, x, y)
--   * GetPoint(i) -> point, relativeTo, relativePoint, x, y   (5 values)
--   * GetLeft()/GetRight()/GetTop()/GetBottom() -> screen-space
--     edges (y-up, bottom-left origin; the parent, UIParent, spans the
--     whole screen) — the reliable measurement the addon must clamp on
--   * Show() -> sizes the frame+backdrop from the CURRENT line count,
--     then fires OnShow — the client's order, and the re-layout the
--     addon is allowed to rely on.
-- The stub deliberately has NO Layout(): it is not a verified method on
-- this client, so the addon must not depend on it — the show path is the
-- re-layout, and this section has to prove it works with none other.
local LINE_H = 16
local PAD = 10
local SCREEN_W, SCREEN_H = 1920, 1080
local NT_MARGIN = 10 -- must match MARGIN in UI/Tooltip.lua (Relayout clamp)

UIParent.GetWidth = function() return SCREEN_W end
UIParent.GetHeight = function() return SCREEN_H end
UIParent.GetName = function() return "UIParent" end

local function contentSizeOf(t)
  local w = 0
  for _, l in ipairs(t) do
    w = math.max(w, #(type(l) == "string" and l or ""))
  end
  return w * 7 + PAD, #t * LINE_H + PAD
end

-- Replaces the bare Show above: size first, then fire the OnShow hook —
-- the client's order — and count every show: the addon's re-layout must
-- drive it, and only it.
GT.sizeFromContent = function(self)
  self.fw, self.fh = contentSizeOf(self.lines)
  self.bgW, self.bgH = self.fw, self.fh
end
GT.showCalls = 0
GT.Show = function(self)
  GT.showCalls = GT.showCalls + 1
  self:sizeFromContent()
  self.shown = true
  for _, fn in ipairs(self.hooks.OnShow or {}) do
    fn(self)
  end
end
GT.GetWidth = function(self) return self.fw or 0 end
GT.GetHeight = function(self) return self.fh or 0 end
-- Resizing the frame resizes the backdrop too (it is anchored to the frame):
-- that is the panel the report says was too small for the block.
GT.SetWidth = function(self, w) self.fw = w; self.bgW = w end
GT.SetHeight = function(self, h) self.fh = h; self.bgH = h end

-- Anchor storage + the real GetPoint contract (5 values, documented
-- order): GetNumPoints / GetPoint / SetPoint behave like the real thing.
GT.points = {}
GT.SetPoint = function(self, p1, relTo, p2, x, y)
  GT.points = { { p = p1, relTo = relTo, rp = p2, x = x, y = y } }
end
GT.GetNumPoints = function(self) return #GT.points end
GT.GetPoint = function(self, i)
  local pt = GT.points[i]
  if not pt then
    return nil, nil, nil, nil, nil
  end
  return pt.p, pt.relTo, pt.rp, pt.x, pt.y
end

-- Measured screen edges — the client's own getters. The parent (UIParent)
-- spans the whole screen, so these are screen coordinates, y-up,
-- bottom-left origin — exactly what the real client returns for a
-- tooltip parented to UIParent.
local function anchorOrigin(rp)
  local ox = rp:find("RIGHT") and SCREEN_W or (rp:find("CENTER") and SCREEN_W * 0.5 or 0)
  local oy = rp:find("TOP") and SCREEN_H or (rp:find("CENTER") and SCREEN_H * 0.5 or 0)
  return ox, oy
end
local function rectOf()
  local pt = GT.points[1]
  if not pt then return nil end
  local w, h = GT.fw or 0, GT.fh or 0
  local ox, oy = anchorOrigin(pt.rp)
  local cx, cy = ox + pt.x, oy + pt.y
  return {
    left = cx - (pt.p:find("RIGHT") and w or (pt.p:find("CENTER") and w * 0.5 or 0)),
    right = cx + (pt.p:find("LEFT") and w or (pt.p:find("CENTER") and w * 0.5 or 0)),
    bottom = cy - (pt.p:find("TOP") and h or (pt.p:find("CENTER") and h * 0.5 or 0)),
    top = cy + (pt.p:find("BOTTOM") and h or (pt.p:find("CENTER") and h * 0.5 or 0)),
  }
end
GT.GetLeft = function(self) local e = rectOf() return e and e.left or nil end
GT.GetRight = function(self) local e = rectOf() return e and e.right or nil end
GT.GetTop = function(self) local e = rectOf() return e and e.top or nil end
GT.GetBottom = function(self) local e = rectOf() return e and e.bottom or nil end

-- Test 16 (contract pin, runs before the layout asserts): the stub
-- speaks the REAL Frame anchor contract. If GetPoint ever returns a
-- made-up shape again (v4's invented 7-value order), the green layout
-- runs below stop being evidence — so pin the shape right here.
local c0 = GT:GetPoint(1)
check(c0 == nil, "Test 16: unanchored frame — GetPoint(1) carries no anchor point")
GT:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 12, 34)
local cp1, crel1, crp1, cx1, cy1 = GT:GetPoint(1)
check(cp1 == "BOTTOMLEFT", "Test 16: GetPoint value 1 is the anchor point (string)")
check(crel1 == UIParent, "Test 16: GetPoint value 2 is the relativeTo frame")
check(crp1 == "BOTTOMLEFT", "Test 16: GetPoint value 3 is the relativePoint (string)")
check(cx1 == 12 and type(cx1) == "number", "Test 16: GetPoint value 4 is offsetX (number)")
check(cy1 == 34 and type(cy1) == "number", "Test 16: GetPoint value 5 is offsetY (number)")
check(select("#", GT:GetPoint(1)) == 5, "Test 16: GetPoint returns exactly 5 values, documented order")

-- Client hover at a screen mouse position: populate, anchor 16px to the
-- right/below the mouse (TOPLEFT anchor on a BOTTOMLEFT origin — the
-- client's convention), then Show (sizes the backdrop from what's in it).
local function clientHoverAt(name, mx, my)
  GT.lines = { name, "Herbalism" }
  GT:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mx + 16, SCREEN_H - my - 16)
  GT:Show()
end

-- Test 16: populate path (OnShow). The client sized the backdrop from
-- its own two lines BEFORE the hook appended ours; the addon must pull
-- the client through its own show path — exactly once — and that show
-- re-sizes the backdrop to enclose every line.
local sc16 = GT.showCalls
clientHoverAt("Peacebloom", 960, 400)
check(blockCount() == 1, "Test 16: block present after OnShow append")
check(has("Peacebloom | 100% (base)"), "Test 16: drop line present (OnShow path)")
check(GT.showCalls == sc16 + 2,
  "Test 16: hover = 1 client Show + exactly 1 addon re-layout Show (showCalls="
    .. tostring(GT.showCalls) .. ")")
check(GT.bgH ~= nil and GT.bgH >= #GT.lines * LINE_H,
  "Test 16: backdrop encloses all lines after a post-Show append (bgH="
    .. tostring(GT.bgH) .. " lines=" .. #GT.lines .. ")")

-- Test 17: late (poller) path. An unseen repopulate wipes the block; one
-- clock tick re-appends it BUT MUST NOT SHOW THE FRAME: a Show from a tick
-- re-runs the client's show path under a tooltip the client may be rewriting,
-- which is the minimap herb flash. The position is clamped, the backdrop
-- re-layout is deferred to the next real client show.
GT.lines = { "Peacebloom", "Herbalism" }
GT:sizeFromContent() -- client re-sizes what it just repopulated
local sc17 = GT.showCalls
local rb17 = refreshCalls
pollTick()
check(GT.showCalls == sc17,
  "Test 17: a poll append must NOT show the frame (flicker guard) — showCalls went "
    .. tostring(GT.showCalls - sc17))
check(refreshCalls == rb17 + 1,
  "Test 17: one recovery tick = one append evaluation, no re-entry (got "
    .. (refreshCalls - rb17) .. ")")
check(T._layoutPending == true, "Test 17: the backdrop re-layout is deferred, not dropped")
check(blockCount() == 1, "Test 17: block exactly once after late append")
-- The deferred re-layout runs on the next real client evaluation (here the
-- SetUnit fast path the client fires on a repopulate), where a Show is safe.
local sc17b = GT.showCalls
fire("OnTooltipSetUnit")
check(GT.showCalls == sc17b + 1,
  "Test 17: the deferred re-layout pulls the client through its show path exactly once on the next client evaluation")
check(T._layoutPending == false, "Test 17: the deferred re-layout is cleared once it ran")
check(GT.bgH ~= nil and GT.bgH >= #GT.lines * LINE_H,
  "Test 17: backdrop encloses all lines after the deferred re-layout (bgH="
    .. tostring(GT.bgH) .. " lines=" .. #GT.lines .. ")")
check(blockCount() == 1, "Test 17: block still exactly once after the deferred re-layout")

-- Tests 17b–17e: THE PANEL IS TOO SMALL FOR THE BLOCK (live, build 16e7954).
-- Live /nt ttdiag from the client: `last relayout: show=ran layout=no` — this
-- client has no Frame:Layout(), and its Show() does NOT re-run the padding
-- sizing. So neither the relayout nor the clamp (which measures the FRAME, not
-- the text overflowing it) can size the panel for lines appended late. The
-- panel stayed as wide as the client's own two lines and "Alchemy: Elixir of"
-- ran past the backdrop and was cut off. The frame must instead be sized from
-- the MEASURED text (GetStringWidth over the line font strings).

-- Test 17b: a poll append (the client never shows again) widens the panel to
-- the widest line plus the tooltip's own padding — and still never Shows.
GT.lines = { "Silverleaf", "Herbalism" }
GT:sizeFromContent() -- client sized the panel for its own two lines
local clientW = GT.fw
local sc17b = GT.showCalls
pollTick() -- late append, no client show afterwards
check(GT.showCalls == sc17b,
  "Test 17b: the poll append still never shows the frame (went "
    .. tostring(GT.showCalls - sc17b) .. ")")
local widest = 0
for _, l in ipairs(GT.lines) do
  if type(l) == "string" then widest = math.max(widest, #l * 7) end
end
check(widest > clientW,
  "Test 17b: precondition — our block is wider than the panel the client sized (widest="
    .. widest .. " panel=" .. tostring(clientW) .. ")")
check(GT.fw > clientW,
  "Test 17b: the panel was widened for the block (was " .. tostring(clientW)
    .. " now " .. tostring(GT.fw) .. ")")
check(GT.fw >= widest,
  "Test 17b: the panel encloses the widest line (widest=" .. widest
    .. " frame=" .. tostring(GT.fw) .. ")")
check(GT.fw == widest + PAD,
  "Test 17b: it grew by exactly the tooltip's own padding (frame=" .. tostring(GT.fw)
    .. " expected " .. (widest + PAD) .. ")")
check(GT.bgW == GT.fw, "Test 17b: the backdrop follows the frame")
check(blockCount() == 1, "Test 17b: block still exactly once")

-- Test 17c: the fit is grow-only and idempotent — a second evaluation leaves
-- the width alone (it never ratchets, and it never shrinks).
local fittedW = GT.fw
pollTick()
check(GT.fw == fittedW,
  "Test 17c: a second evaluation leaves the fitted width alone (got " .. tostring(GT.fw) .. ")")

-- Test 17d: the HEIGHT. The client's panel is shorter than the block, so the
-- tail is clipped below the frame: the last line's measured bottom sits below
-- the frame's bottom and the frame must grow by exactly that overflow.
local linesNow = #GT.lines
local lastFs = _G["GameTooltipTextLeft" .. linesNow]
check(lastFs ~= nil, "Test 17d: the last line has a font string")
local oldLastBottom = lastFs.GetBottom
local oldGetBottom = GT.GetBottom
GT.GetBottom = function() return 100 end
lastFs.GetBottom = function() return 85 end
local hBefore = GT.fh
local fitH = type(T.FitContent) == "function" and T:FitContent(GT) or nil
check(fitH and fitH.grew == true, "Test 17d: the fit grows a frame whose tail is clipped")
check(GT.fh == hBefore + 15,
  "Test 17d: ... by exactly the measured tail overflow (was " .. tostring(hBefore)
    .. " now " .. tostring(GT.fh) .. ")")
GT.GetBottom = oldGetBottom
lastFs.GetBottom = oldLastBottom

-- Test 17e: a tooltip with no NodeTrail block is never resized.
GT.lines = { "Stone Vein", "Mining" }
GT:sizeFromContent()
local miningW = GT.fw
local fitMining = type(T.FitContent) == "function" and T:FitContent(GT) or nil
check(fitMining and fitMining.ran == false,
  "Test 17e: a tooltip with no NodeTrail block is not fitted")
check(GT.fw == miningW, "Test 17e: ... and its frame is left untouched")

-- Test 17f: THE SHARP REPRO from the live client — hover a herb, leave it,
-- hover the SAME herb again. The client re-shows a tooltip sized for its OWN
-- lines (the OnShow fires before the node title is populated, so our block
-- arrives from the poll afterwards). The panel must fit on the second hover
-- exactly as it did on the first.
GT.lines = { "Silverleaf", "Herbalism", "Requires Herbalism (1)" }
local realShow = GT.Show
GT.Show = function(self) -- client show, no NodeTrail hook this time
  GT.showCalls = GT.showCalls + 1
  self:sizeFromContent()
  self.shown = true
end
GT:Show()
GT.Show = realShow
local rehoverW = GT.fw
local rehoverH = GT.fh
local widestRe
do
  local w = 0
  for _, l in ipairs(GT.lines) do
    if type(l) == "string" then w = math.max(w, #l * 7) end
  end
  widestRe = w
end
local sc17f = GT.showCalls
pollTick() -- our block arrives late on the poll
check(GT.showCalls == sc17f,
  "Test 17f: the re-hover append still never shows the frame (went "
    .. tostring(GT.showCalls - sc17f) .. ")")
check(#GT.lines > 3, "Test 17f: the block was appended on the re-hover")
check(GT.fw > rehoverW,
  "Test 17f: the panel was widened on the SECOND hover (was " .. tostring(rehoverW)
    .. " now " .. tostring(GT.fw) .. ")")
do
  local w = 0
  for _, l in ipairs(GT.lines) do
    if type(l) == "string" then w = math.max(w, #l * 7) end
  end
  check(GT.fw == w + PAD,
    "Test 17f: the second-hover panel encloses the widest line plus padding (frame="
      .. tostring(GT.fw) .. " expected " .. (w + PAD) .. ")")
end
check(rehoverH ~= nil, "Test 17f: the client sized the re-shown frame")
check(blockCount() == 1, "Test 17f: exactly one block on the second hover")

-- Test 18: bottom-right placement (the Silverleaf clip), in the card's
-- anchor shape: a BOTTOMRIGHT anchor with NON-ZERO offsets, past the
-- bottom-right corner of known screen bounds (1920x1080) — 40px beyond
-- the right edge, 30px below the bottom. The addon must land the frame
-- inside the 10px margin box — by moving the anchor, readable back
-- through the real 5-tuple with its identity intact.
GT.lines = { "Silverleaf", "Herbalism" }
GT:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 40, -30)
local sc18 = GT.showCalls
GT:Show()
check(blockCount() == 1, "Test 18: Silverleaf block present")
check(has("Silverleaf | 100% (base)"), "Test 18: Silverleaf drop line present")
check(GT.showCalls == sc18 + 2,
  "Test 18: client Show + one addon re-layout Show for the clamped append")
local r18 = rectOf()
check(r18 ~= nil, "Test 18: frame still has an anchor")
check(r18.right <= SCREEN_W and r18.left >= 0 and r18.bottom >= 0 and r18.top <= SCREEN_H,
  ("Test 18: bottom-right frame stays on screen (L=%.0f B=%.0f R=%.0f T=%.0f)"):format(r18.left, r18.bottom, r18.right, r18.top))
check(r18.right <= SCREEN_W - NT_MARGIN and r18.left >= NT_MARGIN
  and r18.bottom >= NT_MARGIN and r18.top <= SCREEN_H - NT_MARGIN,
  ("Test 18: frame inside the Relayout margin box (L=%.0f B=%.0f R=%.0f T=%.0f)"):format(r18.left, r18.bottom, r18.right, r18.top))
check(r18.right == SCREEN_W - NT_MARGIN and r18.bottom == NT_MARGIN,
  ("Test 18: clamp lands exactly on the margin-box edges (R=%s B=%s)"):format(tostring(r18.right), tostring(r18.bottom)))
-- The clamp moved the anchor — read it back through the REAL contract:
local ap18, arel18, arp18, ax18, ay18 = GT:GetPoint(1)
check(ap18 == "BOTTOMRIGHT" and arel18 == UIParent and arp18 == "BOTTOMRIGHT",
  "Test 18: anchor identity preserved by the clamp (point, relativeTo, relativePoint)")
check(ax18 == 40 - ((SCREEN_W + 40) - (SCREEN_W - NT_MARGIN)),
  "Test 18: xOffset pulled left by exactly the right-edge overflow (xOfs=" .. tostring(ax18) .. ")")
check(ay18 == -30 + (NT_MARGIN - (-30)),
  "Test 18: yOffset pulled up by exactly the bottom-edge overflow (yOfs=" .. tostring(ay18) .. ")")
check(GT.bgH ~= nil and GT.bgH >= #GT.lines * LINE_H, "Test 18: backdrop still encloses all lines")

-- Test 19: hostile re-entry. A client whose Show() first wipes and
-- re-pays content from its own source and THEN fires the OnShow hook —
-- the worst re-entry for the show-path relayout (the addon's own show
-- would discard its just-appended block). The lock + content guard must
-- still yield exactly one block, and the show calls must stay bounded
-- (no re-layout loop).
local benignShow = GT.Show
GT.Show = function(self)
  GT.showCalls = (GT.showCalls or 0) + 1
  self.lines = { "Peacebloom", "Herbalism" } -- hostile re-pay from source
  self:sizeFromContent()
  self.shown = true
  for _, fn in ipairs(self.hooks.OnShow or {}) do
    fn(self)
  end
end
local sc19 = GT.showCalls
clientHoverAt("Peacebloom", 960, 400)
check(blockCount() == 1, "Test 19: hostile Show re-firing OnShow — exactly one block")
check(GT.showCalls <= sc19 + 2,
  "Test 19: show calls bounded (client 1 + addon 1, no re-layout loop) (got " .. (GT.showCalls - sc19) .. ")")
check(has("Peacebloom | 100% (base)"), "Test 19: block content intact after hostile re-entry")
local r19 = rectOf()
check(r19 ~= nil and r19.right <= SCREEN_W and r19.left >= 0 and r19.bottom >= 0 and r19.top <= SCREEN_H,
  "Test 19: frame on screen after hostile re-entry")
GT.Show = benignShow
check(T._error == nil, "Test 19: no error recorded through the hostile path")

-- Test 20: /nt ttdiag — the only in-client evidence channel. It must
-- print the real anchor fields in the real GetPoint order (point,
-- relativeTo, relativePoint, offsetX, offsetY), the measured screen
-- edges, and the on-screen/margin verdict — wrong field order there
-- wastes the smoke test.
local chat2 = {}
local origAddMsg = DEFAULT_CHAT_FRAME.AddMessage
DEFAULT_CHAT_FRAME.AddMessage = function(self, m) chat2[#chat2 + 1] = m end
local diagOut = ""
if type(T.Diag) == "function" then
  T:Diag()
  diagOut = table.concat(chat2, "\n")
end
DEFAULT_CHAT_FRAME.AddMessage = origAddMsg
check(type(T.Diag) == "function", "Test 20: T:Diag exists")
check(diagOut:find("NumLines=", 1, true) ~= nil, "Test 20: ttdiag prints NumLines")
check(diagOut:find("point 1: TOPLEFT of UIParent BOTTOMLEFT", 1, true) ~= nil,
  "Test 20: ttdiag prints the anchor in real field order (point, relativeTo, relativePoint)")
check(diagOut:find("xOfs=976", 1, true) ~= nil, "Test 20: ttdiag prints offsetX (4th GetPoint value)")
check(diagOut:find("yOfs=664", 1, true) ~= nil, "Test 20: ttdiag prints offsetY (5th GetPoint value)")
check(diagOut:find("measured: left=", 1, true) ~= nil, "Test 20: ttdiag prints the measured screen edges")
check(diagOut:find("screen 1920x1080", 1, true) ~= nil, "Test 20: ttdiag prints the screen size + rect")
check(diagOut:find("within margin", 1, true) ~= nil, "Test 20: ttdiag prints the on-screen verdict")
check(diagOut:find("block: title=Peacebloom", 1, true) ~= nil, "Test 20: ttdiag reports the block state")
check(diagOut:find("added=", 1, true) ~= nil, "Test 20: ttdiag reports pre-/post-Show add")

-- Test 21 (final): nothing errored, including through the layout work
-- (show-path relayout, clamp, hostile re-entry, diag).
check(T._error == nil, "Test 21: ns.Tooltip._error == nil after layout tests")

-- ─────────────────────────────────────────────────────────────────────────
-- Tests 22–25: THE MINIMAP FLICKER ("it tries to give me the tooltip info but
-- it goes away super fast"). Two invariants, from the card:
--   * while the same node is hovered the block must stay put;
--   * the frame must not be hidden/re-shown on a poll tick.
-- The model is the minimap case: the tooltip is CURSOR-anchored (BOTTOMLEFT on
-- UIParent, a small positive offset), which is what a minimap tracking dot
-- produces, and the client rewrites the content under us on some ticks.
local function cursorAnchorAt(mx, my)
  GT:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", mx + 14, my + 14)
end

cursorAnchorAt(300, 700)
GT.lines = { "Peacebloom", "Herbalism" }
local sc22 = GT.showCalls
GT:Show() -- client show at the cursor
check(blockCount() == 1, "Test 22: block present on a cursor-anchored minimap hover")
check(GT.showCalls == sc22 + 2,
  "Test 22: the event path still re-layouts once (backdrop sizing is unchanged)")

-- Test 22: five poll ticks with the same node hovered and the block intact —
-- the evaluation must touch NOTHING (no Show, no clamp, no line change).
local sc22b = GT.showCalls
local lines22 = #GT.lines
for _ = 1, 5 do
  pollTick()
end
check(GT.showCalls == sc22b,
  "Test 22: five poll ticks while the same node is hovered must not show the frame (went "
    .. tostring(GT.showCalls - sc22b) .. ")")
check(#GT.lines == lines22, "Test 22: five poll ticks change no line")
check(blockCount() == 1, "Test 22: block still exactly once after five poll ticks")

-- Test 23: the same node hovered but the client rewrites the text under us on
-- every tick (the minimap's repopulate path). The block must be re-appended
-- once per rewrite and the frame must STILL not be shown from a tick.
local sc23 = GT.showCalls
for _ = 1, 5 do
  GT.lines = { "Peacebloom", "Herbalism" } -- unseen client rewrite, no Show, no hook
  pollTick()
end
check(GT.showCalls == sc23,
  "Test 23: a poll append on a rewritten tooltip must not show the frame (went "
    .. tostring(GT.showCalls - sc23) .. ")")
check(blockCount() == 1, "Test 23: exactly one block after five rewritten ticks")
check(T._layoutPending == true, "Test 23: relayout stays deferred while only ticks arrive")

-- Test 24: the ring records what actually happened. The last eight evaluations
-- must be readable and each one must carry the facts the card asks for:
-- hovered name, NumLines, whether the block was appended, whether blockIntact
-- matched, and whether Show/Clamp ran.
local ring = T.RingEntries()
check(#ring > 0, "Test 24: the refresh ring holds evaluations")
check(#ring <= 8, "Test 24: the refresh ring is bounded to the last 8 (got " .. #ring .. ")")
local sawPoll = false
local sawAppended = false
for i = 1, #ring do
  local e = ring[i]
  check(e.n ~= nil, "Test 24: ring entry " .. i .. " carries a sequence number")
  check(e.source ~= nil, "Test 24: ring entry " .. i .. " names its source")
  if e.source == "poll" then
    sawPoll = true
    check(e.show == false or e.show == nil,
      "Test 24: no poll evaluation in the ring ever showed the frame")
  end
  if e.appended then
    sawAppended = true
    check(e.name ~= nil, "Test 24: an append records the hovered node name")
    check(type(e.after) == "number", "Test 24: an append records NumLines after")
  end
end
check(sawPoll, "Test 24: the ring contains poll evaluations")
check(sawAppended, "Test 24: the ring contains appended evaluations")

-- Test 25: /nt ttdiag prints the ring — the whole point of keeping it, since
-- the flash is over before the player can type the command.
local chat3 = {}
local origAdd3 = DEFAULT_CHAT_FRAME.AddMessage
DEFAULT_CHAT_FRAME.AddMessage = function(_, m) chat3[#chat3 + 1] = m end
T:Diag()
DEFAULT_CHAT_FRAME.AddMessage = origAdd3
local diag3 = table.concat(chat3, "\n")
check(diag3:find("refresh ring:", 1, true) ~= nil, "Test 25: ttdiag prints the refresh ring block")
check(diag3:find("src=poll", 1, true) ~= nil, "Test 25: ttdiag prints the evaluation source")
check(diag3:find("intact=", 1, true) ~= nil, "Test 25: ttdiag prints the blockIntact decision")
check(diag3:find("show=", 1, true) ~= nil, "Test 25: ttdiag prints whether Show ran")
check(diag3:find("clamp=", 1, true) ~= nil, "Test 25: ttdiag prints whether Clamp ran")
check(diag3:find("appended=", 1, true) ~= nil, "Test 25: ttdiag prints whether the block was appended")
check(diag3:find("last relayout:", 1, true) ~= nil, "Test 25: ttdiag prints the last relayout")
check(diag3:find("content: frame=", 1, true) ~= nil,
  "Test 25: ttdiag prints the measured frame and widest row (the content-fit evidence)")
check(diag3:find("last fit:", 1, true) ~= nil,
  "Test 25: ttdiag prints the last fit (frame before -> after, widest, widened)")

-- Test 26 (final): still nothing errored after the flicker work.
check(T._error == nil, "Test 26: ns.Tooltip._error == nil after the flicker tests")

-- ─────────────────────────────────────────────────────────────────────────
-- Tests 27–29 (t_c2e67619): NO ADDON NAME IN THE BLOCK.
--
-- The block used to open with a "NodeTrail" header line, and that line was also
-- the marker that told Refresh "our block is still here". Both are gone: the
-- block now opens with the node name, and the marker moved to the line index +
-- first-line text + the profession line above it (see blockMarker in
-- UI/Tooltip.lua). These tests pin the two halves together — the rendered
-- block carries no addon name, AND a second hover is still recognised (no
-- second copy). They fail on 16e7954, where the header line is still there.

-- Test 27: a hover of a known herb renders no addon name, and the block starts
-- with the node name, right below the client's own profession line.
GT.lines = { "Silverleaf", "Herbalism" }
clientHoverAt("Silverleaf", 480, 300)
check(blockCount() == 1, "Test 27: exactly one block on a Silverleaf hover")
local addonNameLines = 0
for _, l in ipairs(GT.lines) do
  if l == "NodeTrail" then addonNameLines = addonNameLines + 1 end
end
check(addonNameLines == 0,
  "Test 27: no line in the tooltip reads the addon's name (got " .. addonNameLines .. ")")
local named27 = 0
for _, l in ipairs(GT.lines) do
  if type(l) == "string" and l:sub(1, #"Silverleaf") == "Silverleaf" then named27 = named27 + 1 end
end
check(named27 == 2,
  "Test 27: the node name appears twice — the client's title and our first line (got "
    .. named27 .. ")")
local start27 = T.last and T.last.start
check(type(start27) == "number", "Test 27: the append records where the block starts")
check(start27 == 3, "Test 27: the block starts right after the client's two lines (start="
  .. tostring(start27) .. ")")
check(type(GT.lines[start27]) == "string" and GT.lines[start27]:sub(1, #"Silverleaf") == "Silverleaf",
  "Test 27: the block opens with the node name (got " .. tostring(GT.lines[start27]) .. ")")
check(T.last.first == "Silverleaf",
  "Test 27: the marker records the node name as the block's first line (got "
    .. tostring(T.last.first) .. ")")
check(T.last.above == "Herbalism",
  "Test 27: the marker records the profession line above the block (got "
    .. tostring(T.last.above) .. ")")

-- Test 28: a SECOND hover of the same herb. The client rebuilds the tooltip
-- from its own two lines, so the old block is gone and exactly one fresh copy
-- is appended — not two. Then every further evaluation of that same tooltip
-- (duplicate hooks, poll ticks) appends nothing: the block is recognised by
-- its marker, which is the whole point of not needing a header line.
local picksAdded = 0
local realAddLine, realAddDouble = GT.AddLine, GT.AddDoubleLine
local function countPick(t)
  if type(t) == "string" and t:find("^Your picks: ") then picksAdded = picksAdded + 1 end
end
GT.AddLine = function(self, t) countPick(t); realAddLine(self, t) end
GT.AddDoubleLine = function(self, l, r) realAddDouble(self, l, r) end

clientHoverAt("Silverleaf", 480, 300)
check(picksAdded == 1, "Test 28: a second hover appends exactly one block (got " .. picksAdded .. ")")
check(blockCount() == 1, "Test 28: ... and the tooltip holds exactly one")
for _, fn in ipairs(GT.hooks.OnShow or {}) do fn(GT) end
for _, fn in ipairs(GT.hooks.OnShow or {}) do fn(GT) end
for _ = 1, 5 do pollTick() end
check(picksAdded == 1,
  "Test 28: re-evaluating an intact block appends nothing (got " .. picksAdded .. " appends)")
check(blockCount() == 1, "Test 28: ... still exactly one block in the tooltip")
local ring28 = T.RingEntries()
local last28 = ring28[#ring28]
check(last28 ~= nil and last28.intact == true,
  "Test 28: the latest evaluation reports the block intact")
check(last28 ~= nil and not last28.appended,
  "Test 28: ... and appended nothing")
-- The marker is not a lucky text hit: wiping the content behind our back still
-- reads as "gone" and is repaired exactly once.
GT.lines = { "Silverleaf", "Herbalism" }
pollTick()
check(picksAdded == 2, "Test 28: an unseen wipe is repaired by exactly one append (got " .. picksAdded .. ")")
check(blockCount() == 1, "Test 28: ... leaving exactly one block")
GT.AddLine, GT.AddDoubleLine = realAddLine, realAddDouble

-- Test 29: the renderer itself. BuildLines is where the block is built, so no
-- line it returns may carry the addon's name, the picks line must be untouched,
-- and an alchemy line must still lead with "Alchemy: ".
local built = T.BuildLines("Silverleaf")
check(type(built) == "table" and #built >= 2, "Test 29: BuildLines returns the block")
check(built[1] and built[1].left == "Silverleaf",
  "Test 29: the first line is the node name (got " .. tostring(built[1] and built[1].left) .. ")")
for i, l in ipairs(built) do
  check(l.left ~= "NodeTrail",
    "Test 29: line " .. i .. " carries no addon name (got " .. tostring(l.left) .. ")")
end
local picks29, alch29, alchWrong29 = false, false, false
for _, l in ipairs(built) do
  if type(l.left) == "string" and l.left:find("^Your picks: ") then picks29 = true end
  if type(l.left) == "string" and l.left:find("Alchemy", 1, true) then
    if l.left:find("^Alchemy: ") then alch29 = true else alchWrong29 = true end
  end
end
check(picks29, "Test 29: the 'Your picks:' line is untouched")
check(not alchWrong29, "Test 29: any alchemy line still leads with 'Alchemy: '")

if failed > 0 then
  os.exit(1)
else
  print("tooltip_refresh_spec: ok")
end
