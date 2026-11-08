-- t_c0221fd7 — the BEAST tooltip: hovering a beast shows what its corpse and
-- its skinning have yielded, from our own recorded observations.
--
-- Mightie: "we are missing the skinning tooltip. we should have some
-- information when hovering over beasts that says what we might get if we kill
-- it and skin it. Same as herbing just another step in the middle."
--
-- Unlike herbs there is NO researched drop table behind these numbers, so this
-- spec pins the honesty rules as hard as the rendering:
--
--   1. the block opens with the CLIENT's creature name (display-only: a client
--      name may be SECRET, so it is never measured, sliced or concatenated);
--   2. "skinnable" is stated only when we know — a client call that answers a
--      boolean, else our own skin windows; no skin window yet says nothing;
--   3. corpse and skinning yields are separate sections, counts always, a
--      percentage ONLY once the sample reaches PERSONAL_MIN, and that
--      percentage is labelled as the player's own observation;
--   4. "kills seen: N · skinned: M" says how thin the evidence is;
--   5. a creature we have never seen says "no observations here yet" — never
--      zeros dressed as data;
--   6. a non-beast, a creature the client calls unskinnable, and a character
--      without Skinning all draw NOTHING;
--   7. the creature is matched by the NPC id from UnitGUID, not by its name
--      (names repeat across zones);
--   8. the store is read, never written: hovering must not create a bucket.
--
-- Everything below drives the REAL recorder (Modules/Skinning/Record.lua) to
-- build its records — the spec never hand-writes a record shape — and then the
-- real hover poller over a fake client.
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

time = time or os.time
CopyTable = function(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = type(v) == "table" and CopyTable(v) or v
  end
  return c
end
GetSpellInfo = function(id)
  local map = { [2366] = "Herb Gathering", [2259] = "Alchemy", [8613] = "Skinning" }
  return map[id]
end
SlashCmdList = {}
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end }

-- ── the client's item data (names must come from HERE, not a hardcoded table) ─
local ITEM_NAMES = {
  [2319] = "Medium Leather",
  [2934] = "Ruined Leather Scrappings",
  [5466] = "Scorpid Stinger",
  [4867] = "Broken Scorpid Leg",
}
GetItemInfo = function(id) return ITEM_NAMES[id] end

-- ── the character's professions, behind one stub ───────────────────────────
local skillLines = {
  { name = "Skinning", rank = 300 },
  { name = "Herbalism", rank = 300 },
}
GetNumSkillLines = function() return #skillLines end
GetSkillLineInfo = function(i)
  local row = skillLines[i]
  if not row then return nil end
  return row.name, false, true, row.rank
end

-- ── the hovered unit ───────────────────────────────────────────────────────
local unit = { exists = false, guid = nil, ctype = "Beast", name = "Clattering Scorpid" }
UnitExists = function(u) return u == "mouseover" and unit.exists == true end
UnitGUID = function(u)
  if u ~= "mouseover" then return nil end
  return unit.guid
end
UnitCreatureType = function(u)
  if u ~= "mouseover" then return nil end
  return unit.ctype
end
UnitName = function(u)
  if u ~= "mouseover" then return nil end
  return unit.name
end

local pkg = {}
local function loadFile(path)
  local f = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path))
  f("MightiePack", pkg)
end
local function loadAddon(path)
  local f = assert(loadfile(root .. "/MightiePack/" .. path))
  f("MightiePack", pkg)
end

