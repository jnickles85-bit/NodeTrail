-- window_strata_spec.lua — the draw ORDER inside the one window, as a structure.
--
-- Card t_5d0cc41a. The owner saw the Touchstone tab uniformly dim — header,
-- inner strip and item list — while Herbs, Skinning and Pack Settings were at
-- full brightness, with every alpha reading 1.00. Nothing was faded and nothing
-- covered the body. He measured the order instead:
--
--   P1 StatForgeMainFrame   alpha 1  level 3  strata MEDIUM   <-- the body
--   P2 MightiePackWindow    alpha 1  level 2  strata DIALOG   <-- the fill was HERE
--   TS MEDIUM   OPT DIALOG   WIN DIALOG
--
-- Strata beats frame level outright, and the window painted its own 0.96 fill
-- on the frame that also carried DIALOG. So the fill drew OVER the whole body.
-- The covering-frame detectors could never see it: the culprit is an ANCESTOR,
-- and an ancestor is excluded from "what draws over me" by definition.
--
-- The fix (option A, approved by the owner) is structural: the fill gets its
-- own frame at BACKGROUND, so the window's ordering becomes
--
--     fill (BACKGROUND)  <  content (MEDIUM)  <  chrome (DIALOG)
--
-- and any future reparented body at MEDIUM is correct without its own strata
-- hack. This file pins the STRUCTURE, not the instance:
--
--   1. THE FILL IS ITS OWN FRAME: BACKGROUND strata, SetAllPoints(window), the
--      same dark 0.96 it always painted, and — load-bearing — `EnableMouse(true)`
--      (card t_cdee6bb6). The fill is the LOWEST layer, so content and chrome
--      still win the hit test over it; what it catches is the click on empty
--      window area, which must not fall through to the camera. It was mouse-off
--      on t_5d0cc41a only because the WINDOW frame was still mouse-enabled and
--      caught that click itself — and that same window frame, in DIALOG, was
--      eating every click over the MEDIUM Touchstone body. See
--      tests/window_inner_input_spec.lua for the input half, measured.
--   2. THE CHROME FRAME PAINTS NO FILL. A backdrop fill on the DIALOG frame is
--      the defect itself, whatever colour it is; the border stays.
--   3. THE ORDER: fill < content < chrome, by strata rank, and the body stays
--      at MEDIUM so it can never climb into the chrome and cover the tabs.
--   4. NOTHING LOSES TO STRATA: the live tree has no frame drawn under an
--      ancestor's fill, and no reparent recorded one at the moment of the move.
--   5. THE MODEL CAN FAIL: a MEDIUM frame moved under a DIALOG parent's fill is
--      named, the move is recorded, and moving that fill to a BACKGROUND frame
--      clears it. Then the fill goes back on the DIALOG frame and the model must
--      name it again — a check that cannot fail is not evidence.
--   6. THE FILL DOES NOT OWN THE MOUSE: every tab still receives its own click
--      and the fill is not the frame under a point over the body.
--
-- Harness: tests/support/wowclient.lua, extended on this card so an explicit
-- strata is honoured as written and compared against the parent on SetParent
-- (`C.StrataCover`, `C.ZOrderHazards`, `C.reparentHazards`). Level alone is the
-- weaker ordering and it is what let a green suite ship this defect twice.

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
-- The client's convenience globals, which the harness does not model.
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

-- The owner's live state, reduced to the keys that matter: both modules on,
-- Touchstone used before (so no first-use splash is in play at all).
MightiePackDB = { modules = { NodeTrail = true, Touchstone = true }, seen = { firstRun = true }, bugCount = 0 }
NodeTrailDB = {
  schema = 2,
  herbs = { schema = 2, total = 0, maps = {}, mapTotals = {}, stats = { gathers = {}, co = {}, names = {} }, hotspots = {}, folded = {} },
  skinning = { enabled = true, schema = 2, chars = {} },
  route = {},
}
StatForgeDB = { ui = { scale = 1 }, firstUse = false }

