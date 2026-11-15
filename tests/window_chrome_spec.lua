-- window_chrome_spec.lua — card t_2d2c37b0 (the reshape + design pass).
--
-- What this file pins, and why each is a fact rather than a restatement:
--
--   1. THE SHAPE. The window has exactly two tabs (Touchstone, Pack Settings)
--      and no third surface hiding anywhere in the frame. Herbs and Skinning
--      left with NodeTrail; they are gone, not hidden.
--   2. THE HIERARCHY. A title band across the top with one hairline under it, a
--      tab strip on the grid, and content inset from the frame by one token.
--      Every one of those numbers is READ FROM THE THEME, so a value cannot be
--      "close enough" in one file and different in another.
--   3. THE STATUS LINE. The frame states what Touchstone knows — off, waiting,
--      no data, scored, verdict — and the spec drives each state through real
--      inputs (the advisor's verdict table, its combat deferral flag, the
--      module switch) and requires the words and the dot colour to follow. A
--      status line that says "ready" when there is no data is worse than none:
--      Jeremy's product promise is "see yes, and trust it".
--   4. LIVE, NOT PAINTED ONCE. A state change followed by a tab activation
--      repaints the line. The band is a readout, not an ornament.
--   5. THE GRID. The bands and insets are the theme's; the chrome rects do not
--      overlap each other.
--
-- Not a screenshot: this is harness geometry/draw evidence. A true in-game
-- capture needs the live client (the card's OWNER-RUN / BLOCKED note).

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })
tinsert, tremove, tsort = table.insert, table.remove, table.sort
format = string.format
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local pkg = {}
local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. path .. ": " .. tostring(e))
end

MightiePackDB = { modules = { Touchstone = true }, seen = { firstRun = true }, bugCount = 0 }
StatForgeDB = { ui = { scale = 1 }, firstUse = false }