loadFile("locale/enUS.lua")
loadFile("Config.lua")
loadFile("Data/Recorder.lua")
loadFile("Data/HerbData.lua")
loadFile("Data/Profession.lua")
-- The beast block's data module. On a tree that predates this card the file is
-- absent: load it leniently so the checks below REPORT that ("the beast block
-- does not exist") instead of dying in a traceback.
pcall(loadFile, "Data/SkinHints.lua")
loadFile("Data/Recipes.lua")
loadFile("UI/TooltipPanel.lua")
loadFile("UI/Tooltip.lua")
loadFile("Core.lua")
-- The recorder the beast block reads. Loaded AFTER NodeTrail's UI, exactly as
-- the TOC does — which is why SkinHints resolves it at call time.
loadAddon("Modules/Skinning/Record.lua")

local ns = pkg.NodeTrail
local T = ns.Tooltip
local P = ns.TooltipPanel
local Pr = ns.Profession
local H = ns.SkinHints
local R = pkg.Skinning.Recorder

local function minFloor()
  if type(H) == "table" and type(H.Min) == "function" then
    return H.Min()
  end
  return nil
end

check(type(H) == "table", "0: Data/SkinHints.lua loaded (the beast block's data build)")
check(type(T.BuildBeastLines) == "function",
  "0: ns.Tooltip.BuildBeastLines exists (the hover path asks it about a beast)")
check(type(R) == "table" and type(R.CreatureID) == "function",
  "0: the skinning recorder is loaded (this spec drives the real one)")

-- The recorder keys records per character: Name-Realm.
GetUnitName = function(u) if u == "player" then return "Skinner" end return nil end
GetRealmName = function() return "TestRealm" end

-- The sub-toggle ON, so the recorder's records land in the DB the panel reads.
NodeTrailDB = {
  recipes = {}, profile = {},
  herbs = { schema = 1, total = 0, maps = {} },
  skinning = { enabled = true },
}

local function reset()
  Pr:Forget()
end

-- ── records, built by calling the real recorder ────────────────────────────
local CID = 3125 -- the Clattering Scorpid of the acceptance criteria
local seq = 0

local function guidOf(cid, n)
  -- The creature entry is the second-to-last GUID field (R.CreatureID).
  return ("Creature-0-7072-1-48-%d-%012X"):format(cid, n)
end

--- One observed corpse: death, corpse loot, a successful 8613 cast, skin loot.
--- `corpseItems` / `skinItems` are the probe's tuple shape ({ id, name, qty }).
local function observe(cid, corpseItems, skinItems)
  seq = seq + 1
  local g = guidOf(cid, seq)
  R:OnKill({ guid = g, t = 1000 + seq, name = "Clattering Scorpid" })
  if corpseItems then
    R:OnCorpseLoot({ guid = g, t = 1001 + seq, items = corpseItems })
  end
  if skinItems then
    R:OnSkinCast({ guid = g, t = 1002 + seq, spellID = 8613 })
    R:OnSkinLoot({ guid = g, t = 1003 + seq, items = skinItems })
  end
  return g
end

local CORPSE = { { id = 5466, name = "Scorpid Stinger", qty = 1 } }
local SKIN = { { id = 2319, name = "Medium Leather", qty = 2 } }

-- ── hover ─────────────────────────────────────────────────────────────────
local function hoverBeast(opts)
  opts = opts or {}
  unit.exists = true
  unit.guid = opts.guid
  unit.ctype = opts.ctype or "Beast"
  unit.name = opts.name or "Clattering Scorpid"
  local gt = F.newTooltip({
    lines = { "Clattering Scorpid", "Beast" },
    owner = UIParent,
    left = 300,
    bottom = 700,
    width = opts.width or 180,
    height = 60,
  })
  _G.GameTooltip = gt
  gt.shown = true
  -- Lenient on purpose: a tree without the beast path raises inside the poll,
  -- and the checks below are what must report that (not a traceback).
  pcall(T.Poll, T, gt)
  return gt
end

local function rows()
  return P:TextLines()
end

local function joined()
  return table.concat(rows(), "\n")
end

local function findRow(text)
  for _, l in ipairs(rows()) do
    if l == text then return true end
  end
  return false
end

local function findPrefix(prefix)
  for _, l in ipairs(rows()) do
    if type(l) == "string" and l:sub(1, #prefix) == prefix then return true, l end
  end
  return false, nil
end

local function diagText()
  chat = {}
  local ok, err = pcall(T.Diag, T)
  return ok, err, table.concat(chat, "\n")
end

-- ═══ 1. ENOUGH EVIDENCE: percentages, both sections, and the totals line ═══
-- 12 observed kills, 10 of them skinned. PERSONAL_MIN is 10, so every row may
-- carry a percentage — labelled as the player's own observation.
for _ = 1, 9 do
  observe(CID, CORPSE, SKIN)
end
observe(CID, { { id = 4867, name = "Broken Scorpid Leg", qty = 1 } }, nil)
observe(CID, CORPSE, SKIN)
observe(CID, CORPSE, nil) -- killed, never skinned
reset()
hoverBeast({ guid = guidOf(CID, 1) })

check(P:IsShown() == true, "1: a beast with records shows the block")
check(minFloor() == 10, "1: the evidence floor is HerbData.PERSONAL_MIN (got " .. tostring(minFloor()) .. ")")
local r = rows()
check(r[1] == "Clattering Scorpid", "1: the block opens with the creature's name (got "
  .. tostring(r[1]) .. ")")
check(findRow("skinnable · skin windows recorded: 10"),
  "1: skinnability comes from our own skin windows (got:\n" .. joined() .. ")")
check(findRow("corpse loot"), "1: the corpse section is labelled")
check(findRow("Scorpid Stinger x11 | 92% (yours)"),
  "1: corpse rows carry count + a percentage labelled (yours) (got:\n" .. joined() .. ")")
check(findRow("Broken Scorpid Leg x1 | 8% (yours)"),
  "1: a rare corpse item is a percentage of the kills, not of the whole drop list (got:\n" .. joined() .. ")")
check(findRow("skinned"), "1: the skinning section is labelled")
check(findRow("Medium Leather x20 | 100% (yours)"),
  "1: skin rows carry count + a percentage of the corpses that were skinned (got:\n" .. joined() .. ")")
check(findRow("kills seen: 12 · skinned: 10"),
  "1: the totals line states how thin the evidence is (got:\n" .. joined() .. ")")
local at = {}
for i, line in ipairs(r) do at[line] = at[line] or i end
check(at["corpse loot"] and at["skinned"] and at["corpse loot"] < at["skinned"],
  "1: the corpse section precedes the skinning section (got:\n" .. joined() .. ")")
check(at["skinned"] and at["kills seen: 12 · skinned: 10"]
  and at["skinned"] < at["kills seen: 12 · skinned: 10"] and at["kills seen: 12 · skinned: 10"] == #r,
  "1: the totals line closes the block (got:\n" .. joined() .. ")")

-- No researched table exists for a beast: every percentage is OURS, and none
-- is printed without that label.
for _, row in ipairs({ "Scorpid Stinger x11 | 92% (yours)", "Medium Leather x20 | 100% (yours)" }) do
  check(findRow(row), "1: labelled percentage row " .. row)
end
local _, baseLabel = findPrefix("Scorpid Stinger")
check(baseLabel == nil or baseLabel:find("(base)", 1, true) == nil,
  "1: nothing here is presented as a base/global rate")

-- ═══ 2. THIN EVIDENCE: counts only, no percentage at all ══════════════════
local THIN = 3126
for _ = 1, 3 do
  observe(THIN, CORPSE, SKIN)
end
reset()
hoverBeast({ guid = guidOf(THIN, 1) })
check(P:IsShown() == true, "2: a thin sample still shows its counts")
local _, thinCorpse = findPrefix("Scorpid Stinger x3")
check(thinCorpse == "Scorpid Stinger x3",
  "2: below PERSONAL_MIN the corpse row is a count with no percentage (got "
  .. tostring(thinCorpse) .. ")")
local _, thinSkin = findPrefix("Medium Leather x6")
check(thinSkin == "Medium Leather x6",
  "2: below PERSONAL_MIN the skin row is a count with no percentage (got "
  .. tostring(thinSkin) .. ")")
check(findRow("kills seen: 3 · skinned: 3"),
  "2: the totals line still says the sample is three (got:\n" .. joined() .. ")")
check(joined():find("%", 1, true) == nil, "2: no percentage appears in a thin block (got:\n"
  .. joined() .. ")")

-- ═══ 3. UNKNOWN CREATURE: the name + "no observations here yet" ════════════
local UNKNOWN = 9001
reset()
hoverBeast({ guid = guidOf(UNKNOWN, 500), name = "Young Stranglethorn Tiger" })
check(P:IsShown() == true, "3: a beast we have never recorded says so instead of hiding")
check(rows()[1] == "Young Stranglethorn Tiger",
  "3: the client's name still leads the block (got " .. tostring(rows()[1]) .. ")")
check(findRow("no observations here yet"),
  "3: an unknown creature says 'no observations here yet' (got:\n" .. joined() .. ")")
check(joined():find("kills seen:", 1, true) == nil,
  "3: no totals line is printed for zero records (got:\n" .. joined() .. ")")

-- ═══ 4. MATCHED BY NPC ID, NOT BY NAME ════════════════════════════════════
-- A DIFFERENT creature that the client displays under the same name. Its
-- records must not be borrowed: names repeat across zones.
local IMPOSTOR = 3124
for _ = 1, 12 do
  observe(IMPOSTOR, { { id = 2319, name = "Medium Leather", qty = 9 } }, SKIN)
end
reset()
hoverBeast({ guid = guidOf(CID, 1), name = "Clattering Scorpid" })
check(findRow("no observations here yet") == false,
  "4: our own creature still resolves its own records")
check(findRow("Scorpid Stinger x11 | 92% (yours)"),
  "4: the ids do not bleed into each other (got:\n" .. joined() .. ")")
reset()
hoverBeast({ guid = guidOf(UNKNOWN, 501), name = "Clattering Scorpid" })
check(findRow("no observations here yet"),
  "4: a same-name creature with no records of its own is not given another's numbers (got:\n"
  .. joined() .. ")")
check(findRow("Medium Leather x108 | 100% (yours)") == false,
  "4: the impostor's 108 hides never appear under the wrong NPC id")

-- ═══ 5. NON-BEASTS DRAW NOTHING ══════════════════════════════════════════
for _, ctype in ipairs({ "Humanoid", "Mechanical", "Undead", "Elemental", "Dragonkin" }) do
  reset()
  hoverBeast({ guid = guidOf(CID, 1), ctype = ctype })
  check(P:IsShown() == false, "5: a " .. ctype .. " hover draws no beast block")
end
-- ...and an unreadable creature type is not a licence to guess.
reset()
local savedType = UnitCreatureType
UnitCreatureType = nil
hoverBeast({ guid = guidOf(CID, 1) })
check(P:IsShown() == false, "5: an unreadable creature type hides the block (never guess a beast)")
UnitCreatureType = savedType

-- A player or a pet has a GUID that is not a Creature GUID: nothing.
reset()
hoverBeast({ guid = "Player-1-00000001" })
check(P:IsShown() == false, "5: a player GUID draws nothing")
reset()
hoverBeast({ guid = "Pet-0-0000-0000-0000000000" })
check(P:IsShown() == false, "5: a pet GUID draws nothing")

-- ═══ 6. NOT SKINNABLE, when the CLIENT says so ════════════════════════════
-- The card allows the client's own creature data when the client exposes one.
-- This client does not, so the call is stubbed here to prove the gate exists
-- and that a "no" from it hides the block instead of printing a guess.
reset()
UnitIsSkinnable = function(u) return false end
hoverBeast({ guid = guidOf(CID, 1) })
check(P:IsShown() == false, "6: a creature the client calls not skinnable draws nothing")
local okD6, errD6, out6 = diagText()
check(okD6, "6: ttdiag does not raise (" .. tostring(errD6) .. ")")
check(out6:find("UnitIsSkinnable", 1, true) ~= nil,
  "6: ttdiag names the client call it measured (got:\n" .. out6 .. ")")
UnitIsSkinnable = function(u) return true end
reset()
hoverBeast({ guid = guidOf(CID, 1) })
check(P:IsShown() == true, "6: a 'yes' from the same call still shows the block")
check(findRow("skinnable"), "6: the client's own answer is printed as 'skinnable' (got:\n"
  .. joined() .. ")")
UnitIsSkinnable = nil

-- With no client call (the real client), and no skin window yet, the line is
-- LEFT OUT rather than guessed.
local NOSKIN = 3127
observe(NOSKIN, CORPSE, nil) -- killed, looted, never skinned
reset()
hoverBeast({ guid = guidOf(NOSKIN, 1) })
check(P:IsShown() == true, "6: kills with no skin window still show the corpse side")
local anySkinLine = false
for _, l in ipairs(rows()) do
  if type(l) == "string" and (l == "skinnable" or l == "not skinnable"
    or l:sub(1, 10) == "skinnable ") then
    anySkinLine = true
  end
end
check(anySkinLine == false, "6: with no evidence of skinnability the line is omitted, not guessed (got:\n"
  .. joined() .. ")")
check(findRow("kills seen: 1 · skinned: 0"),
  "6: the totals line says one kill and no skins (got:\n" .. joined() .. ")")

-- ═══ 7. THE PROFESSION GATE ═══════════════════════════════════════════════
-- A character with no Skinning sees NOTHING — the same gate as the herb block.
skillLines = { { name = "Herbalism", rank = 300 }, { name = "Cooking", rank = 75 } }
reset()
hoverBeast({ guid = guidOf(CID, 1) })
check(P:IsShown() == false, "7: a non-skinner sees no beast block")
local ring = T.RingEntries()
local last = ring[#ring]
check(last and last.kind == "beast", "7: the ring says this was a beast evaluation")
check(last and type(last.skip) == "string" and last.skip:find("Skinning", 1, true) ~= nil,
  "7: the ring names Skinning as the reason (got " .. tostring(last and last.skip) .. ")")

-- A skinner sees it again.
skillLines = { { name = "Skinning", rank = 300 } }
reset()
hoverBeast({ guid = guidOf(CID, 1) })
check(P:IsShown() == true, "7: the skinner sees the block")

-- An UNREADABLE profession (no skill API at all) still shows it: these records
-- are bucketed per character, so they cannot be somebody else's numbers.
local savedNum, savedInfo = GetNumSkillLines, GetSkillLineInfo
local savedProf, savedProfInfo = GetProfessions, GetProfessionInfo
GetNumSkillLines, GetSkillLineInfo = nil, nil
GetProfessions, GetProfessionInfo = nil, nil
C_TradeSkillUI = nil
reset()
hoverBeast({ guid = guidOf(CID, 1) })
check(P:IsShown() == true, "7: an unreadable profession still shows this character's own records")
local okD7, errD7, out7 = diagText()
check(okD7, "7: ttdiag does not raise (" .. tostring(errD7) .. ")")
check(out7:find("skinning=unknown", 1, true) ~= nil,
  "7: ttdiag reports the skinning read as unknown (got:\n" .. out7 .. ")")
GetNumSkillLines, GetSkillLineInfo = savedNum, savedInfo
GetProfessions, GetProfessionInfo = savedProf, savedProfInfo
skillLines = { { name = "Skinning", rank = 300 } }
reset()

-- ═══ 8. A SECRET CREATURE NAME IS SHOWN, NEVER MEASURED ═══════════════════
-- The live client can hand back a SECRET string for a creature name: it may be
-- displayed, but `#`, concatenation and formatting all raise. Model that with a
-- userdata whose __len/__concat raise and whose display path works, then prove
-- the hover never takes any of those reads.
local PAYLOAD = "Clattering Scorpid"
local measuredSecret, formattedSecret, convertedSecret = 0, 0, 0
local function secretName()
  local u = newproxy(true)
  local mt = getmetatable(u)
  mt.__payload = PAYLOAD
  mt.__len = function()
    measuredSecret = measuredSecret + 1
    error("attempt to get length of a secret string value", 2)
  end
  mt.__concat = function()
    formattedSecret = formattedSecret + 1
    error("attempt to concatenate a secret value", 2)
  end
  mt.__tostring = function()
    convertedSecret = convertedSecret + 1
    return PAYLOAD
  end
  return u
end
issecretvalue = function(v)
  if type(v) ~= "userdata" then return false end
  local mt = getmetatable(v)
  return type(mt) == "table" and mt.__payload ~= nil
end
-- The client's own display path accepts a secret; its MEASURING path raises on
-- one (that is the whole contract). Wrap the panel's font strings so the spec
-- can tell the two apart.
local savedCreateFrame = CreateFrame
CreateFrame = function(kind, name, parent)
  local f = savedCreateFrame(kind, name, parent)
  local makeFS = f.CreateFontString
  f.CreateFontString = function(self, a, b, c)
    local fs = makeFS(self, a, b, c)
    local setText, getWidth = fs.SetText, fs.GetStringWidth
    fs.SetText = function(s, v)
      if type(v) == "userdata" then
        s.rawValue = v
        s.text = ""
        return
      end
      setText(s, v)
    end
    fs.GetStringWidth = function(s)
      if s.rawValue ~= nil then
        measuredSecret = measuredSecret + 1
        error("attempt to get length of a secret string value", 2)
      end
      return getWidth(s)
    end
    return fs
  end
  return f
end
P.frame = nil -- force a fresh panel through the wrapped factory
P._pool = nil
P._hasRows = false

local secret = secretName()
reset()
hoverBeast({ guid = guidOf(CID, 1), name = secret })
check(P:IsShown() == true, "8: a secret creature name does not cost the block")
check(measuredSecret == 0, "8: the secret name was never measured (# taken "
  .. measuredSecret .. " time(s))")
check(formattedSecret == 0, "8: the secret name was never concatenated ("
  .. formattedSecret .. " time(s))")
check(convertedSecret == 0, "8: the secret name was never converted with tostring ("
  .. convertedSecret .. " time(s))")
local shownName = rows()[1]
check(type(shownName) == "userdata" and getmetatable(shownName).__payload == PAYLOAD,
  "8: the secret name is carried to the panel whole (got " .. type(shownName) .. ")")
check(findRow("kills seen: 12 · skinned: 10") or findRow("corpse loot"),
  "8: the data rows are still rendered below the secret name (got:\n"
  .. table.concat({ rows()[2] or "", rows()[3] or "" }, " / ") .. ")")
-- The name is carried but unmeasurable, so the width floor comes from the
-- client's own tooltip rect instead of a fabricated measurement.
check(type(P.rawRows) == "number" and P.rawRows == 1, "8: one row is marked as the client's own text")
check((P.width or 0) >= 180 - 0.01, "8: the panel is at least as wide as the tooltip that holds that name (got "
  .. tostring(P.width) .. ")")
check(P.covers == true, "8: the coverage verdict still holds for the text WE measured")
CreateFrame = savedCreateFrame
issecretvalue = nil
P.frame = nil
P._pool = nil
P._hasRows = false

-- ═══ 9. THE STORE IS READ, NEVER WRITTEN ══════════════════════════════════
-- A character with no bucket yet: hovering must not create one in the saved
-- variables, and must still answer honestly.
local key = R.CharKey()
NodeTrailDB.skinning.chars = nil
reset()
hoverBeast({ guid = guidOf(CID, 1) })
check(NodeTrailDB.skinning.chars == nil,
  "9: a hover did not create a saved-variable bucket")
check(findRow("no observations here yet"),
  "9: with no store at all the block says so (got:\n" .. joined() .. ")")
check(NodeTrailDB.skinning.enabled == true,
  "9: the tooltip did not touch the sub-toggle")

-- ═══ 10. THE HOVER WRITES NOTHING INTO THE TOOLTIP ════════════════════════
NodeTrailDB.skinning.chars = nil -- rebuild the store through the recorder
for i = 1, 12 do end
local rebuild = R:GetDB()
check(type(rebuild) == "table" and type(rebuild.records) == "table",
  "10: the recorder's own store still bootstraps")
local g10 = guidOf(CID, 900)
R:OnKill({ guid = g10, t = 5000, name = "Clattering Scorpid" })
R:OnCorpseLoot({ guid = g10, t = 5001, items = CORPSE })
reset()
unit.exists = true
unit.guid = g10
unit.ctype = "Beast"
unit.name = "Clattering Scorpid"
local gtSource = F.newTooltip({ lines = { "Clattering Scorpid", "Beast" }, owner = UIParent,
  left = 300, bottom = 700, width = 180, height = 60 })
local proxy, writes = F.readOnly(gtSource, "GameTooltip")
_G.GameTooltip = proxy
gtSource.shown = true
local okPoll, errPoll = pcall(T.Poll, T, proxy)
check(okPoll, "10: a write-hostile tooltip hover does not raise (" .. tostring(errPoll) .. ")")
check(#writes == 0, "10: zero writes to the tooltip (got " .. #writes .. ": "
  .. table.concat(writes, ", ") .. ")")
check(P:IsShown() == true, "10: the block still shows through a read-only tooltip")

-- ═══ 11. A PERCENTAGE THAT CANNOT BE TRUE IS NOT PRINTED ══════════════════
-- Some records are loot-only (a window never matched to an observed death), so
-- an item can be seen more often than there are "kills seen". 11 sightings out
-- of 10 kills is not "110%": the row falls back to the count, which is a fact.
local LOOTONLY = 3128
for i = 1, 10 do
  seq = seq + 1
  R:OnKill({ guid = guidOf(LOOTONLY, seq), t = 7000 + seq })
end
for i = 1, 11 do
  seq = seq + 1
  R:OnCorpseLoot({
    guid = guidOf(LOOTONLY, seq), t = 7100 + seq,
    items = { { id = 2319, name = "Medium Leather", qty = 1 } },
  })
end
reset()
hoverBeast({ guid = guidOf(LOOTONLY, 1) })
check(P:IsShown() == true, "11: loot-only records still render")
local _, impossible = findPrefix("Medium Leather x11")
check(impossible == "Medium Leather x11",
  "11: 11 sightings against 10 kills prints the count, never 110% (got "
  .. tostring(impossible) .. ")")
check(joined():find("%", 1, true) == nil,
  "11: no percentage appears when the item outnumbers its sample (got:\n" .. joined() .. ")")
check(findRow("kills seen: 10 · skinned: 0"),
  "11: the totals line counts only the deaths that were seen (got:\n" .. joined() .. ")")

-- ═══ 12. NOTHING ERRORED, AND NO EVENT SURFACE WAS TOUCHED ════════════════
check(T._error == nil, "12: ns.Tooltip recorded no error (" .. tostring(T._error) .. ")")
check(P._error == nil, "12: the panel recorded no error (" .. tostring(P._error) .. ")")
check(R._error == nil, "12: the recorder recorded no error (" .. tostring(R._error) .. ")")

if failed > 0 then
  io.stderr:write(failed .. " skin-tooltip check(s) failed\n")
  os.exit(1)
end
print(("skin_tooltip_spec: ok (%d row(s) on hover, %.0fpx wide, floor %s)"):format(
  #rows(), P.width or 0, tostring(minFloor())))
