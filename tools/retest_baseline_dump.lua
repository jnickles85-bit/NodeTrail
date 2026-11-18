-- tools/retest_baseline_dump.lua — card t_853291f0 (the Step 3 payload wiring).
--
-- Prints the three behaviours the OWNER retests after a re-pin, measured on a
-- pack tree, side by side with the tree's own wiring state:
--
--   [1] where the verdict line lands relative to a third-party tooltip block
--       (the item's own lines, then the verdict, then whatever TSM appends);
--   [2] a refusal: the word the player reads, the side it names, and whether a
--       judged-clause leaked onto a line that refused;
--   [3] whether StatOrders / Arbitration are reachable in `_G` once the pack's
--       own TOC order has been loaded (Step 3 payload, card t_13c807af).
--
-- The window is NOT printed here: tools/ledger_geometry_dump.lua already dumps
-- the chrome, the hosted body, the summary strip and the ledger rows, and it is
-- the file to diff before/after a re-pin.
--
-- This file ASSERTS NOTHING. It prints; a human (or a diff) compares. The
-- assertions live in tests/touchstone_tooltip_line_spec.lua (placement),
-- tests/touchstone_disclosure_spec.lua (refusal clause),
-- tests/touchstone_arbitration_parity_spec.lua (the payload is the pin's engine)
-- and the window specs.
--
--     lua5.1 tools/retest_baseline_dump.lua                 # this tree
--     lua5.1 tools/retest_baseline_dump.lua <pack-root>     # another tree
--
-- It is HARNESS evidence, labelled as such. A real in-game capture is the
-- owner's, and is not faked anywhere in this repo.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = (arg and arg[1]) or src:match("^(.*)/tools/[^/]+$") or "."
root = root:gsub("\\", "/")

local TOUCH = root .. "/MightiePack/Modules/Touchstone/"

-- ---- WoW stub (the shapes tests/touchstone_tooltip_line_spec.lua proves) ----
local chat, frames = {}, {}
local postCall, preCall

local function makeTexture()
  local t = {}
  for _, m in ipairs({ "SetPoint", "SetAllPoints", "SetTexture", "SetColorTexture",
    "SetTexCoord", "SetSize", "Hide", "Show", "SetBlendMode", "SetDesaturated" }) do
    t[m] = function() end
  end
  return t
end

local function makeFontString()
  local fs = { text = "" }
  fs.SetPoint = function() end
  fs.SetAllPoints = function() end
  fs.SetText = function(_, v) fs.text = v end
  fs.GetText = function() return fs.text end
  fs.SetTextColor = function() end
  fs.SetWidth = function() end
  fs.SetJustifyH = function() end
  fs.SetWordWrap = function() end
  fs.SetNonSpaceWrap = function() end
  fs.Hide = function() end
  fs.Show = function() end
  return fs
end

local function makeFrame(kind, name)
  local f = { kind = kind, name = name, events = {}, scripts = {}, children = {} }
  f.RegisterEvent = function(_, e) f.events[e] = true end
  f.UnregisterEvent = function(_, e) f.events[e] = nil end
  f.IsEventRegistered = function(_, e) return f.events[e] == true end
  f.SetScript = function(_, k, fn) f.scripts[k] = fn end
  f.GetScript = function(_, k) return f.scripts[k] end
  f.HookScript = function() end
  f.CreateTexture = function() return makeTexture() end
  f.CreateFontString = function() return makeFontString() end
  frames[#frames + 1] = f
  if name then _G[name] = f end
  setmetatable(f, { __index = function() return function() end end })
  return f
end

local function resetEnv()
  chat, frames = {}, {}
  SlashCmdList = setmetatable({}, { __newindex = function(t, k, v) rawset(t, k, v) end })
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
  CreateFrame = makeFrame
  UIParent = makeFrame("Frame", "UIParent")
  frames = {}
  MightiePackTouchstoneSkip = nil
  StatForge, StatForgeDB, ChestAdvisor, ChestAdvisorDB = nil, nil, nil, nil
  MightiePackDB = nil
  C_AddOns = { DoesAddOnExist = function() return false end }
  GetAddOnInfo, IsAddOnLoaded = nil, nil
  _G.ChestAdvisor_Frame = nil
  hooksecurefunc = function() end
  UnitClass = function() return "Paladin", "PALADIN" end
  UnitLevel = function() return 40 end
  C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 1, "Holy", "", 0, "HEALER" end,
  }
  postCall, preCall = nil, nil
  TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn) postCall = fn end,
    AddTooltipPreCall = function(kind, fn) preCall = fn end,
  }
  Enum = { TooltipDataType = { Item = 0 } }
  CreateColor = function(r, g, b) return { GetRGB = function() return r, g, b end } end
end

local function loaded(path, ...)
  local chunk, err = loadfile(path)
  if not chunk then error("loadfile " .. path .. ": " .. tostring(err)) end
  local ok, runErr = pcall(chunk, ...)
  if not ok then error("load " .. path .. ": " .. tostring(runErr)) end
end

