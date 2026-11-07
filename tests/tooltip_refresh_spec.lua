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
GameTooltip = GT
local origGetLine = GT.GetLine -- restore point for tests that swap the stub

-- Font strings: the proven line-reading path the addon falls back to.
-- Provide a full map (title at index 1, real content at the rest) so the
-- font-string path holds the real text at any index — the title lookup and
-- the whole block are visible exactly as the lines array holds them.
local function makeFontString(i)
  return { GetText = function() return GT.lines[i] end }
end
for _ = 1, 40 do
  local idx = _
  _G["GameTooltipTextLeft" .. idx] = makeFontString(idx)
end

-- Refresh spy: counts every time the addon evaluates a refresh, whether or
-- not it ends up a no-op.
local refreshCalls = 0
local origRefresh = T.Refresh
T.Refresh = function(self, tt)
  refreshCalls = refreshCalls + 1
  return origRefresh(self, tt)
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

local function headerCount()
  local n = 0
  for _, l in ipairs(GT.lines) do
    if l == "NodeTrail" then n = n + 1 end
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
check(GT.scripts.OnUpdate == nil, "Test 1: GameTooltip keeps its own scripts (no OnUpdate clobber)")

-- Test 2: baseline hover still works (the first hover of the session)
hover("Peacebloom")
check(headerCount() == 1, "Test 2: header present exactly once on first hover")
check(has("Peacebloom | 100% (base)"), "Test 2: Peacebloom drop line present")
check(has("Your picks: none yet"), "Test 2: picks line present")

-- Test 3: the client re-populates the SAME herb (the in-game 'flash'):
-- no OnTooltipCleared, and no new Show. The block must be back exactly once.
clientRepopulate("Peacebloom", true)
pollTick()
check(has("Peacebloom | 100% (base)"), "Test 3: block self-heals after same-herb repopulate")
check(headerCount() == 1, "Test 3: header exactly once after same-herb repopulate")

