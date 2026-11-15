-- window_ledger_spec.lua — card t_07f778ca, PART B (B4: the drawing is PINNED).
--
-- The owner picked V1 · Ledger from the pictures. What he approved is a set of
-- structural promises, not a mood:
--
--   * the verdict gutter is the token's width (88), and the marker glyph and the
--     verdict WORD share the verdict's colour — the row's colour belongs to the
--     judgement, not to the item;
--   * the item name is the anchor and the REASON is on its own line BENEATH it,
--     muted and readable, never inline beside it;
--   * the change column is the token's width (110), right-aligned, dim;
--   * the row grows to its reason (ROW_MIN is a floor, not a pitch).
--
-- Every leg here is a measurement of the real rows the pack builds inside the
-- window — not a restatement of the code. The negative legs then build a row the
-- OLD way (reason inline, fixed pitch, dim reason) and require the SAME checker
-- to name it, so a green pass means the checker has teeth.
--
-- Harness: tests/support/wowclient.lua with the real vendored module and the
-- real pack. Not a screenshot: this is what the client was asked to draw.

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
local EPS = 0.05

local pkg = {}
local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. path .. ": " .. tostring(e))
end

local LONG_REASON =
  "eligibility unconfirmed (fail-closed): the client returned false for this link, " ..
  "so no stat order was read for the slot and the item was left unjudged."

-- Sorted by rank then name: UPGRADE first, then TRADE_OFF, then the refusals.
-- The reasons on rows 2-5 are FILLED IN BELOW from the vendored reader itself
-- (card t_24a4c8ea): the ledger's job is to draw whatever reason the reader
-- hands it, so the fixture asks the reader instead of typing a copy that can
-- drift away from it.
local FIXTURE = {
  { link = "[Amber Chain Vest]", id = 1001, verdict = "UPGRADE", slotWord = "Chest", reason = LONG_REASON },
  { link = "[Kelpweave Vest]",  id = 1002, verdict = "UPGRADE", slotWord = "Chest", reason = "" },
  { link = "[Mystic Robe]",     id = 1003, verdict = "TRADE_OFF", slotWord = "Chest", reason = "" },
  { link = "[Ragged Gloves]",   id = 1004, verdict = "NOT_UPGRADE", slotWord = "Hands", reason = "" },
  { link = "[Truesteel Pants]", id = 1005, verdict = "NOT_UPGRADE", slotWord = "Legs", reason = "" },
}

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

local W, T = pkg.Window, pkg.Theme
check(type(W) == "table" and type(T) == "table", "the window and the theme exist")
local SF = rawget(_G, "StatForge")
local CA = rawget(_G, "ChestAdvisor")
check(type(SF) == "table" and type(CA) == "table", "the vendored module and the advisor loaded")

CA.getVerdicts = function()
  local out = {}
  for _, row in ipairs(FIXTURE) do
    out[row.link] = { verdict = row.verdict, id = row.id, slotWord = row.slotWord, reason = row.reason }
  end
  return out
end
if type(CA.tooltipUI) ~= "table" then CA.tooltipUI = {} end
if type(CA.tooltipUI.word) ~= "function" then
  -- The real advisor ships this mapper; a harness without it would make the
  -- "one vocabulary" leg vacuous rather than wrong.
  CA.tooltipUI.word = function(token) return tostring(token) end
end

