-- window_touchstone_shade_spec.lua — is anything shading the Touchstone body?
--
-- Card t_5d0cc41a. The owner sees the Touchstone tab in the unified window
-- "uniformly dimmed, roughly a quarter brightness" while Herbs, Skinning and
-- Pack Settings are at full brightness, and the veil travels with Touchstone's
-- OWN content (his GetMouseFocus chain over the outer tab row shows nothing
-- foreign above the button).
--
-- This file does not claim to explain what he sees. It pins the one question
-- that HAS to be answered first, mechanically: can anything the pack creates
-- draw over the hosted Touchstone body and tint it? A "shader" here is a
-- visible frame that
--
--   * overlaps at least half of the body's rect,
--   * draws ABOVE the deepest frame inside the body (i.e. above every label,
--     row and button the panel owns — a veil on the panel is above its text),
--   * and is not fully transparent (frame alpha < 1, or a backdrop colour with
--     alpha < 1). A frame that draws above the content but paints nothing
--     cannot dim it.
--
-- Legs:
--   1. THE HOSTED PATH RAN. StatForgeMainFrame exists, is parented to the
--      touchstone host and is shown. Without this every later leg would pass
--      on an empty tree.
--   2. NO SHADER, with the owner's saved state (`firstUse = false`, which is
--      what his account-level SavedVariables holds). Green today, and it is
--      the leg that would go red if the pack ever left a veil over the hosted
--      body again.
--   3. THE DETECTOR HAS TEETH. Install the exact frame the first-use splash
--      installs — SetAllPoints(body), level = deepest + 50, black backdrop at
--      alpha 0.78 — and require the detector to name it. Without this leg,
--      leg 2 going green would only prove the checker found nothing.
--   4. THE GUARD, on a fresh install. With `firstUse == nil` the vendored show
--      path DOES leave that 0.78 cover over the hosted body, and the detector
--      names it. That is the real (and different) defect the card's prime
--      suspect described; it is recorded here, not fixed (mira's STOP), so a
--      change that makes it fire on a save with `firstUse == false` fails
--      loudly instead of quietly dimming the tab.
--   5. FRAME LEVEL IS NOT THE DIFFERENCE. The other reparented body in this
--      window — Options.lua's Pack Settings panel, which the owner confirmed
--      renders at full brightness — is hosted at a level no higher than
--      Touchstone's. So "the reparented frame kept a low level" cannot be what
--      distinguishes the dim tab from the bright one.
--
-- Harness: tests/support/wowclient.lua, extended on this card so it can model
-- the two client behaviours this question needs: a frame's level is frozen at
-- birth (a SetParent does not re-level it), and a NAMED frame becomes a global.

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

-- The owner's live account-level SavedVariables, reduced to the keys that
-- matter: the module is on, Touchstone has been used before.
MightiePackDB = { modules = { NodeTrail = true, Touchstone = true }, seen = { firstRun = true }, bugCount = 0 }
NodeTrailDB = {
  schema = 2,
  herbs = { schema = 2, total = 0, maps = {}, mapTotals = {}, stats = { gathers = {}, co = {}, names = {} }, hotspots = {}, folded = {} },
  skinning = { enabled = true, schema = 2, chars = {} },
  route = {},
}
StatForgeDB = { ui = { scale = 1 }, firstUse = false }

-- Load in TOC order, exactly as the client does: the real vendored Touchstone
-- module, the real Window.lua and the real tab files.
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

-- ── 1. THE HOSTED PATH RAN ─────────────────────────────────────────────────
local opened = W.Open("touchstone")
check(opened == true, "the window opens on the touchstone tab")
local host = W.hosts and W.hosts.touchstone
check(type(host) == "table", "the touchstone host exists")

local body = rawget(_G, "StatForgeMainFrame")
check(type(body) == "table",
  "StatForgeMainFrame exists after the tab opened (the vendored show path ran)")
check(type(body) == "table" and body:GetParent() == host,
  "the Touchstone body is parented into the touchstone host")
check(type(body) == "table" and body:IsShown(), "the Touchstone body is shown")

-- ── The detector ───────────────────────────────────────────────────────────
local function ancestors(frame)
  local out = {}
  local p = frame
  while type(p) == "table" do
    out[p] = true
    p = p:GetParent()
  end
  return out
end

local function descendants(frame)
  local out = {}
  local function walk(f)
    local ok, kids = pcall(f.GetChildren, f)
    if not ok or type(kids) ~= "table" then return end
    for _, k in ipairs(kids) do
      if type(k) == "table" and not out[k] and type(k.GetFrameLevel) == "function" then
        out[k] = true
        out[#out + 1] = k
        walk(k)
      end
    end
  end
  walk(frame)
  return out
end

--- The deepest frame the body owns: a veil over the panel must be above this.
local function deepestOwn(frame)
  local best, bestLevel = nil, -1
  for _, f in ipairs(descendants(frame)) do
    local ok, lvl = pcall(f.GetFrameLevel, f)
    if ok and type(lvl) == "number" and lvl > bestLevel then best, bestLevel = f, lvl end
  end
  return best, bestLevel
end

--- Share of `body`'s rect that `f` covers (0..1). WoW's y axis points down
--- from the screen top, so a rect's `top` is GREATER than its `bottom`.
local function coverage(f, body)
  local a, b = C.Rect(f), C.Rect(body)
  local bw, bh = b.width, b.height
  if bw <= 0 or bh <= 0 then return 0 end
  local left = math.max(a.left, b.left)
  local right = math.min(a.right, b.right)
  local top = math.min(a.top, b.top)
  local bottom = math.max(a.bottom, b.bottom)
  if right <= left or top <= bottom then return 0 end
  return ((right - left) * (top - bottom)) / (bw * bh)
end

--- Would this frame visibly tint what is behind it?
local function tints(f)
  local okA, alpha = pcall(f.GetAlpha, f)
  if okA and type(alpha) == "number" and alpha < 0.999 then return true, ("frame alpha %.2f"):format(alpha) end
  local okC, r, g, b, a = pcall(f.GetBackdropColor, f)
  if okC and type(r) == "number" and type(a) == "number" and a < 0.999 then
    return true, ("backdrop alpha %.2f"):format(a)
  end
  return false, "opaque"
end

local function label(f)
  return string.format("%s/%s L%d", tostring(f.Name), tostring(f.kind or "?"), f:GetFrameLevel())
end

--- Every frame that shades `target`: above `ref` (the deepest frame the panel
--- owned BEFORE any cover was installed — see leg 3), covering at least half of
--- the target, visible, not an ancestor, and actually tinting.
---
--- `ref` is passed in rather than recomputed: once a cover exists it IS the
--- deepest frame in the panel, and "draws above the deepest frame" would then
--- compare the cover with itself.
local function shaders(target, ref)
  local out = {}
  if type(target) ~= "table" then return out end
  local above = ancestors(target)
  for _, f in ipairs(C.allFrames) do
    local kind = f.kind or "Frame"
    local isRegion = kind == "Texture" or kind == "FontString"
    if not isRegion and f ~= target and not above[f] and C.Visible(f) and ref then
      local cov = coverage(f, target)
      if cov >= 0.5 and C.DrawsAbove(f, ref) and tints(f) then
        out[#out + 1] = f
      end
    end
  end
  return out
end

local function describeShaders(list)
  local parts = {}
  for _, f in ipairs(list) do
    local _, why = tints(f)
    parts[#parts + 1] = label(f) .. " cov=" .. ("%.0f%%"):format(coverage(f, body) * 100) .. " " .. why
  end
  return table.concat(parts, "; ")
end

-- ── 2. NO SHADER with the owner's saved state ──────────────────────────────
-- The reference frame is the deepest thing the panel owns on a normal open,
-- measured before anything is installed below.
local contentRef, contentLevel = deepestOwn(body)
check(type(contentRef) == "table",
  "the hosted body owns content to measure against (deepest level " .. tostring(contentLevel) .. ")")
local found = shaders(body, contentRef)
check(#found == 0,
  "with firstUse=false the pack leaves no frame shading the hosted Touchstone body (got "
    .. #found .. ": " .. describeShaders(found) .. ")")

-- The splash cover is not even created on this path (the guard at
-- UI.lua:462 reads `StatForgeDB.firstUse ~= false`).
local coverChildren = 0
if type(body) == "table" then
  for _, child in ipairs(body:GetChildren()) do
    if type(child) == "table" and child.GetAllPoints and child:GetAllPoints() == body then
      coverChildren = coverChildren + 1
    end
  end
end
check(coverChildren == 0,
  "no full-frame overlay is created inside the Touchstone body when firstUse=false (got "
    .. coverChildren .. ")")

-- ── 3. THE DETECTOR HAS TEETH ──────────────────────────────────────────────
-- Install exactly what SF.ShowFirstUseSplash installs, and require the
-- detector to name it. If this leg cannot fail the detector, leg 2 is
-- worthless.
local deepest, deepestLevel = contentRef, contentLevel
local teeth
if type(body) == "table" and deepest then
  teeth = CreateFrame("Frame", "SpecShadeTeeth", body, "BackdropTemplate")
  teeth:SetAllPoints(body)
  teeth:SetFrameLevel(deepestLevel + 50)
  if type(teeth.SetBackdrop) == "function" then
    teeth:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", tile = false, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    teeth:SetBackdropColor(0, 0, 0, 0.78)
    teeth:SetBackdropBorderColor(0, 0, 0, 0)
  end
  teeth:EnableMouse(true)
end
local teethFound = shaders(body, contentRef)
local named = false
for _, f in ipairs(teethFound) do
  if f == teeth then named = true end
end
check(named,
  "the detector names a deliberately installed 0.78 cover over the body (found "
    .. #teethFound .. " shader(s): " .. describeShaders(teethFound) .. ")")
if teeth then teeth:Hide() end
check(#shaders(body, contentRef) == 0, "hiding the installed cover silences the detector")

-- ── 4. THE FRESH-INSTALL CASE, recorded ────────────────────────────────────
-- firstUse == nil is a player who has never opened Touchstone. The guard is
-- true, the vendored show path shows the splash, and because the splash was
-- written for a standalone window it now covers the hosted body at 0.78 — a
-- quarter brightness. This is what the card's prime suspect described; it is
-- a real defect on a fresh install, and it is NOT the owner's current state.
if type(W._sfShowMain) == "function" and type(body) == "table" then
  StatForgeDB.firstUse = nil
  local okShow = pcall(W._sfShowMain, "upgrades")
  check(okShow, "the vendored show path runs with firstUse=nil")
  local fresh = shaders(body, contentRef)
  local freshNamed = false
  for _, f in ipairs(fresh) do
    local _, why = tints(f)
    if why:find("0.78", 1, true) or why:find("0.77", 1, true) then freshNamed = true end
  end
  check(freshNamed,
    "with firstUse=nil the hosted path leaves a 0.78 cover over the body and the detector names it (got "
      .. #fresh .. ": " .. describeShaders(fresh) .. ")")
  StatForgeDB.firstUse = false
end

-- ── 5. FRAME LEVEL IS NOT THE DIFFERENCE ───────────────────────────────────
-- The Pack Settings body is the other reparented frame in this window, and the
-- owner reports it at full brightness. If it is hosted at a level no higher
-- than Touchstone's, the level cannot explain the difference between the tabs.
W.Open("settings")
local settingsPanel = pkg.optionsPanel
local okPanel = type(settingsPanel) == "table"
check(okPanel, "the Pack Settings panel exists (pkg.optionsPanel)")
if okPanel and type(body) == "table" then
  local settingsHost = W.hosts and W.hosts.settings
  check(settingsPanel:GetParent() == settingsHost,
    "the Pack Settings panel is parented into its host too")
  check(settingsPanel:GetFrameLevel() <= body:GetFrameLevel(),
    "the full-brightness Pack Settings body is hosted at a level no higher than Touchstone's (settings L"
      .. settingsPanel:GetFrameLevel() .. ", touchstone L" .. body:GetFrameLevel()
      .. ") — so frame level cannot be what dims Touchstone")
  print(("levels: window L%d, host L%d, touchstone L%d, settings L%d")
    :format(win:GetFrameLevel(), host:GetFrameLevel(), body:GetFrameLevel(), settingsPanel:GetFrameLevel()))
end

if failed == 0 then
  print("window_touchstone_shade_spec: ok")
else
  print(("window_touchstone_shade_spec: %d failure(s)"):format(failed))
  os.exit(1)
end
