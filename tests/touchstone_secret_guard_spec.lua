-- The PR #22 secret-values guard must be present in the shipped Verdict.lua.
-- CI cannot clone the private StatForge source, so this is a file-level check
-- that the playerHitPercent path still refuses secret numbers.

local function read(path)
  local f, err = io.open(path, "r")
  assert(f, "could not open " .. path .. ": " .. tostring(err))
  local t = f:read("*a")
  f:close()
  return t
end

local function check(cond, msg)
  if not cond then
    io.stderr:write("FAIL " .. msg .. "\n")
    os.exit(1)
  end
end

local path = "MightiePack/Modules/Touchstone/ChestAdvisor/Verdict.lua"
local text = read(path)
local start = text:find("function Verdict.playerHitPercent", 1, true)
check(start ~= nil, path .. " defines Verdict.playerHitPercent")
local nxt = text:find("\nfunction ", start + 1, true)
local body = text:sub(start, nxt and (nxt - 1) or #text)
local preface = text:sub(math.max(1, start - 2500), start - 1)

check(preface:find("local function isSecretNumber", 1, true) ~= nil,
  "isSecretNumber helper sits above playerHitPercent")
check(preface:find("issecretvalue", 1, true) ~= nil,
  "isSecretNumber calls issecretvalue")
check(preface:find("local function pcallNumber", 1, true) ~= nil,
  "pcallNumber helper sits above playerHitPercent")
check(body:find("pcallNumber(GetHitModifier)", 1, true) ~= nil,
  "melee branch reads GetHitModifier through pcallNumber")
check(body:find("pcallNumber(GetSpellHitModifier)", 1, true) ~= nil,
  "spell branch reads GetSpellHitModifier through pcallNumber")
check(body:find("if bSec or mSec then return nil end", 1, true) ~= nil,
  "playerHitPercent refuses the sum when either half is secret")

-- Combat defer lives in ChestAdvisor.scan
local ca = read("MightiePack/Modules/Touchstone/ChestAdvisor/ChestAdvisor.lua")
check(ca:find("UnitAffectingCombat", 1, true) ~= nil,
  "ChestAdvisor.scan still consults UnitAffectingCombat")
check(ca:find("InCombatLockdown", 1, true) ~= nil,
  "ChestAdvisor.scan still consults InCombatLockdown")

print("ok")
