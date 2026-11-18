-- touchstone_log_entry_word_spec.lua — card t_baea7949.
--
-- THE DEFECT. The disagreement log is the third surface that names a verdict,
-- and it was the only one that could not name an ARBITRATED pair the way the
-- other two do. `ChestAdvisorDB.log` stored the verdict TOKEN and nothing about
-- the arbitration, so the Log tab asked `TOOLTIP_UI.word(e.verdict)` — the
-- pre-arbitration token map — and a pair the window and the tooltip call
-- "Sidegrade" read "Trade-off" in the log. The window's half of this was card
-- t_c8970547; this is the record's half.
--
-- THE DECISION (option A of the card, and why). The log is evidence of what the
-- advisor said at the moment the player wore the item, so the record carries
-- the arbitration's own state (`arbState`) and every reader of a stored entry
-- asks the same helper the other two surfaces ask (`TOOLTIP_UI.entryWord` ->
-- `wordFor`). Option B — label the column "as recorded" and keep printing the
-- token's word — would have made the log permanently apologise for a one-field
-- data gap, and the entry's `reason` is ALREADY the arbitrated sentence, so the
-- word and the line under it could name one entry two ways.
--
-- WHAT THIS SPEC PINS, through the real writer and the real renderers:
--
--   1. NEW ENTRY. `ChestAdvisor._logDisagreement` (the shipping recorder) on a
--      row the engine arbitrated to SIDEGRADE writes an entry whose `arbState`
--      is "SIDEGRADE"; the Log tab, the window row and the tooltip headline
--      then print the SAME word.
--   2. OLD ENTRY. A pre-change entry (the token only — the shape the field
--      writes) still loads and renders the token's word, is not guessed into a
--      judgement it never made, and round-trips through a SavedVariables-shaped
--      serialisation unchanged.
--   3. THE OTHER READER. `/up log` prints the same arbitrated word.
--   4. NON-VACUITY. The pre-fix source (`word(verdict)`) is quoted beside the
--      drawn word and the spec asserts the Log tab did NOT print it.
--
-- Nothing here re-derives a judgement: the state is the engine's
-- (`Verdict.arbitrate`), the word is the advisor's (`TOOLTIP_UI.wordFor`), and
-- every string asserted on is read off a surface (a drawn FontString, or the
-- tooltip's own line table, or the chat frame's own text).
--
-- Run from the repo root:  lua5.1 tests/touchstone_log_entry_word_spec.lua

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

local pkg = { PackVersion = function() return "0.5.0" end }
_G.MightiePack = pkg

tinsert = table.insert
tremove = table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
MightiePackDB = { modules = {} }
StatForgeDB = { ui = { scale = 1 }, firstUse = false }

-- The per-character store the recorder writes into (Touchstone.toc:7 declares
-- it). Started EMPTY: every entry this spec asserts on is written by this run or
-- is the documented pre-change shape, never a copy of the owner's save.
ChestAdvisorDB = {}

local TOUCH = root .. "/MightiePack/Modules/Touchstone/"
local function loadFile(name)
  local chunk, err = loadfile(TOUCH .. name)
  check(chunk ~= nil, "loadfile " .. name .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. name .. ": " .. tostring(e))
end

for _, name in ipairs({
  "Bootstrap.lua", "Constants.lua", "Weights.lua", "UI.lua",
  "UpgradesTab.lua", "LogTab.lua",
  "ChestAdvisor/Marks.lua", "ChestAdvisor/Verdict.lua", "ChestAdvisor/StatOrders.lua",
  "ChestAdvisor/Arbitration.lua", "ChestAdvisor/ChestAdvisor.lua",
}) do
  loadFile(name)
end

local SF = _G.StatForge
local CA = _G.ChestAdvisor
local V = _G.Verdict
check(type(SF) == "table", "the module loads")
check(type(CA) == "table", "the advisor loads")
check(type(V) == "table", "the engine loads")

local okEnable, enableErr = pcall(CA.Enable)
check(okEnable, "ChestAdvisor.Enable: " .. tostring(enableErr))
local TIP = type(CA) == "table" and CA.tooltipUI or nil
check(type(TIP) == "table", "ChestAdvisor.tooltipUI is published")
check(type(TIP) == "table" and type(TIP.entryWord) == "function",
  "the advisor publishes the stored-entry word (TOOLTIP_UI.entryWord)")
