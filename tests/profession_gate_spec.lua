-- t_d4848ce0 — the herb block belongs to herbalists, and the picks number must
-- say where it comes from.
--
-- Two defects, one data build:
--   1. every character saw the herb block, including a skinning hunter who
--      cannot gather a single herb;
--   2. the block's `Your picks: N` came from NodeTrailDB.herbs.maps — ONE saved
--      table for the whole account (Recorder.lua keys nothing per character) —
--      so on the skinner that "your" count was somebody else's eight gathers.
--
-- The fix is a profession gate in the panel's DATA BUILD plus honest wording:
--   * an herbalist      -> block, with `Picks: N (all characters)`;
--   * not an herbalist  -> no block at all;
--   * unreadable        -> block, but NO picks line (never "yours"), and the
--                          diag says why.
--
-- The gate reads the client's own skill API and MEASURES which call exists
-- (GetNumSkillLines/GetSkillLineInfo, GetProfessions/GetProfessionInfo, or the
-- open-window calls), which is what /nt ttdiag has to report.
--
-- Not loaded by the addon TOC.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

local F = dofile(root .. "/tests/support/fakeui.lua")
F.install({ width = 1920, height = 1080 })

local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end }
time = time or os.time
CopyTable = function(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = type(v) == "table" and CopyTable(v) or v
  end
  return c
end
GetSpellInfo = function(id)
  local map = { [2366] = "Herb Gathering", [2259] = "Alchemy" }
  return map[id]
end
UnitExists = function() return false end
SlashCmdList = {}

local pkg = {}
local function loadFile(path)
  local f = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path))
  f("MightiePack", pkg)
end

loadFile("locale/enUS.lua")
loadFile("Config.lua")
loadFile("Data/ItemNames.lua")
loadFile("Data/Recorder.lua")
loadFile("Data/HerbData.lua")
loadFile("Data/Profession.lua")
loadFile("Data/Recipes.lua")
loadFile("UI/TooltipPanel.lua")
loadFile("UI/Tooltip.lua")
loadFile("Core.lua")

local ns = pkg.NodeTrail
local T = ns.Tooltip
local P = ns.TooltipPanel
local Pr = ns.Profession

NodeTrailDB = { recipes = {}, profile = {}, herbs = { schema = 1, total = 0, maps = {} } }

-- The client's skill lines, behind one stub. `rank` is what makes a row a
-- learned profession; the shape is the documented 4-field one:
--   name, isHeader, isExpanded, skillRank
local skillLines = {}
local skillShape = "4-field"
local skillRaises = false
-- Individual rows can fail while the rest of the list reads: case 12.
local skillRaiseRows = nil
GetNumSkillLines = function() return #skillLines end
GetSkillLineInfo = function(i)
  if skillRaises then
    error("boom: GetSkillLineInfo")
  end
  if skillRaiseRows and skillRaiseRows[i] then
    error("boom: GetSkillLineInfo row " .. i)
  end
  local row = skillLines[i]
  if not row then return nil end
  if skillShape == "short" then
    return row.name, row.rank
  end
  return row.name, row.header == true, true, row.rank
end

-- A fresh tooltip per hover, so nothing carries over between cases.
local function hover(name)
  local gt = F.newTooltip({
    lines = { name, "Herbalism" },
    owner = UIParent,
    left = 300,
    bottom = 700,
    width = 180,
    height = 60,
  })
  _G.GameTooltip = gt
  gt.shown = true
  T:Poll(gt)
  return gt
end

local function panelRows()
  return P:TextLines()
end