-- ---- the reasons the reader emits at this pin (card t_24a4c8ea) -------------
-- Asked of the vendored reader, not typed here: the two shapes this re-vendor
-- exists for are the wand pair's dps sentence and DD-2's priced healing word.
-- If the reader's wording moves, this fixture moves with it and the ledger
-- still has to draw whatever comes back.
local V = rawget(_G, "Verdict")
check(type(V) == "table", "the vendored Verdict is loaded")
local WAND_REASON, HEAL_REASON = "", ""
if type(V) == "table" then
  local WAND = { "Lesser Magic Wand", "Binds when equipped", "Ranged  Wand",
    "12 - 22 Arcane Damage  Speed 1.50", "(11.3 damage per second)",
    "Equip: Increases damage and healing done by magical spells and effects by up to 1.",
    "Durability 35 / 35", "Requires Level 5", "Sell Price: 1s 10c" }
  local NOVICE = { "Novice's Practice Wand", "Binds when equipped", "Ranged  Wand",
    "3 - 9 Arcane Damage  Speed 1.50", "(4.0 damage per second)",
    "Durability 20 / 20", "Requires Level 3" }
  local ZWEI = { "Polished ZweiHander of Healing", "Two-Hand  Sword",
    "20 - 37 Damage  Speed 3.00", "(9.5 damage per second)",
    "Equip: Increases healing done by up to 34 and damage done by up to 11"
      .. " for all magical spells and effects" }
  local PLAIN = { "Plain ZweiHander", "Two-Hand  Sword",
    "20 - 37 Damage  Speed 3.00", "(9.5 damage per second)" }
  local PRIEST = { class = "PRIEST", role = "PRIEST", order = { "Intellect", "Spirit", "Stamina" } }
  local HEALER = { class = "PRIEST", role = "spell", clientRole = "HEALER",
    order = { "Intellect", "Spirit", "Stamina" } }
  WAND_REASON = select(2, V.compareWeapon(WAND, NOVICE, true, PRIEST, true)) or ""
  HEAL_REASON = select(2, V.compareWeapon(ZWEI, PLAIN, true, HEALER, true)) or ""
  check(WAND_REASON == "upgrade: more weapon damage per second (11.30 vs 4.00)",
    "the reader emits the wand pair's dps reason (got " .. tostring(WAND_REASON) .. ")")
  check(HEAL_REASON == "upgrade: better on Healing",
    "the reader prices the of-Healing pair on the Healing word (got " .. tostring(HEAL_REASON) .. ")")
end
FIXTURE[2].reason = WAND_REASON
FIXTURE[3].reason = HEAL_REASON
FIXTURE[4].reason = HEAL_REASON
FIXTURE[5].reason = WAND_REASON

-- Open the window on Touchstone and render the Upgrades inner tab, which is what
-- creates the rows in the client.
check(W.Frame() ~= nil, "the window frame is created")
W.Open("touchstone")
if type(SF.SelectTab) == "function" then pcall(SF.SelectTab, "upgrades") end

local LIST = T.list
local function findNamed(frame, name, seen)
  if type(frame) ~= "table" then return nil end
  if frame.Name == name then return frame end
  seen = seen or {}
  if seen[frame] then return nil end
  seen[frame] = true
  local ok, kids = pcall(frame.GetChildren, frame)
  if not ok or type(kids) ~= "table" then return nil end
  for _, child in ipairs(kids) do
    local hit = findNamed(child, name, seen)
    if hit then return hit end
  end
  return nil
end

-- ── 0. The tokens ARE the approved drawing ─────────────────────────────────
-- The card states the palette as hex; the theme must hold those values, not
-- "something close". A drifted token changes the drawing without changing a row,
-- so it is pinned here rather than left to the eye.
local HEX = {
  bg = "14161a", band = "191c22", surface = "1b1f26", raised = "20242c",
  text = "eef1f5", muted = "a8b2c0", dim = "7c8695",
  upgrade = "6fcf97", tradeoff = "e6a94c", noupgrade = "8b95a5",
}
check(type(T.ledgerPalette) == "table", "the theme publishes the ledger palette")
for name, hex in pairs(HEX) do
  local c = type(T.ledgerPalette) == "table" and T.ledgerPalette[name] or nil
  check(type(c) == "table", "the ledger palette states " .. name)
  if type(c) == "table" then
    local function byte(v) return math.floor((v or 0) * 255 + 0.5) end
    local got = string.format("%02x%02x%02x", byte(c[1]), byte(c[2]), byte(c[3]))
    check(got == hex, ("the ledger's %s is #%s (got #%s)"):format(name, hex, got))
  end
end
for _, token in ipairs({ "line", "line2" }) do
  local c = T.ledgerPalette[token]
  check(type(c) == "table" and type(c[4]) == "number" and c[4] > 0 and c[4] < 1,
    "the ledger's " .. token .. " is a white at a partial alpha")
end
check(T.list.gutter == 88 and T.list.change == 110,
  ("the columns are the drawing's (gutter %s, change %s)")
    :format(tostring(T.list.gutter), tostring(T.list.change)))
check(T.list.nameSize == 14.5 and T.list.reasonSize == 12 and T.list.labelSize == 9.5,
  "the type sizes are the drawing's (14.5 / 12 / 9.5)")