check(type(CA) == "table" and type(CA._logDisagreement) == "function",
  "the advisor publishes the disagreement recorder (_logDisagreement)")
if type(TIP) ~= "table" or type(TIP.entryWord) ~= "function"
  or type(CA) ~= "table" or type(CA._logDisagreement) ~= "function" then
  io.stderr:write("cannot continue without the advisor's log word\n")
  os.exit(1)
end

-- ── the pair, judged by the real engine ───────────────────────────────────────
-- Verbatim from tests/touchstone_arbitration_parity_spec.lua (the §5a measured
-- healer, MID): TRADE_C vs TRADE_E is the SIDEGRADE case.
local SPELL = { id = 19939, name = "Holy Light", rank = 5, cost = 190, castTimeMs = 2500 }
local MID = {
  pool = 2060, regenCasting = 5.5885, crit = 6.38, bonusHealing = 36, level = 34,
  regenMeasured = true, spell = SPELL,
  stats = { Intellect = 101, Spirit = 80 },
}
local SPEC = { role = "spell", class = "PALADIN", context = "raid" }
local TRADE_C = { Intellect = 6, Healing = 38 }
local TRADE_E = { Intellect = 12, Healing = 15 }

local LINK = "|cnIQ0:|Hitem:9001::::::::34:1::::::|h[Parity Chest of the Trade]|h|r"
local token, reason, detail = V.arbitrate(TRADE_C, TRADE_E, SPEC, MID)
check(token == "TRADE_OFF", "the pair is a token-level trade-off (" .. tostring(token) .. ")")
check(type(detail) == "table" and detail.state == "SIDEGRADE",
  "the engine arbitrated it to SIDEGRADE ("
    .. tostring(type(detail) == "table" and detail.state or nil) .. ")")

-- The row, in the shape the scan writes it (:7839 `arbitration = arbDet`).
local ROW = {
  id = 9001, bag = 0, slot = 5, slotWord = "Chest",
  verdict = token, reason = reason, arbitration = detail, role = "PALADIN",
}

-- ── leg 2 first: an OLD entry, so the store is oldest-first as in game ───────
-- The PRE-CHANGE SHAPE, field for field: the writer's own eight fields
-- (time, at, slot, slotName, link, verdict, reason, role) exactly as they sit in
-- a save written before this card. No `arbState` key — that is the point.
local OLD_LINK = "|cnIQ1:|Hitem:3270::::::::5:1::::::|h[Flax Vest]|h|r"
local OLD_ENTRY = {
  at = 1794333381, time = 501332.686, slot = 5, slotName = "chest",
  link = OLD_LINK, verdict = "TRADE_OFF", role = "PALADIN",
  reason = "weighted 12 [Holy] — more Intellect, less Healing",
}
ChestAdvisorDB.log = { OLD_ENTRY }

