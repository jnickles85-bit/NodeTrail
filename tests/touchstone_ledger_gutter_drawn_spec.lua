-- touchstone_ledger_gutter_drawn_spec.lua — the verdict gutter must PAINT.
--
-- WHAT WENT WRONG. On 7439f02 the owner's live client (WoW: Forever, 16001)
-- drew the Upgrades row for Hunter's Boomstick with its name, its reason and its
-- slot word, and drew NOTHING in the VERDICT column: no green marker.tga arrow
-- and no "Upgrade" word. The Log tab's VERDICT column was empty the same way.
-- The tooltip, reading the very same word helper (TOOLTIP_UI.wordFor), said
-- "Upgrade", and the header summary used the same colour tokens — so the word,
-- the colour and the font were all fine.
--
-- The one thing the missing pieces share: they are the only regions owned by
-- the row's `gutter` frame, and that frame was built with ONE anchor
-- (TOPLEFT) and SetWidth(GUTTER) — no height, no second vertical anchor. Its
-- rect is 88 x 0, and the client does not paint the regions of a frame with no
-- area. Every sibling the player COULD see (name, reason, slot) is owned by the
-- row itself, which has a height.
--
-- WHY THE SUITE STAYED GREEN. Every existing ledger spec asked IsVisible()
-- (all flags true), read the text back (SetText worked), and measured the
-- gutter's WIDTH (88, correct). None asked whether the gutter had a height, and
-- the client model had no notion of "drawn" beyond "shown". The model now has
-- `C.Drawn` (tests/support/wowclient.lua), and this spec asks it of the real
-- rows both tabs build inside the real window.
--
-- TEETH. The checker is first run on a hand-built zero-height gutter, which it
-- must call undrawn, and on the same gutter given a height, which it must call
-- drawn — so a green pass is a statement about the shipped rows, not a checker
-- that agrees with everything.
--
-- Run from the repo root:  lua5.1 tests/touchstone_ledger_gutter_drawn_spec.lua

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

-- ── 0. The checker has teeth ───────────────────────────────────────────────
do
  local row = CreateFrame("Frame", nil, UIParent)
  row:SetSize(780, 60)
  row:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
  local gutter = CreateFrame("Frame", nil, row)
  gutter:SetWidth(88)                       -- the 7439f02 shape: width, no height
  gutter:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -11)
  local mark = gutter:CreateTexture(nil, "OVERLAY")
  mark:SetSize(14, 14)
  mark:SetPoint("TOPLEFT", gutter, "TOPLEFT", 0, 0)
  local word = gutter:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  word:SetPoint("TOPLEFT", gutter, "TOPLEFT", 0, -18)
  word:SetWidth(88)
  word:SetText("Upgrade")
  check(mark:IsVisible() and word:IsVisible(),
    "teeth: the zero-height gutter's regions report IsVisible() true (the blind spot)")
  check(not C.Drawn(mark), "teeth: a texture in a zero-height frame is NOT drawn")
  check(not C.Drawn(word), "teeth: a font string in a zero-height frame is NOT drawn")
  gutter:SetHeight(40)
  check(C.Drawn(mark), "teeth: the same texture IS drawn once its frame has a height")
  check(C.Drawn(word), "teeth: the same word IS drawn once its frame has a height")
  local blank = gutter:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  blank:SetPoint("TOPLEFT", gutter, "TOPLEFT")
  blank:SetWidth(88)
  check(not C.Drawn(blank), "teeth: an empty string draws nothing")
  row:Hide()
end

-- ── The real pack, the real window ─────────────────────────────────────────
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
check(pcall(pkg.EnableModules), "the enabled modules start (as they do at login)")

local W = pkg.Window
local SF = rawget(_G, "StatForge")
local CA = rawget(_G, "ChestAdvisor")
check(type(W) == "table" and type(SF) == "table" and type(CA) == "table",
  "the window, the vendored module and the advisor loaded")
if failed > 0 then os.exit(1) end

