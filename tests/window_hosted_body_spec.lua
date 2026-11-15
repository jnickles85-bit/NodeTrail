-- window_hosted_body_spec.lua — card t_07f778ca, review 2 (PART B's retest).
--
-- THE DEFECT (the owner, in game, on 670c1ef): the ledger landed inside the OLD
-- Touchstone panel — its own bordered box, its own title bar with a second close
-- button, and the module's teal chrome (title, tab highlights, Settings
-- headings). Part A2 stripped StatForgeMainFrame's own backdrop and hid "the
-- 40px child" — and both claims were true at THEIR level only:
--
--   * the body's OUTER backdrop lost its edge, but the body's CONTENT frame kept
--     painting a WHITE8x8 border: that is the box around the ledger;
--   * the title bar was hidden by matching a child's measured height. The
--     harness agreed with the measurement; the live client did not, and kept
--     drawing the title bar and its close button.
--
-- The fix is a HOSTED MODE in the vendored UI (tools/touchstone-patches/
-- UI.lua.patch): told by the pack, the body's own creation path skips its title
-- bar and close button, draws no border and no fill on itself or its content
-- frame, keeps the inner strip as navigation, and resolves every accent through
-- the pack's theme. Nothing is recognised by height, order or name.
--
-- So this spec asserts the RENDERED state of the whole subtree under the body,
-- on the LIVE path (W.Open("touchstone"), the call the tab renderer makes), and
-- not just the one frame Part A claimed:
--
--   1. no shown frame under the body paints a backdrop edge (a border);
--   2. the content frame specifically: no edge, transparent fill;
--   3. no chrome the body owns is shown — by REFERENCE (SF.Chrome()), not by
--      measuring it; a frame created in hosted mode has none of them at all;
--   4. no visible FontString under the body carries the vendored accent
--      (#66fcf1), by colour value AND by colour code in its text;
--   5. the inner strip still offers Upgrades / Log / Settings and still
--      switches tabs (navigation preserved, not deleted);
--   6. the Settings tab's own headings are painted from the pack's palette.
--
-- Every leg has a negative leg: the SAME checker that is silent on the live tree
-- must name a re-introduced edge, a re-introduced teal string, and a shown title
-- bar. A checker that cannot name the defect proves nothing when it is quiet.
--
-- VISIBILITY: effective, not own-flag. The client hides a child whose ancestor
-- is hidden, and tests/support/wowclient.lua's C.Visible walks the ancestor
-- chain for exactly that. Using a child's own IsShown() was the harness gap
-- named in the review; it reports a FontString under a hidden parent as shown.

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

local toc = assert(io.open(root .. "/MightiePack/MightiePack.toc", "r"))
local tocText = toc:read("*a")
toc:close()
for line in tocText:gmatch("[^\r\n]+") do
  local t = line:gsub("^%s+", ""):gsub("%s+$", "")
  if t ~= "" and not t:match("^##") then loadFile(t) end
end
local okEnable, errEnable = pcall(pkg.EnableModules)
check(okEnable, "the enabled modules start (as they do at login): " .. tostring(errEnable))

local W, T = pkg.Window, pkg.Theme
local SF = rawget(_G, "StatForge")
check(type(W) == "table" and type(T) == "table" and type(SF) == "table",
  "the window, the theme and the vendored body exist")

-- ── The live path ─────────────────────────────────────────────────────────
-- EXACTLY what a player does when his slash command opens the window: no
-- W.Frame(), no direct AttachTouchstone, no test-only shortcut.
W.Open("touchstone")
local body = rawget(_G, "StatForgeMainFrame")
check(type(body) == "table", "the body exists after W.Open(\"touchstone\")")
if type(body) ~= "table" then
  print("window_hosted_body_spec: " .. failed .. " failure(s)")
  os.exit(1)
end
check(C.Visible(body) == true, "the body is visible on the Touchstone tab")

-- ── Walker ────────────────────────────────────────────────────────────────
-- The harness registers every FontString twice in its parent's `children`, so
-- the walk dedupes by identity. Only EFFECTIVELY SHOWN frames are audited: what
-- a hidden thing paints is not on the player's screen.
local function walk(rootFrame)
  local out, seen = {}, {}
  local function visit(f)
    if type(f) ~= "table" or seen[f] then return end
    seen[f] = true
    out[#out + 1] = f
    local ok, kids = pcall(f.GetChildren, f)
    if ok and type(kids) == "table" then
      for _, kid in ipairs(kids) do visit(kid) end
    end
  end
  visit(rootFrame)
  return out
end

local function shownUnder(rootFrame)
  local out = {}
  for _, f in ipairs(walk(rootFrame)) do
    if C.Visible(f) then out[#out + 1] = f end
  end
  return out
end

local function nameOf(f)
  if type(f) ~= "table" then return "?" end
  if type(f.Name) == "string" and f.Name ~= "" then return f.Name end
  return "<" .. tostring(f.kind or "frame") .. ">"
end

local function hex(c)
  if type(c) ~= "table" then return "none" end
  return format("#%02x%02x%02x",
    math.floor((c[1] or 0) * 255 + 0.5),
    math.floor((c[2] or 0) * 255 + 0.5),
    math.floor((c[3] or 0) * 255 + 0.5))
end

local ACCENT = type(SF.Colors) == "table" and SF.Colors.accent or { 0.4, 0.988, 0.945 }
local ACCENT_HEX = hex(ACCENT)
local function nearAccent(r, g, b)
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return false end
  return math.abs(r - ACCENT[1]) < 0.02
    and math.abs(g - ACCENT[2]) < 0.02
    and math.abs(b - ACCENT[3]) < 0.02
end

-- ── Checker 1: no border under the body ───────────────────────────────────
--- Every effectively shown frame under `rootFrame` that paints a backdrop edge.
--- Returns sentences, empty when the tree is a flat plane.
local function auditEdges(rootFrame)
  local out = {}
  for _, f in ipairs(shownUnder(rootFrame)) do
    local bd = f.backdrop
    if type(bd) == "table" and type(bd.edgeFile) == "string" and bd.edgeFile ~= "" then
      out[#out + 1] = nameOf(f) .. " paints a border (edgeFile = " .. bd.edgeFile .. ")"
    end
  end
  return out
end

-- ── Checker 2: no vendored accent under the body ──────────────────────────
--- Every effectively shown FontString whose TEXT COLOUR is the vendored accent
--- (the harness records the actual SetTextColor values) or whose text embeds the
--- accent as a colour code (the title fontstring did exactly that: its text was
--- "|cff66fcf1Touchstone|r", so its default colour was not the whole story).
local function auditAccent(rootFrame)
  local out = {}
  for _, f in ipairs(shownUnder(rootFrame)) do
    if f.kind == "FontString" then
      local r, g, b = f:GetTextColor()
      if nearAccent(r, g, b) then
        out[#out + 1] = nameOf(f) .. " paints in the vendored accent " .. hex({ r, g, b })
      end
      local text = tostring(f.text or ""):lower()
      if text:find("|cff" .. ACCENT_HEX:gsub("#", ""), 1, true) then
        out[#out + 1] = nameOf(f) .. " embeds the vendored accent in its text: "
          .. tostring(f.text)
      end
    end
  end
  return out
end

-- ── Checker 3: the chrome the body owns is not shown ──────────────────────
--- `parts` is a list of { label = "...", frame = ... }. A part that does not
--- exist is not a problem — in hosted mode the chrome is never created. A part
--- that EXISTS and is effectively shown is the second title bar / second close
--- button the owner saw.
local function auditChrome(parts)
  local out = {}
  for _, part in ipairs(parts) do
    local f = part.frame
    if type(f) == "table" and C.Visible(f) then
      out[#out + 1] = part.label .. " is shown inside the hosted body"
    end
  end
  return out
end

-- ── Checker 4: the content frame is one flat plane ────────────────────────
--- Returns nil when `cf` is a flat, transparent plane; a sentence otherwise.
local function auditContentFrame(cf)
  if type(cf) ~= "table" then return "the content frame does not exist" end
  local bd = cf.backdrop
  if type(bd) ~= "table" then return nameOf(cf) .. " has no backdrop at all" end
  if type(bd.edgeFile) == "string" and bd.edgeFile ~= "" then
    return nameOf(cf) .. " paints its own border (edgeFile = " .. bd.edgeFile .. ")"
  end
  local ok, r, g, b, a = pcall(cf.GetBackdropColor, cf)
  if not ok or type(a) ~= "number" then
    return nameOf(cf) .. " has no backdrop colour to read"
  end
  if a ~= 0 then
    return nameOf(cf) .. " paints a fill (alpha " .. tostring(a) .. ")"
  end
  if type(bd.insets) == "table" then
    for _, side in ipairs({ "left", "right", "top", "bottom" }) do
      if (tonumber(bd.insets[side]) or 0) ~= 0 then
        return nameOf(cf) .. " insets its fill (" .. side .. ")"
      end
    end
  end
  return nil
end

-- ── 1. THE PASS LEG: the whole subtree under the body ─────────────────────
local edgeHits = auditEdges(body)
check(#edgeHits == 0,
  "no shown frame under the hosted body paints a border (" .. #edgeHits .. "):\n    "
    .. table.concat(edgeHits, "\n    "))

local accentHits = auditAccent(body)
check(#accentHits == 0,
  "no shown FontString under the hosted body carries the vendored accent " .. ACCENT_HEX
    .. " (" .. #accentHits .. "):\n    " .. table.concat(accentHits, "\n    "))

-- The tree must CONTAIN things, or "no offenders" would be vacuous.
local shownFrames, shownLabels = 0, 0
for _, f in ipairs(shownUnder(body)) do
  shownFrames = shownFrames + 1
  if f.kind == "FontString" then shownLabels = shownLabels + 1 end
end
check(shownFrames > 3, "the audit walked real frames (found " .. shownFrames .. ")")
check(shownLabels > 0, "the audit walked real FontStrings (found " .. shownLabels .. ")")

-- ── 2. THE CONTENT FRAME, by reference ───────────────────────────────────
-- SF.ContentFrame() is a handle the body publishes, so this is "the box under
-- the ledger" and not "whatever child is third" or "whatever is 391 tall".
local contentFrame = type(SF.ContentFrame) == "function" and SF.ContentFrame() or nil
check(type(contentFrame) == "table", "the body publishes its content frame (SF.ContentFrame)")
local contentProblem = auditContentFrame(contentFrame)
check(contentProblem == nil, "the content frame is ONE FLAT PLANE: " .. tostring(contentProblem))
check(type(contentFrame) == "table" and contentFrame:GetParent() == body,
  "the content frame is a child of the body (the box the ledger renders into)")

-- ── 3. THE CHROME, by reference ──────────────────────────────────────────
-- In hosted mode the chrome is never CREATED. The accessor is the body's own
-- statement of which parts those would be; nothing here measures a height.
local chrome = type(SF.Chrome) == "function" and SF.Chrome() or {}
local chromeParts = {
  { label = "the title bar", frame = chrome.titleBar },
  { label = "the close button", frame = chrome.close },
  { label = "the title fontstring", frame = chrome.title },
  { label = "the subtitle fontstring", frame = chrome.subtitle },
}
local chromeHits = auditChrome(chromeParts)
check(#chromeHits == 0,
  "the hosted body shows no chrome of its own (" .. #chromeHits .. "):\n    "
    .. table.concat(chromeHits, "\n    "))
check(chrome.titleBar == nil and chrome.close == nil,
  "hosted, the title bar and its close button are not even created")
check(type(chrome.strip) == "table", "the inner tab strip IS created (navigation, not chrome)")

-- ── 4. THE INNER STRIP STILL NAVIGATES ───────────────────────────────────
-- Restyled is not removed: the three inner tabs must exist, be visible, and
-- still switch the body's tab.
local function findTabButton(label)
  for _, f in ipairs(shownUnder(body)) do
    if f.kind == "Button" and type(f.label) == "table"
      and tostring(f.label.text) == label then
      return f
    end
  end
  return nil
end

local upgradesBtn = findTabButton("Upgrades")
local logBtn = findTabButton("Log")
local settingsBtn = findTabButton("Settings")
check(upgradesBtn ~= nil and logBtn ~= nil and settingsBtn ~= nil,
  "the inner strip still offers Upgrades / Log / Settings")

if logBtn then
  C.FireScript(logBtn, "OnClick")
  check(SF.ActiveTab() == "log", "clicking Log switches the body to Log (got "
    .. tostring(SF.ActiveTab()) .. ")")
end
if settingsBtn then
  C.FireScript(settingsBtn, "OnClick")
  check(SF.ActiveTab() == "options", "clicking Settings switches the body to Settings (got "
    .. tostring(SF.ActiveTab()) .. ")")
end

-- ── 5. THE SETTINGS TAB IS PAINTED IN THE PACK'S PALETTE ────────────────
-- The owner's third complaint: the module's teal Settings headings. The accent
-- scan above now covers the Settings tree, because that tab is the active one.
local settingsEdgeHits = auditEdges(body)
check(#settingsEdgeHits == 0,
  "no shown frame under the body paints a border on the Settings tab ("
    .. #settingsEdgeHits .. "):\n    " .. table.concat(settingsEdgeHits, "\n    "))
local settingsAccentHits = auditAccent(body)
check(#settingsAccentHits == 0,
  "no shown FontString under the body carries the vendored accent on the Settings tab ("
    .. #settingsAccentHits .. "):\n    " .. table.concat(settingsAccentHits, "\n    "))

-- A heading IS painted — in the pack's reading colour, not the module's teal.
local sawHeading = false
for _, f in ipairs(shownUnder(body)) do
  if f.kind == "FontString" and tostring(f.text) == "What Touchstone shows" then
    sawHeading = true
    local r, g, b = f:GetTextColor()
    local tr, tg, tb = T.Ledger("text")
    check(math.abs(r - tr) < 0.02 and math.abs(g - tg) < 0.02 and math.abs(b - tb) < 0.02,
      "the Settings heading paints in the ledger's reading colour (got " .. hex({ r, g, b }) .. ")")
  end
end
check(sawHeading, "the Settings tab's headings are on screen (the scan had something to read)")

if upgradesBtn then
  C.FireScript(upgradesBtn, "OnClick")
  check(SF.ActiveTab() == "upgrades", "clicking Upgrades comes back (got "
    .. tostring(SF.ActiveTab()) .. ")")
end

-- ── 6. NEGATIVE LEGS: each checker must NAME what it forbids ─────────────
-- A quiet checker proves nothing unless it can be made to speak. Each leg
-- re-introduces exactly the defect the owner saw and requires the SAME code
-- that passed above to fail.

-- 6a. Re-introduce a border under the body.
local badRoot = CreateFrame("Frame", "HostedSpecBadRoot", UIParent)
local badBox = CreateFrame("Frame", "HostedSpecBadBox", badRoot, "BackdropTemplate")
badBox:SetSize(100, 60)
badBox:SetBackdrop({
  bgFile = T.tex.solid, edgeFile = T.tex.edge, tile = false, edgeSize = 1,
  insets = { left = 0, right = 0, top = 0, bottom = 0 },
})
local badEdgeHits = auditEdges(badRoot)
local namedEdge = false
for _, hit in ipairs(badEdgeHits) do
  if hit:find("HostedSpecBadBox", 1, true) then namedEdge = true end
end
check(namedEdge, "the edge checker NAMES a re-introduced border: "
  .. table.concat(badEdgeHits, "; "))

-- 6b. Re-introduce the vendored accent on a visible string.
local badLabel = badRoot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
badLabel:SetText("Touchstone")
badLabel:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
badLabel:SetPoint("TOPLEFT", badRoot, "TOPLEFT", 0, 0)
local badAccentHits = auditAccent(badRoot)
local namedAccent = false
for _, hit in ipairs(badAccentHits) do
  if hit:find("re-introduced", 1, true) or hit:find("accent", 1, true) then
    namedAccent = namedAccent or hit:find(ACCENT_HEX, 1, true) ~= nil
  end
end
check(#badAccentHits > 0 and namedAccent,
  "the accent checker NAMES a re-introduced teal string (" .. #badAccentHits .. "):\n    "
    .. table.concat(badAccentHits, "\n    "))

-- 6c. Re-introduce a title bar: the chrome checker must name it.
local fakeTitleBar = CreateFrame("Frame", "HostedSpecFakeTitleBar", body)
fakeTitleBar:SetSize(100, 40)
fakeTitleBar:Show()
local fakeClose = CreateFrame("Button", nil, fakeTitleBar, "UIPanelCloseButton")
local badChromeHits = auditChrome({
  { label = "the title bar", frame = fakeTitleBar },
  { label = "the close button", frame = fakeClose },
})
local namedTitle, namedClose = false, false
for _, hit in ipairs(badChromeHits) do
  if hit:find("title bar", 1, true) then namedTitle = true end
  if hit:find("close button", 1, true) then namedClose = true end
end
check(namedTitle and namedClose,
  "the chrome checker NAMES a re-introduced title bar and close button: "
    .. table.concat(badChromeHits, "; "))

-- 6d. Re-introduce the bordered box on the REAL content frame (the owner's own
-- defect, put back where it was), require the checker to name it, then restore.
if type(contentFrame) == "table" then
  local flat = contentFrame.backdrop
  contentFrame:SetBackdrop({
    bgFile = T.tex.solid, edgeFile = T.tex.edge, tile = false, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  contentFrame:SetBackdropColor(0.1, 0.12, 0.15, 0.6)
  local problem = auditContentFrame(contentFrame)
  check(problem ~= nil and problem:find("border", 1, true) ~= nil,
    "the content-frame checker NAMES the old bordered box: " .. tostring(problem))
  contentFrame:SetBackdrop(flat)
  contentFrame:SetBackdropColor(0, 0, 0, 0)
  check(auditContentFrame(contentFrame) == nil,
    "restoring the flat plane makes the content-frame checker quiet again")
end

-- The negative tree must not leak into the live audit.
fakeTitleBar:Hide()
badLabel:Hide()
badBox:Hide()

if failed == 0 then
  print("window_hosted_body_spec: ok")
else
  print(("window_hosted_body_spec: %d failure(s)"):format(failed))
  os.exit(1)
end
