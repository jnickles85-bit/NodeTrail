-- pack_settings_spec.lua — card t_2d2c37b0 (the reshape + design pass).
--
-- Pack Settings is what is LEFT of the pack's own options once NodeTrail's rows
-- left with the module (card t_75309c97). The extraction card deliberately did
-- not delete them — they were unreachable, not wrong — and this card does,
-- because "removed surfaces are gone, not hidden" is the card's second
-- done-when.
--
-- Two halves:
--
--   A. THE SOURCE. Options.lua contains no NodeTrail surface at all: no
--      ntRecipes, no applySkinning, no skinRouteNote, no syncRecipesBlock, no
--      read or write of NodeTrailDB. A helper that still exists is a helper
--      that will be wired up again by mistake.
--
--   B. THE BUILT PANEL. What the player sees is driven from pkg.modules (not a
--      hard-coded list), laid out on the theme's grid, and sized to its own
--      rows: the MODULES card is the height its rows need, the "Gear for"
--      sub-option is indented one sub-step under the row it belongs to, and
--      the feedback buttons and footer sit below it without overlapping.
--
-- Not a screenshot: harness geometry/source evidence.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

-- ── A. THE SOURCE: no NodeTrail surface left in the panel ─────────────────
local optionsSrc = readFile(root .. "/MightiePack/Options.lua") or ""
check(optionsSrc ~= "", "Options.lua is readable")
local banned = {
  { "ntModule", "the NodeTrail module accessor" },
  { "nodeTrailOn", "the NodeTrail module check" },
  { "skinningOn", "the skinning sub-option toggle" },
  { "autoRefreshOn", "the auto-refresh sub-option toggle" },
  { "skinRouteOn", "the farming-circle sub-option toggle" },
  { "skinRouteNote", "the farming-circle note" },
  { "applySkinning", "the skinning applier" },
  { "applySkinRoute", "the farming-circle applier" },
  { "ntRecipes", "the Alchemy recipe scan accessor" },
  { "syncRecipesBlock", "the Alchemy recipe block" },
  { "lastModuleWidget", "the last-widget flow helper" },
  { "lastAlchemyWidget", "the last-widget flow helper" },
  { "NodeTrailDB", "a read or write of NodeTrail's store" },
  { "MIGHTIEPACK_DISABLE_SKINNING", "a NodeTrail popup" },
}
for _, entry in ipairs(banned) do
  local name = entry[1]
  local found = nil
  for line in optionsSrc:gmatch("[^\r\n]+") do
    local code = line:gsub("%s*%-%-.*$", "")
    if code:find(name, 1, true) then found = line break end
  end
  check(found == nil, "Options.lua no longer carries " .. entry[2] ..
    " ('" .. name .. "' appears in: " .. tostring(found) .. ")")
end
-- And the sections that only existed for those rows are gone by name too.
for _, header in ipairs({ "Alchemy Recipes", "Skinning (experimental)", "Auto-refresh", "Farming circle" }) do
  check(optionsSrc:find(header, 1, true) == nil,
    "the '" .. header .. "' row is gone from the panel, not hidden")
end

-- ── B. THE BUILT PANEL ────────────────────────────────────────────────────
local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })
-- The client's TOC metadata API (the harness does not model it); the footer
-- reads it to say which build said this.
GetAddOnMetadata = function(name, what)
  if name ~= "MightiePack" then return nil end
  if what == "Version" then return "9.9.9" end
  if what == "Interface" then return "16001" end
  return nil
end
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
check(pcall(pkg.EnableModules), "the enabled modules start")

local W = pkg.Window
local T = pkg.Theme
local panel = pkg.optionsPanel
check(type(W) == "table" and type(panel) == "table", "the window and the panel exist")