-- Load in TOC order, exactly as the client does.
local tocPath = root .. "/MightiePack/MightiePack.toc"
local toc = assert(io.open(tocPath, "r"), "cannot open " .. tocPath)
local tocText = toc:read("*a")
toc:close()
local files = {}
for line in tocText:gmatch("[^\r\n]+") do
  local t = line:gsub("^%s+", ""):gsub("%s+$", "")
  if t ~= "" and not t:match("^##") then files[#files + 1] = t end
end
check(#files > 0, "the TOC lists files")
for _, f in ipairs(files) do loadFile(f) end

local okEnable, errEnable = pcall(pkg.EnableModules)
check(okEnable, "the enabled modules start (as they do at login): " .. tostring(errEnable))

local W = pkg.Window
check(type(W) == "table", "pkg.Window exists")
local win = W.Frame()
check(type(win) == "table", "the window frame is created")
check(W.Open("touchstone") == true, "the window opens on the touchstone tab")

local host = W.hosts and W.hosts.touchstone
check(type(host) == "table", "the touchstone host exists")
local body = rawget(_G, "StatForgeMainFrame")
check(type(body) == "table" and body:GetParent() == host,
  "the Touchstone body is parented into the touchstone host")

-- ── 1. THE FILL IS ITS OWN FRAME, AT BACKGROUND, AND NOT CLICKABLE ─────────
local bg = W.bg
check(type(bg) == "table", "the window's fill lives on its own frame (W.bg)")
if type(bg) == "table" then
  check(bg:GetName() == "MightiePackWindowBackground",
    "the fill frame is NAMED, so the owner's strata read can see it by name (got "
      .. tostring(bg:GetName()) .. ")")
  check(bg:GetFrameStrata() == "BACKGROUND",
    "the fill frame is on BACKGROUND strata (got " .. tostring(bg:GetFrameStrata()) .. ")")
  check(bg:IsMouseEnabled() == true,
    "the fill frame IS mouse-enabled — it is the lowest layer and owns only the "
      .. "clicks on empty window area, which must not fall through to the camera "
      .. "(card t_cdee6bb6)")
  local rw, rf = C.Rect(win), C.Rect(bg)
  local same = math.abs(rw.left - rf.left) < 0.5 and math.abs(rw.right - rf.right) < 0.5
    and math.abs(rw.top - rf.top) < 0.5 and math.abs(rw.bottom - rf.bottom) < 0.5
  check(same, ("the fill frame covers exactly the window (SetAllPoints; window %.0f..%.0f x %.0f..%.0f, fill %.0f..%.0f x %.0f..%.0f)")
    :format(rw.left, rw.right, rw.top, rw.bottom, rf.left, rf.right, rf.top, rf.bottom))
  local alpha = C.FillAlpha(bg)
  check(alpha ~= nil and math.abs(alpha - 0.96) < 0.001,
    "the fill still paints the window's own 0.96 dark backdrop (alpha "
      .. tostring(alpha) .. ") — the colour and alpha did not change, only the frame")
  local bd = bg:GetBackdrop() or {}
  check(type(bd.bgFile) == "string" and bd.bgFile:upper():find("WHITE8X8", 1, true) ~= nil,
    "the fill uses the texture that resolves on this client (WHITE8X8), got "
      .. tostring(bd.bgFile))
  local r, g, b = bg:GetBackdropColor()
  check(type(r) == "number" and math.abs(r - 0.06) < 0.01
      and type(g) == "number" and math.abs(g - 0.06) < 0.01
      and type(b) == "number" and math.abs(b - 0.07) < 0.01,
    ("the fill is the same dark colour as before (%.2f %.2f %.2f)")
      :format(tonumber(r) or -1, tonumber(g) or -1, tonumber(b) or -1))
else
  check(false, "without W.bg the fill is back on the window frame, in DIALOG")
end

-- ── 2. THE CHROME FRAME PAINTS NO FILL ────────────────────────────────────
check(C.FillAlpha(win) == nil,
  "the window frame paints NO fill of its own: a fill on the DIALOG frame is the "
    .. "defect itself, whatever its colour (fill alpha " .. tostring(C.FillAlpha(win)) .. ")")
local wbd = win:GetBackdrop() or {}
check(type(wbd.edgeFile) == "string" and wbd.edgeFile ~= "",
  "the window keeps its border texture (" .. tostring(wbd.edgeFile) .. ")")

-- ── 3. THE ORDER: fill < content < chrome ─────────────────────────────────
if type(bg) == "table" then
  local fillRank = C.StrataRank(bg:GetFrameStrata())
  local contentRank = C.StrataRank(body:GetFrameStrata())
  local chromeRank = C.StrataRank(win:GetFrameStrata())
  check(fillRank < contentRank,
    "the fill sits BELOW the content (" .. bg:GetFrameStrata() .. " < "
      .. body:GetFrameStrata() .. ")")
  check(contentRank < chromeRank,
    "the content sits BELOW the chrome (" .. body:GetFrameStrata() .. " < "
      .. win:GetFrameStrata() .. ")")
  check(body:GetFrameStrata() == "MEDIUM",
    "the body stays on MEDIUM — it must not climb into the chrome and cover the "
      .. "tab row or the close button (got " .. tostring(body:GetFrameStrata()) .. ")")
  check(C.DrawsAbove(body, bg), "the Touchstone body draws above the fill")
  print(("strata: fill %s(%d) < content %s(%d) < chrome %s(%d)")
    :format(bg:GetFrameStrata(), fillRank, body:GetFrameStrata(), contentRank,
      win:GetFrameStrata(), chromeRank))
end

-- ── 4. NOTHING IN THE PACK LOSES TO STRATA ────────────────────────────────
local hazards = C.ZOrderHazards()
check(#hazards == 0,
  "no frame in the pack draws under an ancestor's fill (got " .. #hazards .. ": "
    .. C.DescribeZOrderHazards() .. ")")
check(C.StrataCover(body) == nil,
  "the Touchstone body does not lose to any ancestor's strata")
check(#C.reparentHazards == 0,
  "no reparent put a frame under a covering fill (recorded at the move: "
    .. #C.reparentHazards .. ")")

-- ── 5. THE MODEL CAN FAIL ─────────────────────────────────────────────────
-- Build the exact shape of 58118b0 outside the pack: a DIALOG parent that
-- paints a fill, and a MEDIUM body moved into it. If the model cannot name
-- this, leg 4 going green proves nothing.
do
  local zHost = CreateFrame("Frame", "SpecZHost", UIParent)
  zHost:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  zHost:SetSize(400, 300)
  zHost:SetFrameStrata("DIALOG")
  zHost:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  zHost:SetBackdropColor(0.06, 0.06, 0.07, 0.96)

  local zBody = CreateFrame("Frame", "SpecZBody", UIParent)
  zBody:SetSize(380, 280)
  zBody:SetFrameStrata("MEDIUM")
  zBody:SetPoint("CENTER", zHost, "CENTER", 0, 0)

  local recordedBefore = #C.reparentHazards
  zBody:SetParent(zHost)
  local hazard = C.StrataCover(zBody)
  check(hazard ~= nil and hazard.host == zHost,
    "the model names a MEDIUM frame moved under a DIALOG parent's fill (got "
      .. (hazard and hazard.hostStrata or "nothing") .. ")")
  check(hazard ~= nil and hazard.strata == "MEDIUM" and hazard.fillAlpha > 0.9,
    "and it reports the strata it lost to and the alpha that covers it")
  check(#C.reparentHazards == recordedBefore + 1,
    "SetParent records the strata comparison at the moment of the move (recorded "
      .. (#C.reparentHazards - recordedBefore) .. ")")

  -- The fix's shape: border-only chrome, fill on a BACKGROUND child.
  zHost:SetBackdrop({
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  local zFill = CreateFrame("Frame", "SpecZFill", zHost, "BackdropTemplate")
  zFill:SetAllPoints(zHost)
  zFill:SetFrameStrata("BACKGROUND")
  zFill:EnableMouse(false)
  zFill:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    tile = true, tileSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  zFill:SetBackdropColor(0.06, 0.06, 0.07, 0.96)
  check(C.StrataCover(zBody) == nil,
    "with the fill moved to a BACKGROUND child the same tree is clean (got "
      .. tostring(C.StrataCover(zBody) and C.StrataCover(zBody).hostStrata) .. ")")
  check(C.DrawsAbove(zBody, zFill), "the body draws above the moved fill")

  -- Teeth: put the fill back on the DIALOG frame and the model must name it
  -- again. This is the regression leg — it is the change that would re-create
  -- the dimmed tab.
  zHost:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  zHost:SetBackdropColor(0.06, 0.06, 0.07, 0.96)
  local again = C.StrataCover(zBody)
  check(again ~= nil and again.host == zHost,
    "putting the fill back on the DIALOG frame is named again — the check has teeth")

  zBody:SetParent(nil)
  zFill:SetParent(nil)
  zHost:SetParent(nil)
end

-- ── 6. THE FILL DOES NOT OWN THE MOUSE OVER CONTENT OR CHROME ─────────────
-- The fill IS mouse-enabled (leg 1, t_cdee6bb6): it owns the clicks on empty
-- window area. What it must never do is take a click from a control that draws
-- above it — that was the dead-tab defect (t_ea66cd84) and its inner-strip twin
-- (t_cdee6bb6). Both are measured here at the same points the player clicks.
for _, id in ipairs(W.TABS) do
  local btn = W.tabButtons[id]
  if type(btn) == "table" then
    local x, y = C.Centre(btn)
    local owner = C.MouseOwnerAt(x, y)
    check(owner == btn,
      "the frame under the " .. id .. " button's centre is still the button (got "
        .. tostring(owner and (owner.Name or owner.kind) or "nothing") .. ")")
  end
end
if type(bg) == "table" and type(body) == "table" then
  local bx, by = C.Centre(body)
  check(C.MouseOwnerAt(bx, by) ~= bg,
    "the fill frame does not own the mouse over the body")
end
-- ...and the window's own DIALOG frame must not either: with the window frame
-- mouse-enabled it outranked the MEDIUM body for input, which is the whole of
-- card t_cdee6bb6. Empty-area clicks belong to the fill; content and chrome to
-- themselves.
check(win:IsMouseEnabled() == false,
  "the window's chrome frame does NOT take clicks — in DIALOG it outranks the "
    .. "MEDIUM body it hosts and would swallow every inner control")
check(#C.ZOrderHazards() == 0,
  "and the live tree is still hazard-free after the teeth legs are detached (got "
    .. C.DescribeZOrderHazards() .. ")")

if type(bg) == "table" and type(body) == "table" then
  print(("levels: window L%d, fill L%d, host L%d, touchstone L%d")
    :format(win:GetFrameLevel(), bg:GetFrameLevel(), host:GetFrameLevel(),
      body:GetFrameLevel()))
end

if failed == 0 then
  print("window_strata_spec: ok")
else
  print(("window_strata_spec: %d failure(s)"):format(failed))
  os.exit(1)
end