-- Test 4: move to a DIFFERENT herb after a repopulate (the 'Briarthorn shows
-- nothing' symptom). New herb's block must appear, old lines must be gone.
clientRepopulate("Briarthorn", false)
pollTick()
check(has("Briarthorn | 100% (base)"), "Test 4: Briarthorn drop line present")
check(has("Swiftthistle | 10% (base)"), "Test 4: Briarthorn Swiftthistle line present")
check(not has("Peacebloom | 100%"), "Test 4: stale Peacebloom line gone")
check(headerCount() == 1, "Test 4: header exactly once after herb switch")

-- Test 5: duplicate-hook case — the same population fires the OnShow hook(s)
-- again (several hooks for one tooltip); no duplicate headers may appear.
for _, fn in ipairs(GT.hooks.OnShow or {}) do fn(GT) end
for _, fn in ipairs(GT.hooks.OnShow or {}) do fn(GT) end
pollTick()
check(headerCount() == 1, "Test 5: no duplicate header when several hooks fire")
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
check(headerCount() == 1, "Test 7: header exactly once")

-- Test 8: repeated clock ticks must not duplicate the block
pollTick()
pollTick()
check(headerCount() == 1, "Test 8: clock pump is idempotent")

-- Test 9: UNSEEN CLEAR — the client wipes the tooltip without going through
-- anything the addon wrapped: no ClearLines call, no clear hook, no Show.
-- Content is the truth: one poll tick must re-append the block exactly once.
check(headerCount() == 1, "Test 9: precondition — block present before unseen wipe")
GT.lines = { "Peacebloom", "Herbalism" }
check(headerCount() == 0, "Test 9: unseen wipe took our block (header gone)")
local callsBefore9 = refreshCalls
pollTick()
check(refreshCalls == callsBefore9 + 1, "Test 9: one poll tick evaluated a refresh")
check(has("Peacebloom | 100% (base)"), "Test 9: Peacebloom drop line present after unseen wipe")
check(headerCount() == 1, "Test 9: header present exactly once after one poll tick")

-- Test 10: POPULATE-EVENT FAST PATH — firing OnTooltipSetUnit /
-- OnTooltipSetItem after a client repopulate restores the block without
-- waiting for a poll tick.
GT.lines = { "Peacebloom", "Herbalism" }
check(headerCount() == 0, "Test 10: unseen wipe took our block (header gone)")
fire("OnTooltipSetUnit")
check(headerCount() == 1, "Test 10: OnTooltipSetUnit restores the block without a poll")
check(has("Peacebloom | 100% (base)"), "Test 10: block content correct after SetUnit restore")
GT.lines = { "Peacebloom", "Herbalism" }
fire("OnTooltipSetItem")
check(headerCount() == 1, "Test 10: OnTooltipSetItem restores the block without a poll")

-- Test 11: the poll must do nothing while the tooltip is hidden
check(headerCount() == 1, "Test 11: precondition — block present")
GT:Hide()
local callsBefore11 = refreshCalls
local linesBefore11 = #GT.lines
pollTick(0.2)
pollTick(0.2)
check(refreshCalls == callsBefore11, "Test 11: poll does nothing while tooltip hidden")
check(#GT.lines == linesBefore11, "Test 11: hidden — no lines change")
GT:Show()
check(headerCount() == 1, "Test 11: re-show keeps exactly one header")

-- Test 12: polling is capped at ~5x/second
local callsBefore12 = refreshCalls
for i = 1, 8 do
  pollTick(0.05)
end
check(refreshCalls == callsBefore12 + 2, "Test 12: 0.4s of ticks evaluates the refresh at most ~5x/s (exactly 2)")
check(headerCount() == 1, "Test 12: no duplicate header from throttled polls")

-- Test 13: GetLine returns a TABLE instead of line text (the likely shape if
-- this client's unverified GameTooltip:GetLine is segment-based). lineText
-- must reject the non-string and fall through to the font strings, which
-- still hold the real text — otherwise headerPresent never matches and
-- every poll tick appends another NodeTrail block.
GT.GetLine = function() return { "NodeTrail" } end
hover("Peacebloom")
check(headerCount() == 1, "Test 13: precondition — header exactly once after hover (table GetLine)")
for i = 1, 5 do pollTick() end
check(headerCount() == 1, "Test 13: table-returning GetLine — header exactly once after five poll ticks")
check(has("Peacebloom | 100% (base)"), "Test 13: Peacebloom drop line present with table GetLine")
check(has("Your picks: none yet"), "Test 13: picks line present with table GetLine")
GT.GetLine = origGetLine

-- Test 14: GetLine absent entirely — the font-string path alone must resolve
-- both the title and the header and stay idempotent across ticks.
GT.GetLine = nil
hover("Peacebloom")
check(headerCount() == 1, "Test 14: precondition — header exactly once after hover (no GetLine)")
for i = 1, 5 do pollTick() end
check(headerCount() == 1, "Test 14: missing GetLine — header exactly once via the font-string path")
check(has("Peacebloom | 100% (base)"), "Test 14: Peacebloom drop line present via font strings")
GT.GetLine = origGetLine

-- Test 15: nothing errored along the way
check(T._error == nil, "Test 15: ns.Tooltip._error == nil")

-- ─────────────────────────────────────────────────────────────────────────
-- Tests 16–21: LAYOUT (the laptop report — block shows but the backdrop
-- stops above it and the frame clips at the screen edge).
--
-- Client model, as observed in game (14c1c30's own fast-path comment
-- allows builds that lack the SetUnit/SetItem events): the client sizes
-- the backdrop and anchors the frame at Show, THEN fires the OnShow
-- hook. So every append in that flow is a post-layout append, and the
-- addon must re-layout itself on append. The stub below models exactly
-- that: Show freezes frame size + backdrop rect from the CURRENT line
-- count; Layout() recomputes both (the client's own re-layout); the
-- frame carries a real screen anchor on a finite UIParent.
local LINE_H = 16
local PAD = 10
local SCREEN_W, SCREEN_H = 1920, 1080
local NT_MARGIN = 10 -- must match MARGIN in UI/Tooltip.lua (Relayout clamp)

UIParent.GetWidth = function() return SCREEN_W end
UIParent.GetHeight = function() return SCREEN_H end

local function contentSizeOf(t)
  local w = 0
  for _, l in ipairs(t) do
    w = math.max(w, #(type(l) == "string" and l or ""))
  end
  return w * 7 + PAD, #t * LINE_H + PAD
end

-- Replaces the bare Show above (tests 2–15 already ran and observe no
-- sizing): size first, then fire the OnShow hook — the client's order.
GT.sizeFromContent = function(self)
  self.fw, self.fh = contentSizeOf(self.lines)
  self.bgW, self.bgH = self.fw, self.fh
end
GT.Show = function(self)
  self.shown = true
  self:sizeFromContent()
  for _, fn in ipairs(self.hooks.OnShow or {}) do
    fn(self)
  end
end
GT.Layout = function(self)
  self.layoutCalls = (self.layoutCalls or 0) + 1
  self:sizeFromContent()
end
GT.GetWidth = function(self) return self.fw or 0 end
GT.GetHeight = function(self) return self.fh or 0 end
GT.point = nil
GT.numPoints = 0
GT.SetPoint = function(self, p1, relTo, p2, x, y)
  GT.point = { p1 = p1, relTo = relTo, p2 = p2, x = x, y = y }
  GT.numPoints = 1
end
GT.GetNumPoints = function(self) return GT.numPoints end
GT.GetPoint = function(self, i)
  if not GT.point or GT.numPoints < i then
    return nil, nil, nil, nil, nil, nil, nil
  end
  local p = GT.point
  return 0, 0, p.x, p.y, p.relTo, p.p1, p.p2
end

-- Client hover at a screen mouse position: populate, anchor 16px to the
-- right/below the mouse, then Show (sizes backdrop from what is in it).
local function clientHoverAt(name, mx, my)
  GT.lines = { name, "Herbalism" }
  GT:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mx + 16, SCREEN_H - my - 16)
  GT:Show()
end

-- Screen-space rect from the stub's raw anchor (y-up, bottom-left
-- origin): left, bottom, right, top — independent re-implementation of
-- what Relayout does internally.
local function rectOf()
  if not GT.point then return nil, nil, nil, nil end
  local p = GT.point
  local w, h = GT:GetWidth(), GT:GetHeight()
  local ox = p.p2:find("RIGHT") and SCREEN_W or (p.p2:find("CENTER") and SCREEN_W * 0.5 or 0)
  local oy = p.p2:find("TOP") and SCREEN_H or (p.p2:find("CENTER") and SCREEN_H * 0.5 or 0)
  local cx, cy = ox + p.x, oy + p.y
  local left = cx - (p.p1:find("RIGHT") and w or (p.p1:find("CENTER") and w * 0.5 or 0))
  local right = cx + (p.p1:find("LEFT") and w or (p.p1:find("CENTER") and w * 0.5 or 0))
  local bottom = cy - (p.p1:find("TOP") and h or (p.p1:find("CENTER") and h * 0.5 or 0))
  local top = cy + (p.p1:find("BOTTOM") and h or (p.p1:find("CENTER") and h * 0.5 or 0))
  return left, bottom, right, top
end

-- Test 16: populate path (OnShow). The client sized the backdrop from
-- its own two lines BEFORE the hook appended ours; the addon's
-- post-append re-layout must grow it to enclose every line.
clientHoverAt("Peacebloom", 960, 400)
check(headerCount() == 1, "Test 16: block present after OnShow append")
check(has("Peacebloom | 100% (base)"), "Test 16: drop line present (OnShow path)")
check(GT.bgH ~= nil and GT.bgH >= #GT.lines * LINE_H,
  "Test 16: backdrop encloses all lines after a post-Show append (bgH="
    .. tostring(GT.bgH) .. " lines=" .. #GT.lines .. ")")

-- Test 17: late (poller) path. Unseen repopulate wipes the block; one
-- clock tick re-appends it — that append must force the client's own
-- re-layout, and the resulting backdrop must enclose every line.
GT.lines = { "Peacebloom", "Herbalism" }
GT:sizeFromContent() -- client re-sizes what it just repopulated
local lcBefore = GT.layoutCalls or 0
local rbBefore = refreshCalls
pollTick()
check(refreshCalls == rbBefore + 1, "Test 17: one poll tick evaluated a refresh")
check((GT.layoutCalls or 0) == lcBefore + 1, "Test 17: late append forced exactly one client re-layout")
check(GT.bgH ~= nil and GT.bgH >= #GT.lines * LINE_H,
  "Test 17: backdrop encloses all lines after late append (bgH="
    .. tostring(GT.bgH) .. " lines=" .. #GT.lines .. ")")
check(headerCount() == 1, "Test 17: header exactly once after late re-layout")

-- Test 18: bottom-right placement (the Silverleaf clip). The frame must
-- shift to stay on the screen instead of spilling off the right/bottom.
clientHoverAt("Silverleaf", 1880, 60)
local l, b, r, t = rectOf()
check(l ~= nil, "Test 18: frame still has an anchor")
check(l >= 0 and b >= 0 and r <= SCREEN_W and t <= SCREEN_H,
  ("Test 18: bottom-right frame stays on screen (L=%.0f B=%.0f R=%.0f T=%.0f)"):format(l, b, r, t))
check(l >= NT_MARGIN and b >= NT_MARGIN and r <= SCREEN_W - NT_MARGIN and t <= SCREEN_H - NT_MARGIN,
  "Test 18: frame inside the Relayout margin box")
check(headerCount() == 1, "Test 18: Silverleaf block present")
check(has("Silverleaf | 100% (base)"), "Test 18: Silverleaf drop line present")
check(GT.bgH ~= nil and GT.bgH >= #GT.lines * LINE_H, "Test 18: backdrop still encloses all lines")

-- Test 19: hostile re-entry. A client whose Layout() re-fires the OnShow
-- hook must not produce an append loop or duplicate headers. (The hostile
-- wrapper re-fires the hook and delegates the increment/resize to the
-- base Layout, so one call still counts as one layout.)
local origLayout = GT.Layout
GT.Layout = function(self)
  origLayout(self)
  for _, fn in ipairs(self.hooks.OnShow or {}) do
    fn(self)
  end
end
clientHoverAt("Peacebloom", 960, 400)
check(headerCount() == 1, "Test 19: hostile Layout re-firing OnShow — exactly one header")
check((GT.layoutCalls or 0) <= 4, "Test 19: re-layout calls bounded (no hook loop)")
check(has("Peacebloom | 100% (base)"), "Test 19: block content intact after hostile re-entry")
local l19, b19, r19, t19 = rectOf()
check(l19 >= 0 and b19 >= 0 and r19 <= SCREEN_W and t19 <= SCREEN_H, "Test 19: frame on screen after hostile re-entry")
GT.Layout = origLayout

-- Test 20: /nt ttdiag — while the tooltip is shown it reports the live
-- layout state (NumLines, anchor points, screen rect, pre-/post-Show).
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
check(diagOut:find("point 1:", 1, true) ~= nil, "Test 20: ttdiag prints the anchor point")
check(diagOut:find("screen 1920x1080", 1, true) ~= nil, "Test 20: ttdiag prints screen size + rect")
check(diagOut:find("block: title=Peacebloom", 1, true) ~= nil, "Test 20: ttdiag reports the block state")
check(diagOut:find("added=", 1, true) ~= nil, "Test 20: ttdiag reports pre-/post-Show add")

-- Test 21 (final): nothing errored, including through the layout work
-- (re-layout, clamp, hostile re-entry, diag).
check(T._error == nil, "Test 21: ns.Tooltip._error == nil after layout tests")

if failed > 0 then
  os.exit(1)
else
  print("tooltip_refresh_spec: ok")
end
