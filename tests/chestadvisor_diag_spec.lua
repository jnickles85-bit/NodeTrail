-- The /up diag row must carry the weighted total, the profile and the tiebreak
-- that decided it (audit follow-up on the w2 scope bug).
--
-- What went wrong, so this spec cannot be "fixed" by deleting it. Two edits in
-- tools/sync_touchstone.py act on the same function of the vendored ChestAdvisor:
-- one rewrote a branch to `local v2, r2, w2 = Verdict.evaluate(...)`, a later one
-- injects `weighted = w2 and w2.total`, `profile = w2 and w2.profile` and
-- `tiebreak = w2 and w2.tiebreak` into the persisted diag row. The row sits outside
-- that branch, so the three reads were undefined globals: every diag row recorded
-- nil, and luacheck flagged six reads. The fold now hoists the declaration.
--
-- Two halves, because the scan itself needs a live client:
--   1. the comparator really returns those three values (driven here), and
--   2. the vendored scan really copies them onto the row, with the declaration in
--      a scope the row can see — checked on the generated source, which is what the
--      next sync would regress.
--
-- Run from the repo root:  lua5.1 tests/chestadvisor_diag_spec.lua

local here = (arg and arg[0] or "tests/chestadvisor_diag_spec.lua"):match("^(.*)[/\\][^/\\]*$") or "."
local root = here:gsub("[/\\]tests$", "")
if root == "tests" then root = "." end
local TOUCH = root .. "/MightiePack/Modules/Touchstone/"

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

local verdictSrc = readFile(TOUCH .. "ChestAdvisor/Verdict.lua")
check(verdictSrc ~= nil, "the vendored Verdict.lua is present")
if not verdictSrc then os.exit(1) end

-- ---- 1. The comparator hands back what the row records ----------------------
local V = assert(loadfile(TOUCH .. "ChestAdvisor/Verdict.lua"))()
local RET_SPEC = {
  class = "PALADIN", role = "melee", clientRole = "DAMAGER",
  order = V.classRoleOrder("PALADIN", "melee"), level = 70,
}

local function judge(cand, worn)
  return V.evaluate({ canUse = true, line = cand }, { line = worn }, RET_SPEC, nil)
end

-- 1a. The live cloak pair: a weighted downgrade, with the number and the profile.
local WORN = { "Lambent Scale Cloak", "Back", "19 Armor", "+4 Strength", "+2 Spirit" }
local CAND = { "Barkeeper's Cloak", "Back", "16 Armor", "+3 Stamina" }
local v, _, w = judge(CAND, WORN)
check(v == "NOT_UPGRADE", "the cloak pair is a downgrade, got " .. tostring(v))
check(type(w) == "table", "the comparator returns the weighted record, got " .. type(w))
if type(w) == "table" then
  check(type(w.total) == "number", "the weighted record carries .total")
  check(w.profile == "Retribution",
    "the weighted record names the profile, got " .. tostring(w.profile))
end

-- 1b. A tiebreak row: equal damage, more armour and stamina. That is the shape
-- where .tiebreak has to be a string, because the row stores it verbatim.
local TB_WORN = { "Feral Shoes of Strength", "Feet", "51 Armor", "+4 Strength" }
local TB_CAND = { "Safety Boots", "Feet", "115 Armor", "+4 Strength", "+2 Stamina" }
local vb, _, wb = judge(TB_CAND, TB_WORN)
check(vb == "UPGRADE", "the boots are a tiebreaker upgrade, got " .. tostring(vb))
check(type(wb) == "table" and type(wb.tiebreak) == "string",
  "a tiebreak row carries .tiebreak as a string, got " .. type(wb and wb.tiebreak))

-- ---- 2. The generated scan copies them, from a scope it can see -------------
local advisor = readFile(TOUCH .. "ChestAdvisor/ChestAdvisor.lua")
check(advisor ~= nil, "the vendored ChestAdvisor.lua is present")
if advisor then
  for _, field in ipairs({
    "weighted = w2 and w2.total or nil",
    "profile = w2 and w2.profile or nil",
    "tiebreak = w2 and w2.tiebreak or nil",
  }) do
    check(advisor:find(field, 1, true) ~= nil,
      "the diag row records `" .. field .. "`")
  end

  -- The regression: the declaration must not live inside the branch that assigns
  -- it, or the three reads above go back to being undefined globals.
  check(advisor:find("local v2, r2, w2 = Verdict.evaluate", 1, true) == nil,
    "w2 is not declared inside the else branch that assigns it")

  local declared = advisor:find("\t\t\t\t\tlocal w2\n", 1, true)
  check(declared ~= nil, "the scan declares w2 in the candidate-walk scope")
  local firstRead = advisor:find("weighted = w2 and w2.total", 1, true)
  check(declared ~= nil and firstRead ~= nil and declared < firstRead,
    "the declaration comes before the diag row that reads it")
end

if failed > 0 then
  os.exit(1)
else
  print("chestadvisor_diag_spec: ok")
end