-- Activate the tab: this is the only path that both hosts the panel and runs
-- the build (card t_ea66cd84's lesson — never call OnShow by hand).
W.Open("settings")
check(W.Current() == "settings", "the Pack Settings tab is the active one")
check(panel:GetParent() == W.hosts.settings, "the panel is hosted by the settings tab")

local boxes = pkg.optionsBoxes
check(type(boxes) == "table", "optionsBoxes exists")
check(boxes.Touchstone ~= nil, "the Touchstone module row exists (the pack's one module)")
for _, dead in ipairs({ "NodeTrail", "Skinning", "AutoRefresh", "SkinRoute", "Recipes" }) do
  check(boxes[dead] == nil, "there is no " .. dead .. " widget in the panel")
end

-- The rows come from pkg.modules, not from a hard-coded list: adding a module
-- definition is all it should take for a row to appear.
check(type(pkg.moduleOrder) == "table" and type(pkg.modules) == "table",
  "the panel is driven by pkg.moduleOrder / pkg.modules")

-- Section headings, in the panel's own words.
local function textsUnder(frame, out)
  out = out or {}
  if type(frame) ~= "table" or type(frame.GetChildren) ~= "function" then return out end
  for _, kid in ipairs(frame:GetChildren()) do
    if type(kid) == "table" and type(kid.GetText) == "function" then
      local ok, t = pcall(kid.GetText, kid)
      if ok and type(t) == "string" and t ~= "" then out[#out + 1] = t end
    end
    textsUnder(kid, out)
  end
  return out
end
local function hasText(needle)
  for _, t in ipairs(textsUnder(panel)) do
    if t:find(needle, 1, true) then return true, t end
  end
  return false, nil
end
local okMods = hasText("MODULES")
check(okMods, "the panel carries the MODULES heading")
check(hasText("FEEDBACK"), "the panel carries the FEEDBACK heading")
check(hasText("Touchstone"), "the panel names its module in a row")
check(hasText("Report a bug"), "the panel keeps the bug-report entry point")
check(hasText("Suggest an idea"), "the panel keeps the idea entry point")
local okFooter = hasText("Interface ")
check(okFooter, "the footer states the interface number it was built for")
check(hasText("/mp status"), "the footer names the one command that prints a diagnostic")

-- ── Geometry: rows on the grid, the card sized to its rows ────────────────
local card = boxes.Touchstone and boxes.Touchstone:GetParent()
check(type(card) == "table" and card:GetParent() == panel,
  "the module rows live in a card inside the panel")
local cardRect = C.Rect(card or panel)
check(cardRect.height > 0, "the card has a height it computed itself")
check(cardRect.height % T.space.grid == 0,
  ("the card's height is on the 8px grid (%.0f)"):format(cardRect.height))

local pad = T.space.md
local pitch = T.size.rowPitch
local rows = 1 -- Touchstone
local subRows = (boxes.GearFor and boxes.GearFor:IsShown()) and 1 or 0
local expected = pad + pitch + (rows + subRows) * pitch + pad
check(math.abs(cardRect.height - expected) < 0.5,
  ("the card is exactly as tall as its rows need (%.0f, expected %.0f)")
    :format(cardRect.height, expected))

-- The module row sits one row-pitch below the card's heading line.
local pts = boxes.Touchstone.points
check(type(pts) == "table" and #pts == 1,
  "the module row has exactly one anchor point (no drifting double anchor)")
if type(pts) == "table" and pts[1] then
  local p = pts[1]
  check(p[1] == "TOPLEFT" and p[4] == pad and math.abs((p[5] or 0) + (pad + pitch)) < 0.5,
    ("the module row is on the grid: x %.0f (expected %.0f), y %.0f (expected %.0f)")
      :format(p[4] or 0, pad, p[5] or 0, -(pad + pitch)))
end

-- "Gear for" is a SUB-OPTION: its own row one step below the module row,
-- indented one sub-step, with the label and the button centred on that row.
if boxes.GearFor and boxes.GearForLabel and boxes.GearForRow then
  local rp = boxes.GearForRow.points
  check(type(rp) == "table" and #rp == 1, "the Gear-for row has one anchor point")
  if type(rp) == "table" and rp[1] then
    local p = rp[1]
    check(p[4] == pad + T.size.subIndent,
      ("Gear for is indented one sub-step (x %.0f, expected %.0f)")
        :format(p[4] or 0, pad + T.size.subIndent))
    check(math.abs((p[5] or 0) + (pad + 2 * pitch)) < 0.5,
      ("Gear for is its own row below its module (y %.0f, expected %.0f)")
        :format(p[5] or 0, -(pad + 2 * pitch)))
  end
  -- C.Overlaps takes FRAMES (it resolves each one's rect); passing a rect table
  -- back into it would compare two origin-shaped rects and always "overlap".
  check(not C.Overlaps(boxes.Touchstone, boxes.GearFor),
    "the Gear-for control does not overlap the module row")
  check(not C.Overlaps(boxes.Touchstone, boxes.GearForLabel),
    "the Gear-for label does not overlap the module row")
  check(not C.Overlaps(boxes.GearForLabel, boxes.GearFor),
    "the Gear-for label and its button sit side by side, not on top of each other")
  -- The overlap test must be able to say YES, or the three NOs above prove
  -- nothing. Drop a frame on the module row and require the detector to see it.
  do
    local cover = CreateFrame("Frame", "SpecSettingsCover", card)
    cover:SetPoint("TOPLEFT", boxes.Touchstone, "TOPLEFT", 0, 0)
    cover:SetPoint("BOTTOMRIGHT", boxes.Touchstone, "BOTTOMRIGHT", 0, 0)
    check(C.Overlaps(cover, boxes.Touchstone),
      "the overlap test names a frame placed on the module row")
    cover:SetParent(nil)
  end
end

-- The feedback block sits below the card, and the footer below that.
local bug = nil
for _, kid in ipairs(panel:GetChildren()) do
  if type(kid) == "table" and type(kid.GetText) == "function" then
    local ok, t = pcall(kid.GetText, kid)
    if ok and t == "Report a bug" then bug = kid end
  end
end
check(bug ~= nil, "the Report-a-bug button is a child of the panel")
if bug then
  local bugRect = C.Rect(bug)
  check(bugRect.top <= cardRect.bottom,
    ("the feedback row is below the modules card (bug top %.0f, card bottom %.0f)")
      :format(bugRect.top, cardRect.bottom))
  check(bugRect.height > 0 and math.abs(bugRect.height - T.space.lg) < 0.5,
    ("the feedback buttons are one grid-step tall (%.0f, expected %.0f)")
      :format(bugRect.height, T.space.lg))
end

if failed == 0 then
  print("pack_settings_spec: ok")
else
  print(("pack_settings_spec: %d failure(s)"):format(failed))
  os.exit(1)
end