-- The owner's own rows: the Boomstick upgrade from the 7439f02 screenshot, plus
-- one of each other verdict so every mark branch is exercised.
local FIXTURE = {
  ["[Hunter's Boomstick]"] = { verdict = "UPGRADE", id = 2511, slotWord = "ranged",
    reason = "upgrade: more weapon damage per second (5.00 vs 3.00)" },
  ["[Mystic Robe]"] = { verdict = "TRADE_OFF", id = 1003, slotWord = "chest",
    reason = "better on some stats, worse on others" },
  ["[Ragged Gloves]"] = { verdict = "NOT_UPGRADE", id = 1004, slotWord = "hands",
    reason = "not an upgrade" },
}
CA.getVerdicts = function() return FIXTURE end
CA.getLog = function()
  return {
    { at = 1700000000, slot = 16, slotName = "main hand", link = "[Worn Axe]",
      verdict = "NOT_UPGRADE", reason = "you equipped it anyway" },
    { at = 1700000060, slot = 5, slotName = "chest", link = "[Mystic Robe]",
      verdict = "TRADE_OFF", reason = "you equipped it anyway" },
  }
end

check(W.Frame() ~= nil, "the window frame is created")
W.Open("touchstone")

local function rowsOf(prefix)
  local out = {}
  for i = 1, 20 do
    local r = rawget(_G, prefix .. i)
    if type(r) ~= "table" then break end
    out[#out + 1] = r
  end
  return out
end

local function checkGutter(label, row, wantMark)
  local g = row.gutter
  check(type(g) == "table", label .. ": the row has a verdict gutter")
  if type(g) ~= "table" then return end
  local gr = C.Rect(g)
  check(gr.height > 0, ("%s: the verdict gutter has a height (got %.1f)"):format(label, gr.height))
  local word = row.verdictWord
  local text = word and word:GetText() or ""
  check(text ~= "", label .. ": the verdict word has text")
  local ok, why = C.Drawn(word)
  check(ok, ("%s: the verdict word %q is DRAWN (%s)"):format(label, text, tostring(why)))
  if wantMark then
    local mok, mwhy = C.Drawn(row.mark)
    check(mok, ("%s: the verdict mark is DRAWN (%s)"):format(label, tostring(mwhy)))
  end
  -- The gutter's content must sit inside the gutter's own rect: a gutter that is
  -- tall enough on paper but shorter than the word it holds is the same defect
  -- by a smaller margin.
  local wr = C.Rect(word)
  check(wr.bottom >= gr.bottom - 0.05,
    ("%s: the verdict word ends inside the gutter (word bottom %.1f, gutter bottom %.1f)")
      :format(label, wr.bottom, gr.bottom))
end

-- ── 1. Upgrades: every drawn row paints its verdict ────────────────────────
if type(SF.SelectTab) == "function" then pcall(SF.SelectTab, "upgrades") end
local up = rowsOf("TouchstoneUpgradeRow")
check(#up == 3, "the Upgrades tab built one row per verdict (got " .. #up .. ")")
local sawBoomstick = false
for i, row in ipairs(up) do
  if row:IsVisible() then
    local name = row.itemName and row.itemName:GetText() or ("row " .. i)
    if name == "Hunter's Boomstick" then
      sawBoomstick = true
      check(row.verdictWord:GetText() == "Upgrade",
        "the Boomstick row's word is Upgrade (got " .. tostring(row.verdictWord:GetText()) .. ")")
      check(row.mark:GetTexture() ~= nil, "the Boomstick row's mark is the marker texture")
    end
    local wantMark = (name == "Hunter's Boomstick" or name == "Mystic Robe")
    checkGutter("Upgrades/" .. name, row, wantMark)
  end
end
check(sawBoomstick, "the Boomstick row is on the page")

-- ── 2. Log: the word is the statement, so it must paint ────────────────────
-- LogTab.lua's own note: "most rows have no marker glyph — the verdict word
-- alone is the statement". An empty VERDICT column on a log row is therefore
-- not by design: it is this same defect.
if type(SF.SelectTab) == "function" then pcall(SF.SelectTab, "log") end
local log = rowsOf("TouchstoneLogRow")
check(#log == 2, "the Log tab built one row per entry (got " .. #log .. ")")
for i, row in ipairs(log) do
  if row:IsVisible() then
    local name = row.itemName and row.itemName:GetText() or ("row " .. i)
    checkGutter("Log/" .. name, row, name == "Mystic Robe")
  end
end

if failed > 0 then
  io.stderr:write(("touchstone_ledger_gutter_drawn_spec: %d failure(s)\n"):format(failed))
  os.exit(1)
end
print("touchstone_ledger_gutter_drawn_spec: ok")