-- ── The checker ────────────────────────────────────────────────────────────
local function rgbEqual(c, r, g, b)
  if type(c) ~= "table" then return false end
  return math.abs((c[1] or -1) - r) < 1e-6
    and math.abs((c[2] or -1) - g) < 1e-6
    and math.abs((c[3] or -1) - b) < 1e-6
end

--- The colour a marker texture was drawn in: a tinted glyph (marker.tga) records
--- SetVertexColor, a solid chip records SetColorTexture. Either is "its colour".
local function markerColour(mark)
  if type(mark) ~= "table" then return nil end
  return mark.vertexColor or mark.colorTexture
end

--- Every promise the drawing makes about ONE row, measured. Empty = the row is
--- the drawing. Used on the rows the pack builds AND on the deliberately-wrong
--- rows below, so a green pass is evidence the checker bites.
local function auditRow(row, expectToken)
  local problems = {}
  local name = tostring(row and row.Name or "?")
  local function add(msg) problems[#problems + 1] = name .. ": " .. msg end
  if type(row) ~= "table" then
    return { "no row" }
  end

  -- 1. The verdict gutter is the token's width.
  local gutter = row.gutter
  if type(gutter) ~= "table" then
    add("no verdict gutter")
  else
    local gw = C.Rect(gutter).width
    if math.abs(gw - LIST.gutter) > EPS then
      add(("the verdict gutter is %s wide, the token is %s"):format(tostring(gw), tostring(LIST.gutter)))
    end
  end

  -- 2. The verdict word and the marker share the verdict's colour.
  local word = row.verdictWord
  local tr, tg, tb = T.R(expectToken)
  if type(word) ~= "table" then
    add("no verdict word")
  else
    local okW, wr, wg, wb = pcall(word.GetTextColor, word)
    if not okW or not rgbEqual({ wr, wg, wb }, tr, tg, tb) then
      add(("the verdict word is not the %s colour"):format(expectToken))
    end
    if type(word.GetText) == "function" then
      local text = word:GetText()
      if type(text) ~= "string" or text == "" then add("the verdict word is empty") end
      if text == "UPGRADE" or text == "TRADE_OFF" or text == "NOT_UPGRADE" then
        add("the verdict word is the stored token, not a player word (" .. text .. ")")
      end
    end
  end
  local mark = row.mark
  if type(mark) == "table" and mark.shown ~= false then
    local mc = markerColour(mark)
    if not rgbEqual(mc, tr, tg, tb) then
      add(("the marker is not the %s colour"):format(expectToken))
    end
  end

  -- 3. The reason is on its own line BELOW the name — never beside it.
  local label, reason = row.itemName, row.reason
  if type(label) ~= "table" or type(reason) ~= "table" then
    add("the row has no name or no reason")
  else
    local nr, rr = C.Rect(label), C.Rect(reason)
    if rr.top > nr.bottom + EPS then
      add(("the reason is not below the name (reason top %.1f, name bottom %.1f)")
        :format(rr.top, nr.bottom))
    end
    if math.abs(rr.left - nr.left) > EPS then
      add(("the reason is not in the name's column (reason left %.1f, name left %.1f)")
        :format(rr.left, nr.left))
    end
    if rr.height <= 0 then add("the reason paints nothing") end

    -- 4. The reason is the muted token — secondary, never dimmer.
    local okR, rr1, rg1, rb1 = pcall(reason.GetTextColor, reason)
    local mr, mg, mb = T.R("ledgerMuted")
    if not okR or not rgbEqual({ rr1, rg1, rb1 }, mr, mg, mb) then
      add("the reason is not the muted token")
    end
    if okR and type(rr1) == "number" then
      -- Checked independently of the token match: a reason at 40% white is
      -- "not the token" AND "dimmer than the token", and both are the defect.
      local lum = 0.2126 * rr1 + 0.7152 * rg1 + 0.0722 * rb1
      local mlum = 0.2126 * mr + 0.7152 * mg + 0.0722 * mb
      if lum < mlum - 1e-6 then add("the reason is dimmer than the muted token") end
    end
  end

  -- 5. The change column: the token's width, right-aligned, at the row's edge.
  local change = row.change
  if type(change) ~= "table" then
    add("no change column")
  else
    local cr, rowRect = C.Rect(change), C.Rect(row)
    if math.abs(cr.width - LIST.change) > EPS then
      add(("the change column is %s wide, the token is %s"):format(tostring(cr.width), tostring(LIST.change)))
    end
    if math.abs(cr.right - (rowRect.right - LIST.inset)) > EPS then
      add(("the change column does not end at the row's right edge (%.1f vs %.1f)")
        :format(cr.right, rowRect.right - LIST.inset))
    end
    if type(change.GetJustifyH) == "function" then
      local okJ, j = pcall(change.GetJustifyH, change)
      if okJ and j ~= "RIGHT" then add("the change column is not right-aligned (" .. tostring(j) .. ")") end
    elseif change.justify ~= "RIGHT" then
      add("the change column is not right-aligned")
    end
  end

  -- 6. The row contains its content: height >= the measured columns.
  if type(label) == "table" and type(reason) == "table" then
    local nr, rr, rowRect = C.Rect(label), C.Rect(reason), C.Rect(row)
    local contentH = LIST.padTop + (nr.top - rr.bottom) + LIST.padBottom + LIST.rule
    if rowRect.height + EPS < contentH then
      add(("the row is shorter than its content (row %.1f, content %.1f)")
        :format(rowRect.height, contentH))
    end
  end

  return problems
end

-- ── 1. The rows the pack builds ────────────────────────────────────────────
-- Row order is the tab's own (rank, then name), so the fixture's verdicts are
-- known by index.
local expectations = { "ledgerUpgrade", "ledgerUpgrade", "ledgerTradeoff", "ledgerNoUpgrade", "ledgerNoUpgrade" }
local rows = {}
for i = 1, #FIXTURE do
  rows[i] = findNamed(SF.GetContentFrame and SF.GetContentFrame() or W.Frame(),
    "TouchstoneUpgradeRow" .. i, {})
  check(type(rows[i]) == "table", "row " .. i .. " exists (TouchstoneUpgradeRow" .. i .. ")")
end

for i, row in ipairs(rows) do
  if type(row) == "table" then
    local problems = auditRow(row, expectations[i])
    check(#problems == 0,
      ("row %d is the ledger drawing (%d problem(s)):\n    %s")
        :format(i, #problems, table.concat(problems, "\n    ")))
  end
end

-- The row's words come from the advisor's own mapper: one vocabulary.
if type(rows[1]) == "table" and type(rows[1].verdictWord) == "table" then
  local expected = CA.tooltipUI.word("UPGRADE")
  if expected ~= nil then
    check(rows[1].verdictWord:GetText() == tostring(expected),
      ("the verdict word is the advisor's own (%q, got %q)")
        :format(tostring(expected), tostring(rows[1].verdictWord:GetText())))
  end
end

-- The tall row is the one with the long reason, and it is TALLER than a row
-- whose reason is one line: ROW_MIN is a floor, not a pitch.
if type(rows[1]) == "table" and type(rows[2]) == "table" then
  check(rows[1]:GetHeight() > rows[2]:GetHeight() + EPS,
    ("a wrapped reason grows its row (%.1f vs %.1f)"):format(rows[1]:GetHeight(), rows[2]:GetHeight()))
end

-- The column-label line and the section head are part of the drawing: the head
-- names the section and counts it, the labels name the three columns.
local upgradesHost = W.hosts and W.hosts.touchstone
local function hasText(parent, needle)
  if type(parent) ~= "table" then return nil end
  local ok, kids = pcall(parent.GetChildren, parent)
  if not ok or type(kids) ~= "table" then return nil end
  for _, kid in ipairs(kids) do
    if type(kid.GetText) == "function" then
      local t = kid:GetText()
      if type(t) == "string" and t:find(needle, 1, true) then return t end
    end
  end
  return nil
end

--- Search the whole subtree: the section head lives on the vendored inner host,
--- two levels below the window's touchstone host.
local function findText(frame, needle, seen)
  if type(frame) ~= "table" then return nil end
  seen = seen or {}
  if seen[frame] then return nil end
  seen[frame] = true
  if type(frame.GetText) == "function" then
    local okT, t = pcall(frame.GetText, frame)
    if okT and type(t) == "string" and t:find(needle, 1, true) then return t end
  end
  local ok, kids = pcall(frame.GetChildren, frame)
  if not ok or type(kids) ~= "table" then return nil end
  for _, kid in ipairs(kids) do
    local hit = findText(kid, needle, seen)
    if hit then return hit end
  end
  return nil
end
local columns = findNamed(upgradesHost, "TouchstoneUpgradesColumns", {})
check(type(columns) == "table", "the ledger has a column-label line")
if type(columns) == "table" then
  check(hasText(columns, "VERDICT") ~= nil, "the first column is labelled VERDICT")
  check(hasText(columns, "ITEM AND REASON") ~= nil, "the second column is labelled ITEM AND REASON")
  check(hasText(columns, "CHANGE") ~= nil, "the third column is labelled CHANGE")
end
local head = findText(upgradesHost, "judged")
check(head ~= nil and head:find("5 judged", 1, true) ~= nil and head:find("2 worth taking", 1, true) ~= nil,
  "the section head counts the list (got " .. tostring(head) .. ")")

-- ── 2. NEGATIVE LEGS: a row built the OLD way must be named ────────────────
-- The pre-ledger row: reason INLINE beside the name, everything on one line, a
-- fixed 34-unit pitch. This is the defect the drawing fixes, so the checker must
-- name it — otherwise leg 1's green says nothing about the shape of a row.
local old = CreateFrame("Button", "LedgerSpecOldStyleRow", UIParent, "BackdropTemplate")
old:SetSize(780, 34)
old:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
local oldGutter = CreateFrame("Frame", nil, old)
oldGutter:SetSize(88, 14)
oldGutter:SetPoint("TOPLEFT", old, "TOPLEFT", 6, -4)
old.gutter = oldGutter
local oldName = old:CreateFontString(nil, "OVERLAY", "GameFontNormal")
oldName:SetPoint("TOPLEFT", old, "TOPLEFT", 100, -4)
oldName:SetWidth(400)
oldName:SetText("An old-style row")
old.itemName = oldName
local oldReason = old:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
-- INLINE: to the right of the name, on the same line.
oldReason:SetPoint("LEFT", oldName, "RIGHT", 6, 0)
oldReason:SetWidth(300)
oldReason:SetText("the reason used to sit beside the name, one long line of it")
local dr, dg, db = T.R("ledgerDim")
oldReason:SetTextColor(dr, dg, db)
old.reason = oldReason
local oldChange = old:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
oldChange:SetPoint("TOPRIGHT", old, "TOPRIGHT", -6, -4)
oldChange:SetWidth(60)
old.change = oldChange
local oldWord = oldGutter:CreateFontString(nil, "OVERLAY", "GameFontNormal")
oldWord:SetPoint("TOPLEFT", oldGutter, "TOPLEFT", 0, 0)
oldWord:SetText("Upgrade")
old.verdictWord = oldWord
old.mark = oldGutter:CreateTexture(nil, "OVERLAY")
old.mark:SetSize(14, 14)
old.mark:SetPoint("TOPLEFT", oldGutter, "TOPLEFT", 0, 0)
old.mark:SetColorTexture(1, 0, 0, 1)
old.mark:Hide()

local oldProblems = auditRow(old, "ledgerUpgrade")
check(#oldProblems > 0, "the checker names a row built the old way")
local namedOld, sawInline, sawSqueezed = false, false, false
for _, p in ipairs(oldProblems) do
  if p:find("LedgerSpecOldStyleRow", 1, true) then namedOld = true end
  if p:find("not below the name", 1, true) or p:find("not in the name's column", 1, true) then sawInline = true end
  if p:find("dimmer than the muted token", 1, true) then sawSqueezed = true end
end
check(namedOld, "the offender is NAMED, not merely counted: " .. table.concat(oldProblems, "; "))
check(sawInline, "it is named for the inline reason: " .. table.concat(oldProblems, "; "))
check(sawSqueezed, "a dimmed reason is named too: " .. table.concat(oldProblems, "; "))

-- And the marker/word disagreement is caught on its own: a row whose word is the
-- verdict colour but whose glyph is not.
if type(rows[1]) == "table" and type(rows[1].mark) == "table" then
  local realColour = rows[1].mark.vertexColor
  rows[1].mark.vertexColor = { 1, 0, 0, 1 }
  local problems = auditRow(rows[1], "ledgerUpgrade")
  rows[1].mark.vertexColor = realColour
  local caught = false
  for _, p in ipairs(problems) do
    if p:find("the marker is not the", 1, true) then caught = true end
  end
  check(caught, "a marker in a different colour from the word is named")
end

if failed == 0 then
  print("window_ledger_spec: ok")
else
  print(("window_ledger_spec: %d failure(s)"):format(failed))
  os.exit(1)
end