-- ---- Load in the pack's OWN TOC order (Touchstone lines only) --------------
resetEnv()
local pkg = { Print = function(_, msg) chat[#chat + 1] = tostring(msg) end }
local tocLines = {}
do
  local f = assert(io.open(root .. "/MightiePack/MightiePack.toc", "r"))
  local text = f:read("*a")
  f:close()
  for line in text:gmatch("[^\r\n]+") do
    local t = line:gsub("^%s+", ""):gsub("%s+$", "")
    if t ~= "" and not t:match("^##") and t:match("^Modules/Touchstone/") then
      tocLines[#tocLines + 1] = t
    end
  end
end
for _, t in ipairs(tocLines) do
  loaded(root .. "/MightiePack/" .. t, "MightiePack", pkg)
end
ChestAdvisorDB = { role = {} }
local okEnable, enableErr = pcall(ChestAdvisor.Enable)
if not okEnable then error("ChestAdvisor.Enable: " .. tostring(enableErr)) end

print("== TREE " .. root)
print("touchstone toc entries: " .. #tocLines)
print("step3.StatOrders reachable: "
  .. tostring(type(StatForge) == "table" and rawget(StatForge, "StatOrders") ~= nil
    or rawget(_G, "StatOrders") ~= nil))
print("step3.Arbitration in _G: " .. tostring(type(rawget(_G, "Arbitration"))))
print("Verdict.arbitrate type: " .. tostring(type(Verdict.arbitrate)))
print("")

-- ---- Fixtures: the owner's pair (same bytes as touchstone_disclosure_spec) --
local PROC = "Chance on hit: Sear the target with a vortex of blazing wind,"
  .. " dealing 39 to 59 Holystorm damage. Deals 3 times as much damage to Wolves and Worgen."
local ENCHANT = "Enchanted: Weapon Damage +5"
local HEALING = "Equip: Increases healing done by up to 34 and damage done by up to 11"
  .. " for all magical spells and effects"
local ZWEI = { "Polished ZweiHander of Healing", "Two-Hand  Sword",
  "20 - 37 Damage  Speed 3.00", "(9.5 damage per second)", HEALING }
local WOLF_DISCLOSED = { "Wolfsbane", "Two-Hand  Sword", "69 - 105 Damage  Speed 3.40",
  "+9 Stamina", "+10 Intellect", PROC, ENCHANT }
local WOLF_NODPS = { "Wolfsbane", "Two-Hand  Sword", "+9 Stamina", "+10 Intellect" }

local SPEC = { class = "PALADIN", role = "spell", clientRole = "HEALER", level = 40 }
local SPEC_MELEE = { class = "WARRIOR", role = "melee", clientRole = "MELEE", level = 40 }
local ZWEI_LINK = "|cff9d9d9d|Hitem:31141|h[Polished ZweiHander of Healing]|h|r"

-- ---- [1] verdict line position above a third-party block -------------------
-- The verdict row is the ENGINE's own (Verdict.compareWeapon on the owner's
-- pair). The placement is the SHIPPED pre-call's.
local v1, r1 = Verdict.compareWeapon(ZWEI, WOLF_DISCLOSED, true, SPEC, true, nil)
print("[1] verdict line position (ZweiHander hovered vs equipped Wolfsbane)")
print("    engine: verdict=" .. tostring(v1) .. "  reason=" .. tostring(r1))

ChestAdvisor.__verdicts = {
  [ZWEI_LINK] = { id = 31141, verdict = v1, reason = r1 },
}
if type(preCall) ~= "function" then
  print("    FAIL: no item-tooltip pre-call was registered")
else
  local ownLines = {
    { leftText = "Polished ZweiHander of Healing" },
    { leftText = "Item Level 70" },
    { leftText = "20 - 37 Damage  Speed 3.00" },
    { leftText = "(9.5 damage per second)" },
  }
  local data = { hyperlink = ZWEI_LINK, lines = {} }
  for i, l in ipairs(ownLines) do data.lines[i] = l end
  local tip = { GetName = function() return "GameTooltip" end,
    NumLines = function() return 0 end, AddLine = function() end }
  local okPre, preErr = pcall(preCall, tip, data)
  if not okPre then
    print("    FAIL: pre-call raised: " .. tostring(preErr))
  else
    local verdictAt = #data.lines
    data.lines[#data.lines + 1] = { leftText = "TSM: General Info" }
    local tsmAt = #data.lines
    for i, l in ipairs(data.lines) do
      print(string.format("    line %d: %s", i, tostring(l.leftText)))
    end
    print(string.format("    verdict at %d, third-party block at %d, verdict ABOVE: %s",
      verdictAt, tsmAt, tostring(verdictAt < tsmAt)))
  end
end
print("")

-- ---- [2] a refusal: side named, no judged-clause ---------------------------
-- A MELEE spec takes the DPS comparator. The WORN weapon's damage line is
-- unreadable, so the comparator refuses and says WHICH side it could not read.
-- The line the player sees is the pack's own renderer output.
local v2, r2 = Verdict.compareWeapon(ZWEI, WOLF_NODPS, true, SPEC_MELEE, true, nil)
local row = {
  id = 31141, lines = ZWEI, chestWornLines = WOLF_NODPS,
  class = SPEC_MELEE.class, role = SPEC_MELEE.role, verdict = v2, reason = r2,
}
local lines = ChestAdvisor.tooltipLines(row)
local rendered = ""
if type(lines) == "table" and lines[1] ~= nil then
  rendered = tostring(lines[1].text):gsub("^|c%x%x%x%x%x%x%x%x", ""):gsub("|r$", "")
end
local judged = select(2, rendered:gsub("%(judged", ""))
print("[2] refusal (worn weapon's dps unreadable)")
print("    engine: verdict=" .. tostring(v2))
print("    engine reason: " .. tostring(r2))
print("    rendered: " .. rendered)
print("    names the worn side: " .. tostring(tostring(r2):find("worn", 1, true) ~= nil))
print("    '(judged' clauses in the line: " .. judged)
print("")

-- ---- [3] the window ------------------------------------------------------
print("[3] window: run tools/ledger_geometry_dump.lua on this tree and diff it")
print("PROBE OK")