-- Load in TOC order, exactly as the client does.
local toc = assert(io.open(root .. "/MightiePack/MightiePack.toc", "r"))
local tocText = toc:read("*a")
toc:close()
local files = {}
for line in tocText:gmatch("[^\r\n]+") do
  local t = line:gsub("^%s+", ""):gsub("%s+$", "")
  if t ~= "" and not t:match("^##") then files[#files + 1] = t end
end
for _, path in ipairs(files) do loadFile(path) end

local okEnable, errEnable = pcall(pkg.EnableModules)
check(okEnable, "the enabled modules start (as they do at login): " .. tostring(errEnable))

local W = pkg.Window
local T = pkg.Theme
check(type(W) == "table" and type(T) == "table", "the window and the theme exist")
local f = W.Frame()
check(type(f) == "table", "the window frame is created")

local function rect(frame)
  return C.Rect(frame)
end
local function text(frame)
  if type(frame) ~= "table" then return nil end
  local ok, t = pcall(frame.GetText, frame)
  return ok and t or nil
end
local function findChild(parent, pred)
  local kids = parent and parent.GetChildren and parent:GetChildren() or {}
  for _, kid in ipairs(kids) do
    if pred(kid) then return kid end
  end
  return nil
end
local function findByText(parent, needle)
  local kids = parent and parent.GetChildren and parent:GetChildren() or {}
  for _, kid in ipairs(kids) do
    if type(kid) == "table" and type(kid.GetText) == "function" then
      local t = text(kid)
      if type(t) == "string" and t:find(needle, 1, true) then return kid end
    end
  end
  return nil
end

-- ── 1. THE SHAPE: two tabs, and only two ─────────────────────────────────
check(#W.TABS == 2, "the window has two outer tabs (got " .. tostring(#W.TABS) .. ")")
check(W.TABS[1] == "touchstone" and W.TABS[2] == "settings",
  "the two tabs are Touchstone then Pack Settings")
check(W.tabButtons.touchstone ~= nil and W.tabButtons.settings ~= nil,
  "both tab buttons exist")
check(W.tabButtons.herbs == nil and W.tabButtons.skinning == nil,
  "there is no Herbs or Skinning tab button left anywhere in the frame")
check(W.hosts.herbs == nil and W.hosts.skinning == nil,
  "there is no Herbs or Skinning host left anywhere in the frame")

-- ── 2. THE HIERARCHY: bands and insets from the theme ─────────────────────
local win = rect(f)
check(W.titleBar ~= nil, "the title band exists (W.titleBar)")
local band = rect(W.titleBar)
check(band.height == T.size.titleBand,
  ("the title band is the theme's height (%s, expected %s)")
    :format(tostring(band.height), tostring(T.size.titleBand)))
check(band.top == win.top and band.left == win.left and band.right == win.right,
  "the title band spans the top of the window, edge to edge")
check(T.size.titleBand % T.space.grid == 0,
  "the title band's height sits on the 8px grid")

local hairline = nil
for _, kid in ipairs(W.titleBar:GetChildren()) do
  if kid.kind == "Texture" and (kid.height or 0) == T.space.hair then hairline = kid end
end
check(hairline ~= nil, "one hairline closes the title band (a 1px rule)")
check(hairline and hairline.colorTexture ~= nil,
  "the hairline is drawn from a theme colour, not left uncoloured")

check(text(W.title) == "MightiePack",
  "the band states the pack's name (got " .. tostring(text(W.title)) .. ")")
local tr, tg, tb = T.R("text", 1)
local titler, titleg, titleb = W.title:GetTextColor()
check(titler == tr and titleg == tg and titleb == tb,
  "the name is painted with the theme's text colour")

local strip = rect(W.tabStrip)
check(strip.height == T.size.tabStrip,
  ("the tab strip is the theme's height (%s, expected %s)")
    :format(tostring(strip.height), tostring(T.size.tabStrip)))
check(strip.top == band.bottom, "the tab strip starts exactly where the band ends")

local pad = T.space.md
for _, id in ipairs(W.TABS) do
  local h = rect(W.hosts[id])
  check(math.abs(h.left - (win.left + pad)) < 0.5,
    (id .. ": the content starts one content-pad from the frame's left (%.0f vs %.0f)")
      :format(h.left, win.left + pad))
  check(math.abs(h.right - (win.right - pad)) < 0.5,
    (id .. ": the content ends one content-pad from the frame's right (%.0f vs %.0f)")
      :format(h.right, win.right - pad))
  check(math.abs(h.bottom - (win.bottom + pad)) < 0.5,
    (id .. ": the content ends one content-pad above the frame's bottom (%.0f vs %.0f)")
      :format(h.bottom, win.bottom + pad))
  check(math.abs(h.top - (strip.bottom - T.space.sm)) < 0.5,
    (id .. ": the content starts one step below the tab strip (%.0f vs %.0f)")
      :format(h.top, strip.bottom - T.space.sm))
  check(h.height % T.space.grid == 0,
    (id .. ": the content height is on the grid (%.0f)")
      :format(h.height))
end

-- Nothing in the chrome overlaps anything else in it. (Overlap is how a band
-- and a strip become one grey smear in the client.)
local chrome = { W.titleBar, W.tabStrip, W.hosts[W.TABS[1]], W.hosts[W.TABS[2]] }
for i = 1, #chrome do
  for j = i + 1, #chrome do
    -- Two content hosts share the same rect by design: only one is visible at
    -- any moment. Every pair that is actually on screen at once must not.
    local bothVisible = chrome[i]:IsShown() and chrome[j]:IsShown()
    if bothVisible then
      check(not C.Overlaps(chrome[i], chrome[j]),
        ("visible chrome rects %d and %d do not overlap"):format(i, j))
    end
  end
end
local tabs = { W.tabButtons[W.TABS[1]], W.tabButtons[W.TABS[2]] }
check(not C.Overlaps(tabs[1], tabs[2]), "the two tab buttons do not overlap")

-- ── 3. THE STATUS LINE: five real states, five honest lines ───────────────
check(W.statusText ~= nil and W.statusDot ~= nil,
  "the band carries a status dot and a status line")
check(W.statusDot.width == T.size.statusDot and W.statusDot.height == T.size.statusDot,
  "the status dot is the theme's size")
local function dotIs(token)
  local r, g, b, a = T.R(token)
  local got = W.statusDot.colorTexture
  if type(got) ~= "table" then return false end
  return got[1] == r and got[2] == g and got[3] == b and got[4] == a
end

local CA = rawget(_G, "ChestAdvisor")
check(type(CA) == "table", "precondition: the Touchstone body loaded (ChestAdvisor)")
local realGet = CA and CA.getVerdicts
local realEnabled = pkg.IsModuleEnabled

-- State: no data.
CA.getVerdicts = function() return {} end
CA._scanDeferred = nil
W.PaintStatus()
check(W.statusText:GetText() == "No verdicts yet — open your bags",
  "no verdicts: the line says so (got " .. tostring(W.statusText:GetText()) .. ")")
check(dotIs("dotEmpty"), "no verdicts: the dot is the muted 'nothing yet' colour")

-- State: verdicts present (2 upgrades, 1 trade-off, 6 unchanged).
CA.getVerdicts = function()
  return {
    a = { verdict = "UPGRADE" }, b = { verdict = "UPGRADE" },
    c = { verdict = "TRADE_OFF" },
    d = { verdict = "NOT_UPGRADE" }, e = { verdict = "NOT_UPGRADE" },
    f = { verdict = "NOT_UPGRADE" }, g = { verdict = "NOT_UPGRADE" },
    h = { verdict = "NOT_UPGRADE" }, i = { verdict = "NOT_UPGRADE" },
  }
end
W.PaintStatus()
check(W.statusText:GetText() == "2 upgrades · 1 trade-off · 9 items scored",
  "verdicts present: the line counts them honestly (got "
    .. tostring(W.statusText:GetText()) .. ")")
check(dotIs("dotVerdict"), "verdicts present: the dot is the success colour")
check(W.status and W.status.state == "verdict", "the state key is 'verdict'")

-- State: scored, and none of them a change. Saying "ready" here would be the
-- polite lie the card forbids.
CA.getVerdicts = function()
  return { a = { verdict = "NOT_UPGRADE" }, b = { verdict = "NOT_UPGRADE" },
           c = { verdict = "NOT_UPGRADE" } }
end
W.PaintStatus()
check(W.statusText:GetText() == "3 items scored · no change",
  "scored with no upgrades: the line says 'no change' (got "
    .. tostring(W.statusText:GetText()) .. ")")
check(dotIs("dotScored"), "scored with no upgrades: the dot is the calm accent")

-- State: a scan was deferred by combat (the advisor's only in-flight signal).
CA._scanDeferred = true
W.PaintStatus()
check(W.statusText:GetText() == "Scan waits for combat to end",
  "a deferred scan says it is waiting (got " .. tostring(W.statusText:GetText()) .. ")")
check(dotIs("dotWaiting"), "a deferred scan warns rather than claims progress")
CA._scanDeferred = nil

-- State: the module is off.
pkg.IsModuleEnabled = function(name) return name ~= "Touchstone" end
W.PaintStatus()
check(W.statusText:GetText() == "Touchstone off — see Pack Settings",
  "module off: the line points at the switch (got " .. tostring(W.statusText:GetText()) .. ")")
check(dotIs("dotOff"), "module off: the dot is dim, not a warning")
pkg.IsModuleEnabled = realEnabled

-- ── 4. LIVE, NOT PAINTED ONCE ────────────────────────────────────────────
CA.getVerdicts = function() return { only = { verdict = "UPGRADE" } } end
W.SelectTab("settings")
W.SelectTab("touchstone")
check(W.statusText:GetText() == "1 upgrade · 1 item scored",
  "activating the tab repaints the line from live state (got "
    .. tostring(W.statusText:GetText()) .. ") — singular forms are not '1 upgrades'")

-- A refresh (bag open, rescan) repaints too, without a tab switch.
CA.getVerdicts = function() return {} end
local SF = rawget(_G, "StatForge")
if type(SF) == "table" and type(SF.RefreshActiveTab) == "function" then
  pcall(SF.RefreshActiveTab)
  check(W.statusText:GetText() == "No verdicts yet — open your bags",
    "a vendored refresh repaints the status line (got "
      .. tostring(W.statusText:GetText()) .. ")")
else
  check(false, "the Touchstone seam is in place (SF.RefreshActiveTab)")
end

-- Restore the body's real function for anything loaded after this point.
if CA and realGet then CA.getVerdicts = realGet end

-- ── 5. THE BAND IS NOT PART OF THE CONTENT ───────────────────────────────
-- The title band is chrome: it must not be inside a content host, or a body
-- reparented into that host would be laid out under it.
for _, id in ipairs(W.TABS) do
  local host = W.hosts[id]
  local parent = W.titleBar and W.titleBar:GetParent()
  check(parent == f, "the title band hangs off the window frame itself")
  check(host ~= parent, "the title band is not inside the " .. id .. " host")
end

if failed == 0 then
  print("window_chrome_spec: ok")
else
  print(("window_chrome_spec: %d failure(s)"):format(failed))
  os.exit(1)
end