local function keyList(t)
  local out = {}
  for k in pairs(t or {}) do out[#out + 1] = tostring(k) end
  table.sort(out)
  return table.concat(out, ",")
end
check(keyList(OLD_ENTRY) == "at,link,reason,role,slot,slotName,time,verdict",
  "the old entry is the pre-change shape, eight fields, no arbState ("
    .. keyList(OLD_ENTRY) .. ")")

-- ── leg 1: the real recorder writes the arbitrated state ─────────────────────
_G.GetInventoryItemLink = function(unit, slot)
  if unit == "player" and slot == 5 then return LINK end
  return nil
end
CA.__verdicts = { [LINK] = ROW }
local okLog, logErr = pcall(CA._logDisagreement, 5)
check(okLog, "the recorder ran without raising: " .. tostring(logErr))

local log = ChestAdvisorDB.log
check(#log == 2, "the recorder appended exactly one entry ("
  .. tostring(#log) .. "; expected 2 with the old entry already stored)")
local new = log[2]
check(type(new) == "table", "the new entry exists")
if type(new) == "table" then
  check(new.link == LINK, "the new entry is this item (" .. tostring(new.link) .. ")")
  check(new.verdict == "TRADE_OFF", "the new entry still stores the TOKEN ("
    .. tostring(new.verdict) .. ")")
  check(new.arbState == "SIDEGRADE", "the new entry records the arbitration's state ("
    .. tostring(new.arbState) .. "; expected SIDEGRADE)")
  check(new.reason == reason,
    "the new entry's reason is the ARBITRATED sentence — the word above it must "
      .. "not be the token's")
  print("new entry: " .. string.format(
    "{verdict=%q, arbState=%q, reason=%q}", tostring(new.verdict),
    tostring(new.arbState), tostring(new.reason)))
end
print("old entry: " .. string.format(
  "{verdict=%q, arbState=%s, link=%q}", tostring(OLD_ENTRY.verdict),
  tostring(OLD_ENTRY.arbState), tostring(OLD_ENTRY.link)))

-- ── the words, read off the real surfaces ────────────────────────────────────
local function stripEscapes(text)
  text = tostring(text or "")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return text
end

local function findNamed(frame, name, seen)
  if type(frame) ~= "table" then return nil end
  if frame.Name == name then return frame end
  seen = seen or {}
  if seen[frame] then return nil end
  seen[frame] = true
  for _, child in ipairs(frame:GetChildren()) do
    local hit = findNamed(child, name, seen)
    if hit then return hit end
  end
  return nil
end

--- The tooltip's own first line for a row, and the word it headlines with.
local function tooltipHeadline(r)
  local lines = CA.tooltipLines(r)
  if type(lines) ~= "table" or type(lines[1]) ~= "table" then return nil, nil end
  local text = stripEscapes(lines[1].text)
  local word = text:match("^([^—]+)") or text
  return text, (word:gsub("%s+$", ""))
end

--- The window's ledger row word for a link (the drawn FontString).
local function windowWord(link)
  local seen, stack = {}, { UIParent }
  while #stack > 0 do
    local frame = table.remove(stack)
    if type(frame) == "table" and not seen[frame] then
      seen[frame] = true
      if frame.__link == link and type(frame.verdictWord) == "table" then
        local text = frame.verdictWord:GetText()
        if text ~= nil then return stripEscapes(text) end
      end
      for _, child in ipairs(frame:GetChildren() or {}) do stack[#stack + 1] = child end
    end
  end
  return nil
end

--- One drawn Log-tab row's verdict word, by pool index (oldest first).
local function logRowWord(index)
  local content = SF.GetContentFrame()
  local main = type(content) == "table" and content:GetParent() or nil
  local row = main and findNamed(main, "TouchstoneLogRow" .. tostring(index))
  if type(row) ~= "table" or type(row.verdictWord) ~= "table" then return nil end
  local text = row.verdictWord:GetText()
  if text == nil then return nil end
  return stripEscapes(text), (type(row.itemName) == "table" and row.itemName:GetText() or nil)
end

check(type(SF.ShowMain) == "function", "SF.ShowMain exists")
local okShow, showErr = pcall(SF.ShowMain, "upgrades")
check(okShow, 'SF.ShowMain("upgrades"): ' .. tostring(showErr))

CA.getVerdicts = function() return { [LINK] = ROW } end
SF.SelectTab("log")

local logWord, logItem = logRowWord(2)
local oldWord, oldItem = logRowWord(1)
local winWord = windowWord(LINK)
local tipText, tipWord = tooltipHeadline(ROW)
local tokenWord = TIP.word(ROW.verdict)

check(logWord ~= nil, "the Log tab drew a row for the arbitrated entry")
check(oldWord ~= nil, "the Log tab drew a row for the old entry")
check(winWord ~= nil, "the window drew a row for the arbitrated pair")
check(tipWord ~= nil, "the tooltip produced a headline for the arbitrated pair")

print("SIDEGRADE · Log tab row word    " .. string.format("%q", tostring(logWord)))
print("SIDEGRADE · window row word     " .. string.format("%q", tostring(winWord)))
print("SIDEGRADE · tooltip headline    " .. string.format("%q", tostring(tipWord)))
print("SIDEGRADE · tooltip line        " .. string.format("%q", tostring(tipText)))
print("SIDEGRADE · pre-fix token word  " .. string.format("%q", tostring(tokenWord)))
print("OLD entry · Log tab row word    " .. string.format("%q", tostring(oldWord)))

-- AC 1: one pair, one word, on all three surfaces.
check(logWord == TIP.words.SIDEGRADE,
  "the Log tab reads the model's word: expected "
    .. string.format("%q", tostring(TIP.words.SIDEGRADE)) .. ", got "
    .. string.format("%q", tostring(logWord)))
check(logWord == winWord,
  "the Log tab (" .. tostring(logWord) .. ") and the window row ("
    .. tostring(winWord) .. ") name the same pair the same way")
check(logWord == tipWord,
  "the Log tab (" .. tostring(logWord) .. ") and the tooltip headline ("
    .. tostring(tipWord) .. ") name the same pair the same way")

-- NON-VACUITY: the pre-fix source is `word(verdict)`, still a real function. If
-- the tab printed it, this leg names the Log tab.
check(tokenWord == "Trade-off",
  "the token map still says Trade-off for this token (" .. tostring(tokenWord)
    .. ") — so the two words really are different strings")
check(logWord ~= tokenWord,
  "the Log tab does NOT print the pre-arbitration word "
    .. string.format("%q", tostring(tokenWord)) .. " for a SIDEGRADE entry")

-- AC 2: the old entry renders the word it recorded, and is not invented into a
-- Sidegrade.
check(oldWord == TIP.word(OLD_ENTRY.verdict),
  "the old entry renders the token's word — expected "
    .. string.format("%q", tostring(TIP.word(OLD_ENTRY.verdict))) .. ", got "
    .. string.format("%q", tostring(oldWord)))
check(oldWord == "Trade-off",
  "the old entry reads Trade-off (got " .. string.format("%q", tostring(oldWord)) .. ")")
check(oldWord ~= TIP.words.SIDEGRADE,
  "the old entry is NOT guessed into a judgement the log never made")
check(OLD_ENTRY.arbState == nil,
  "reading an old entry does not invent an arbState on it ("
    .. tostring(OLD_ENTRY.arbState) .. ")")
check(keyList(OLD_ENTRY) == "at,link,reason,role,slot,slotName,time,verdict",
  "the old entry still has exactly its eight fields after render ("
    .. keyList(OLD_ENTRY) .. ")")

-- AC 2, the round trip: a SavedVariables-shaped literal carries the old entry
-- out and back with nothing added or lost.
local function serialise(value)
  local t = type(value)
  if t == "string" then return string.format("%q", value) end
  if t == "number" or t == "boolean" then return tostring(value) end
  if t ~= "table" then return "nil" end
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = ("[%q]=%s"):format(tostring(k), serialise(value[k]))
  end
  return "{" .. table.concat(parts, ",") .. "}"
end
local literal = "return " .. serialise(OLD_ENTRY)
local loader = loadstring or load
local back = assert(loader(literal))()
check(keyList(back) == keyList(OLD_ENTRY),
  "the old entry round-trips through a save-shaped literal with the same fields ("
    .. keyList(back) .. ")")
for _, k in ipairs({ "at", "time", "slot", "slotName", "link", "verdict", "role", "reason" }) do
  check(back[k] == OLD_ENTRY[k], "round trip preserved " .. k)
end
print("old entry literal: " .. literal)

-- ── leg 3: `/up log` — the other reader of a stored entry ────────────────────
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end,
  GetName = function() return "ChatFrame1" end }
local handler = SlashCmdList.CHESTADVISOR or SlashCmdList.UPGRADE or SlashCmdList.UP
check(type(handler) == "function", "/up is registered by Enable()")
if type(handler) == "function" then
  local okCmd, cmdErr = pcall(handler, "log")
  check(okCmd, "/up log did not raise: " .. tostring(cmdErr))
end
local printed = table.concat(chat, "\n")
print("chat: " .. printed:gsub("\n", " | "))
check(printed:find(TIP.words.SIDEGRADE, 1, true) ~= nil,
  "the /up log list prints the arbitrated word for the SIDEGRADE entry")
check(printed:find("Trade-off", 1, true) ~= nil,
  "the /up log list still prints Trade-off for the old entry")

if failed > 0 then
  io.stderr:write(tostring(failed) .. " check(s) failed\n")
  os.exit(1)
end
print("touchstone_log_entry_word_spec: ok")