local function hasRow(prefix)
  for _, l in ipairs(panelRows()) do
    if type(l) == "string" and l:sub(1, #prefix) == prefix then
      return true, l
    end
  end
  return false, nil
end

local function countRowsLike(prefix)
  local n = 0
  for _, l in ipairs(panelRows()) do
    if type(l) == "string" and l:sub(1, #prefix) == prefix then
      n = n + 1
    end
  end
  return n
end

local function diagText()
  chat = {}
  local ok, err = pcall(T.Diag, T)
  return ok, err, table.concat(chat, "\n")
end

-- A definitive answer is reused for Pr.TTL seconds; every case below changes
-- the client underneath, so the reuse window is dropped between them.
local function reset()
  Pr:Forget()
end

-- ── 1. THE SKINNER: no Herbalism → no block at all ────────────────────────
-- The character's skill lines are readable and contain no Herbalism row. That
-- is a definitive "no", so hovering Peacebloom must draw nothing — not the
-- node knowledge, and above all not somebody else's picks.
skillLines = {
  { name = "Skinning", rank = 300 },
  { name = "Cooking", rank = 75 },
  { name = "Swords", rank = 1, header = false },
}
skillShape = "4-field"
reset()
hover("Peacebloom")
check(P:IsShown() == false, "1: the skinner sees no herb block")
check(#panelRows() == 0, "1: no rows are left behind (got " .. #panelRows() .. ")")
local ring = T.RingEntries()
local last = ring[#ring]
check(last and last.panelShown == false, "1: the ring records that the panel stayed hidden")
check(last and type(last.skip) == "string" and last.skip:find("Herbalism", 1, true) ~= nil,
  "1: the ring says the reason is Herbalism (got " .. tostring(last and last.skip) .. ")")

-- ── 2. the same skinner, with eight of ANOTHER character's gathers on file ─
-- NodeTrailDB.herbs.maps is account-wide, so this is exactly the live state:
-- eight Peacebloom picks recorded by somebody else. None of it may surface.
for i = 1, 8 do
  ns.RecordHerb(1429, 0.4 + i / 100, 0.5, { { id = 2447, count = 2 } })
end
reset()
hover("Peacebloom")
check(P:IsShown() == false, "2: account-wide picks still draw no block on a non-herbalist")
check(#panelRows() == 0, "2: no picks row leaked into an empty panel")

-- ── 3. UNREADABLE profession → block, but NO picks line, and the diag says why
-- A client with none of the profession calls. The node knowledge is not
-- personal, so it still shows; the count is, so it must not.
skillLines = nil
local savedNum = GetNumSkillLines
local savedInfo = GetSkillLineInfo
local savedProf = GetProfessions
local savedProfInfo = GetProfessionInfo
GetNumSkillLines = nil
GetSkillLineInfo = nil
GetProfessions = nil
GetProfessionInfo = nil
C_TradeSkillUI = nil
reset()
hover("Peacebloom")
check(P:IsShown() == true, "3: an unreadable profession still shows the node knowledge")
local okBase, baseRow = hasRow("Peacebloom")
check(okBase, "3: the drop row is unchanged (base percentage is node knowledge)")
check(baseRow == "Peacebloom | 100% (base)", "3: the base line reads as before (got " .. tostring(baseRow) .. ")")
check(countRowsLike("Picks") == 0 and countRowsLike("Your picks") == 0,
  "3: NO picks line at all when the profession cannot be read")
check(#panelRows() >= 1, "3: the block still has its content")
local okD3, errD3, out3 = diagText()
check(okD3, "3: ttdiag does not raise with no profession API (" .. tostring(errD3) .. ")")
check(out3:find("profession:", 1, true) ~= nil, "3: ttdiag prints a profession section")
check(out3:find("herbalism=unknown", 1, true) ~= nil,
  "3: ttdiag says the profession is unknown (got:\n" .. out3 .. ")")
check(out3:find("without a picks line", 1, true) ~= nil,
  "3: ttdiag says the block carries no picks line")
-- The API line must be a MEASUREMENT, not a guess.
check(out3:find("api probed:", 1, true) ~= nil, "3: ttdiag lists the calls it probed")
check(out3:find("C_TradeSkillUI absent", 1, true) ~= nil,
  "3: ttdiag says which modern namespace is absent")

-- ── 4. THE HERBALIST: block shown, picks wording matches the storage ──────
-- `Picks: 8 (all characters)` — the number really is 8 here, and it really is
-- account-wide, so the words have to match. The eight records from case 2 are
-- still there.
GetNumSkillLines = savedNum
GetSkillLineInfo = savedInfo
GetProfessions = savedProf
GetProfessionInfo = savedProfInfo
skillLines = {
  { name = "Herbalism", rank = 300 },
  { name = "Alchemy", rank = 150 },
}
skillShape = "4-field"
reset()
hover("Peacebloom")
check(P:IsShown() == true, "4: the herbalist still sees the herb block")
local okPicks, picksRow = hasRow("Picks: ")
check(okPicks, "4: the herbalist sees a picks row")
check(picksRow == "Picks: 8 (all characters)",
  "4: the picks row says the count is account-wide and equals the 8 records (got "
    .. tostring(picksRow) .. ")")
check(countRowsLike("Your picks") == 0, "4: 'Your picks' is gone — it claimed the store was personal")
local okBase4, baseRow4 = hasRow("Peacebloom")
check(okBase4 and baseRow4 == "Peacebloom | 100% (base)",
  "4: the base percentage is unchanged (got " .. tostring(baseRow4) .. ")")
local okD4, _, out4 = diagText()
check(okD4, "4: ttdiag runs for the herbalist")
check(out4:find("herbalism=yes", 1, true) ~= nil,
  "4: ttdiag says the character is an herbalist (got:\n" .. out4 .. ")")
check(out4:find("from skill-lines", 1, true) ~= nil,
  "4: ttdiag names the API that answered")
check(out4:find("Herbalism rank 300", 1, true) ~= nil,
  "4: ttdiag reports what the skill line returned")
check(out4:find("GetNumSkillLines", 1, true) ~= nil,
  "4: ttdiag lists GetNumSkillLines among the probed calls")

-- ── 5. the account-wide count follows picks made on ANY map ───────────────
-- A pick on a different map (a different character's session) is the same
-- store, so the herbalist's row moves — proof the wording is not decorative.
ns.RecordHerb(1413, 0.2, 0.2, { { id = 2447, count = 1 } })
reset()
hover("Peacebloom")
local _, picks5 = hasRow("Picks: ")
check(picks5 == "Picks: 9 (all characters)",
  "5: a gather on another map raises the account-wide count (got " .. tostring(picks5) .. ")")

-- ── 6. an herbalist with nothing recorded says so, still account-wide ─────
NodeTrailDB.herbs.maps = {}
reset()
hover("Peacebloom")
local _, picks6 = hasRow("Picks: ")
check(picks6 == "Picks: none yet (all characters)",
  "6: an empty store reads as 'none yet (all characters)' (got " .. tostring(picks6) .. ")")

-- ── 7. the SHORT GetSkillLineInfo shape is read as well ────────────────────
-- Clients in the wild answer (name, rank) instead of the documented
-- (name, isHeader, isExpanded, rank). The rank must come from the type it
-- actually returned, or the gate silently reads `isHeader` and calls every
-- profession rank 1.
skillLines = { { name = "Herbalism", rank = 0 } }
skillShape = "short"
reset()
hover("Peacebloom")
check(P:IsShown() == false,
  "7: short shape, rank 0 -> not an herbalist (a rank is not a header flag)")
local okD7, _, out7 = diagText()
check(okD7 and out7:find("Herbalism line present at rank 0", 1, true) ~= nil,
  "7: ttdiag reports the rank it actually read (got:\n" .. tostring(out7) .. ")")

-- ── 8. a skill read that RAISES is unknown, not "no" ──────────────────────
-- A raising read must not hide the block: unknown falls through to "node
-- knowledge, no picks line", never to a confident "you are not an herbalist".
skillLines = { { name = "Herbalism", rank = 300 } }
skillShape = "4-field"
skillRaises = true
reset()
hover("Peacebloom")
check(P:IsShown() == true, "8: a raising skill read keeps the block (unknown, not 'no')")
check(countRowsLike("Picks") == 0, "8: ...and still claims no personal picks")
local okD8, _, out8 = diagText()
check(okD8, "8: ttdiag survives a raising skill read")
check(out8:find("herbalism=unknown", 1, true) ~= nil,
  "8: ttdiag reports unknown (got:\n" .. out8 .. ")")
check(out8:find("raised", 1, true) ~= nil, "8: ttdiag records that the read raised")
skillRaises = false

-- ── 9. the seven profession slots are a second, independent source ───────
-- A client with GetProfessions/GetProfessionInfo and no skill lines.
local savedNum, savedInfo = GetNumSkillLines, GetSkillLineInfo
GetNumSkillLines = nil
GetSkillLineInfo = nil
skillLines = nil
GetProfessions = function()
  return 1, 4, nil, nil, nil, nil, nil
end
GetProfessionInfo = function(index)
  if index == 1 then return "Skinning", "icon", 300, 300 end
  if index == 4 then return "Enchanting", "icon", 50, 75 end
  return nil
end
reset()
hover("Peacebloom")
check(P:IsShown() == false, "9: GetProfessions without Herbalism hides the block")
local okD9, _, out9 = diagText()
check(okD9 and out9:find("from professions", 1, true) ~= nil,
  "9: ttdiag names the professions tier (got:\n" .. tostring(out9) .. ")")

GetProfessions = function()
  return 2, 6, nil, nil, nil, nil, nil
end
GetProfessionInfo = function(index)
  if index == 2 then return "Herbalism", "icon", 1, 300 end
  if index == 6 then return "Alchemy", "icon", 300, 300 end
  return nil
end
reset()
hover("Peacebloom")
check(P:IsShown() == true, "9: GetProfessions naming Herbalism shows the block")
local _, picks9 = hasRow("Picks: ")
check(picks9 == "Picks: none yet (all characters)",
  "9: the picks wording is the same whichever API answered (got " .. tostring(picks9) .. ")")

-- ── 10. the OPEN-WINDOW call can confirm, never deny ─────────────────────
-- GetTradeSkillLine names the OPEN window. With no profession window open on
-- this client it reports something else, which says nothing about the
-- character: the answer must stay unknown (block, no picks line).
GetProfessions = nil
GetProfessionInfo = nil
GetTradeSkillLine = function() return "Alchemy" end
reset()
hover("Peacebloom")
check(P:IsShown() == true, "10: a non-Herbalism open window is not a verdict")
check(countRowsLike("Picks") == 0, "10: ...so no picks line is claimed")
local okD10, _, out10 = diagText()
check(okD10 and out10:find("herbalism=unknown", 1, true) ~= nil,
  "10: ttdiag says unknown (got:\n" .. tostring(out10) .. ")")
GetTradeSkillLine = function() return "Herbalism" end
reset()
hover("Peacebloom")
check(P:IsShown() == true, "10: the open window naming Herbalism shows the block")
local okP10, picks10 = hasRow("Picks: ")
check(okP10 and picks10 == "Picks: none yet (all characters)",
  "10: ...with the account-wide wording")

-- ── 11. the reuse window: a definitive answer is held for Pr.TTL ──────────
-- A client that answers the skill read only intermittently must not make the
-- block flicker: a definitive answer is reused for Pr.TTL seconds, and Pr:Forget
-- drops that window so the next hover reads the client again.
local fakeNow = 1000
GetTime = function() return fakeNow end
GetNumSkillLines = savedNum
GetSkillLineInfo = savedInfo
skillLines = { { name = "Herbalism", rank = 300 } }
skillShape = "4-field"
GetTradeSkillLine = nil
reset()
hover("Peacebloom")
check(P:IsShown() == true, "11: the herbalist answer is cached and the block shows")
fakeNow = 1001
skillLines = { { name = "Skinning", rank = 300 } } -- the client now says: no herbalism
hover("Peacebloom")
check(P:IsShown() == true, "11: inside the TTL the definitive answer is reused (no flicker)")
Pr:Forget()
hover("Peacebloom")
check(P:IsShown() == false, "11: Forget drops the window, so the fresh 'no' applies at once")
local okD11, _, out11 = diagText()
check(okD11 and out11:find("cache: hovers reuse", 1, true) ~= nil,
  "11: ttdiag reports the reuse window the hover path is using (got:\n" .. tostring(out11) .. ")")
GetTime = nil

-- ── 12. a PARTIALLY readable skill list is unknown, not "no" ───────────────
-- The dangerous direction: one row raises, the readable rows carry no
-- Herbalism. Answering "no" here would hide the block on a real herbalist, so
-- the tier must abstain and let the question fall through (here: nothing else
-- answers, so the answer is unknown -> block without a picks line).
skillLines = {
  { name = "Skinning", rank = 300 },
  { name = "Cooking", rank = 75 },
}
skillShape = "4-field"
skillRaises = false
skillRaiseRows = { [1] = true }
GetTradeSkillLine = nil
C_TradeSkillUI = nil
reset()
local mixedAnswer, mixedDetail = Pr:FromSkillLines(Pr)
check(mixedAnswer == nil,
  "12: a partially raised skill list abstains, never answers 'no' (got " .. tostring(mixedAnswer) .. ")")
check(type(mixedDetail) == "string" and mixedDetail:find("unreadable", 1, true) ~= nil,
  "12: the detail names the unreadable row (got " .. tostring(mixedDetail) .. ")")
local _, mixedInfo = Pr:Herbalism()
check(type(mixedInfo) == "table" and mixedInfo.herbalism == nil,
  "12: the gate answer is unknown, not false")
hover("Peacebloom")
check(P:IsShown() == true, "12: a partial read does not hide the block")
check(countRowsLike("Picks") == 0 and countRowsLike("Your picks") == 0,
  "12: ...and it still claims no picks")
local okD12, _, out12 = diagText()
check(okD12, "12: ttdiag survives a partially raised skill read")
check(okD12 and out12:find("herbalism=unknown", 1, true) ~= nil,
  "12: ttdiag says unknown (got:\n" .. tostring(out12) .. ")")
check(okD12 and out12:find("unreadable", 1, true) ~= nil,
  "12: ttdiag records why the skill tier abstained")
skillRaiseRows = nil

-- ── 13. a TABLE-shaped profession name is matched after decoding ──────────
-- profName() exists because some clients answer GetProfessionInfo with
-- `{ skillLineName = "Herbalism" }`. Matching the RAW return against a string
-- name reads that as "no Herbalism" and hides the block on an herbalist.
local tier1Num, tier1Info = GetNumSkillLines, GetSkillLineInfo
GetNumSkillLines = nil
GetSkillLineInfo = nil
GetProfessions = function() return 1, 4, nil, nil, nil, nil, nil end
GetProfessionInfo = function(index)
  if index == 1 then return { skillLineName = "Herbalism" }, "icon", 300, 300 end
  if index == 4 then return "Alchemy", "icon", 300, 300 end
  return nil
end
reset()
local tableAnswer, tableDetail = Pr:FromProfessions(Pr)
check(tableAnswer == true,
  "13: a table-shaped Herbalism name is recognised (got " .. tostring(tableAnswer)
    .. ": " .. tostring(tableDetail) .. ")")
hover("Peacebloom")
check(P:IsShown() == true, "13: the block shows for a table-shaped herbalist")
local okPicks13, picks13 = hasRow("Picks: ")
check(okPicks13 and picks13 == "Picks: none yet (all characters)",
  "13: ...with the account-wide picks wording (got " .. tostring(picks13) .. ")")
local okD13, _, out13 = diagText()
check(okD13 and out13:find("from professions", 1, true) ~= nil,
  "13: ttdiag names the professions tier (got:\n" .. tostring(out13) .. ")")

-- ...and a table-shaped NON-herb list is still a real "no".
GetProfessions = function() return 1, nil, nil, nil, nil, nil, nil end
GetProfessionInfo = function(index)
  if index == 1 then return { skillLineName = "Skinning" }, "icon", 300, 300 end
  return nil
end
reset()
local tableNo = Pr:FromProfessions(Pr)
check(tableNo == false, "13: a table-shaped non-herb list is still a definitive no")
hover("Peacebloom")
check(P:IsShown() == false, "13: ...so the block stays hidden for that character")
GetNumSkillLines, GetSkillLineInfo = tier1Num, tier1Info
GetProfessions = nil
GetProfessionInfo = nil

-- ── 15. a row that answers NO NAME is unknown, not a readable row ──────────
-- The round-3 residue, same class as case 12: `GetNumSkillLines` can
-- over-report, and indices past the end of the list answer "" rather than
-- raising. Reading "" as a row whose profession we saw lets the tier answer a
-- definitive "no" about names it never actually received — which hides the
-- block on a real herbalist.
skillLines = {
  { name = "Skinning", rank = 300 },
  { name = "", rank = 0 }, -- an over-reported row: the client has no name here
}
skillShape = "4-field"
skillRaises = false
skillRaiseRows = nil
GetTradeSkillLine = nil
C_TradeSkillUI = nil
reset()
local emptyAnswer, emptyDetail = Pr:FromSkillLines(Pr)
check(emptyAnswer == nil,
  "15: an empty-string row abstains, never answers 'no' (got " .. tostring(emptyAnswer) .. ")")
check(type(emptyDetail) == "string" and emptyDetail:find("unreadable", 1, true) ~= nil,
  "15: the detail names the unreadable row (got " .. tostring(emptyDetail) .. ")")
local _, emptyInfo = Pr:Herbalism()
check(type(emptyInfo) == "table" and emptyInfo.herbalism == nil,
  "15: the gate answer is unknown, not false")
hover("Peacebloom")
check(P:IsShown() == true, "15: an unnamed row does not hide the block")
check(countRowsLike("Picks") == 0 and countRowsLike("Your picks") == 0,
  "15: ...and it still claims no picks")
local okD15, _, out15 = diagText()
check(okD15, "15: ttdiag survives a nameless skill row")
check(okD15 and out15:find("herbalism=unknown", 1, true) ~= nil,
  "15: ttdiag says unknown (got:\n" .. tostring(out15) .. ")")

-- ── 16. a LISTED profession slot whose name cannot be decoded is unknown ──
-- GetProfessions answers nil for an empty slot, so a numeric index is a
-- learned profession by contract. A slot that comes back as a table profName()
-- cannot decode (`{ skillLine = "Herbalism" }`, `{}`) is therefore a read that
-- failed — never an empty slot. Treating it as empty lets one readable
-- non-herb slot carry a definitive "no" over the slot that might be Herbalism.
local t15Num, t15Info = GetNumSkillLines, GetSkillLineInfo
GetNumSkillLines = nil
GetSkillLineInfo = nil
skillLines = nil
GetProfessions = function() return 1, 4, 6, nil, nil, nil, nil end
GetProfessionInfo = function(index)
  -- 1 and 6 are LEARNED slots naming their profession in a shape this module
  -- cannot decode; 4 is a plain readable non-herb profession.
  if index == 1 then return { skillLine = "Herbalism" }, "icon", 300, 300 end
  if index == 4 then return "Alchemy", "icon", 300, 300 end
  if index == 6 then return {}, "icon", 1, 1 end
  return nil
end
reset()
local undecAnswer, undecDetail = Pr:FromProfessions(Pr)
check(undecAnswer == nil,
  "16: an undecodable name on a learned slot abstains, never answers 'no' (got "
    .. tostring(undecAnswer) .. ": " .. tostring(undecDetail) .. ")")
check(type(undecDetail) == "string" and undecDetail:find("unreadable", 1, true) ~= nil,
  "16: the detail counts the undecodable slots (got " .. tostring(undecDetail) .. ")")
local _, undecInfo = Pr:Herbalism()
check(type(undecInfo) == "table" and undecInfo.herbalism == nil,
  "16: the gate answer is unknown, not false")
hover("Peacebloom")
check(P:IsShown() == true, "16: an undecodable learned slot does not hide the block")
check(countRowsLike("Picks") == 0 and countRowsLike("Your picks") == 0,
  "16: ...and it still claims no picks")
local okD16, _, out16 = diagText()
check(okD16, "16: ttdiag survives an undecodable profession name")
check(okD16 and out16:find("herbalism=unknown", 1, true) ~= nil,
  "16: ttdiag says unknown (got:\n" .. tostring(out16) .. ")")
-- The same slots, decoded, still answer definitively in both directions: the
-- abstention must not swallow a real answer from this tier.
GetProfessions = function() return 1, 4, nil, nil, nil, nil, nil end
GetProfessionInfo = function(index)
  if index == 1 then return "Skinning", "icon", 300, 300 end
  if index == 4 then return "Alchemy", "icon", 300, 300 end
  return nil
end
reset()
local readableNo = Pr:FromProfessions(Pr)
check(readableNo == false,
  "16: a fully readable non-herb slot list is still a definitive no (got " .. tostring(readableNo) .. ")")
GetNumSkillLines, GetSkillLineInfo = t15Num, t15Info
GetProfessions = nil
GetProfessionInfo = nil

-- ── 14. the new module obeys the card's hard constraints ──────────────────
-- The profession reader is new code in NodeTrail: it may probe the client, but
-- it must not ask C_EventUtils for validity and must not register (or even
-- mention) the combat log event. It also must not write a frame of its own.
local profPath = root .. "/MightiePack/Modules/NodeTrail/Data/Profession.lua"
local pf = assert(io.open(profPath, "r"), "Data/Profession.lua exists")
local profSrc = pf:read("*a")
pf:close()
-- The CALL shape, not the word: the module's header says in prose that it asks
-- the client nothing restricted, and a comment cannot ask anything.
check(profSrc:find("C_EventUtils%s*[%.:(]") == nil,
  "11: Data/Profession.lua never calls C_EventUtils")
check(profSrc:find("COMBAT_LOG_EVENT_UNFILTERED", 1, true) == nil,
  "11: Data/Profession.lua never mentions COMBAT_LOG_EVENT_UNFILTERED")
check(profSrc:find("RegisterEvent", 1, true) == nil,
  "11: Data/Profession.lua registers no event (it is a read at hover time)")
check(profSrc:find("CreateFrame", 1, true) == nil,
  "11: Data/Profession.lua creates no frame")

-- ── 12. nothing raised along the way ──────────────────────────────────────
check(T._error == nil, "12: ns.Tooltip recorded no error (" .. tostring(T._error) .. ")")
check(P._error == nil, "12: the panel recorded no error (" .. tostring(P._error) .. ")")

if failed > 0 then
  io.stderr:write(failed .. " profession-gate check(s) failed\n")
  os.exit(1)
end
print("profession_gate_spec: ok")
