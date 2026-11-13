-- beast_skinnable_wording_spec.lua — t_f2571ca7, defect A.
--
-- The report, in game, on "Sap Beast" (an ooze, Stonetalon):
--
--     skinnable · skin windows recorded: 1
--     skinned
--     Large Slimy Bone x1
--     skinned: 2
--
-- An ooze is not skinnable. Data/SkinHints.lua asserted it anyway: when the
-- client gave no answer (UnitIsSkinnable is absent on this client, so `flag`
-- is always nil) and the creature had at least one recorded skin window, the
-- three-state block upgraded "a window happened" into the word "skinnable".
--
-- A window is evidence that a window happened, not that the creature can be
-- skinned — and on an ooze it is evidence the window was mis-attributed. The
-- client's three states must stay distinguishable and only the client's own
-- answer may supply the adjective:
--
--   flag == true   -> "skinnable"
--   flag == false  -> "not skinnable"
--   flag == nil    -> the windows only, with NO adjective
--
-- Sections 1 and 5 are RED on the tree this spec was written against: the
-- nil-answer row read "skinnable · skin windows recorded: 1". Sections 2-4
-- pin the two answered states and the three-state distinctness so a future
-- edit cannot buy section 1 by deleting the adjective everywhere.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- ── the client ──────────────────────────────────────────────────────────
local clock = 100
GetTime = function() return clock end
GetUnitName = function(u) if u == "player" then return "Mightie" end return nil end
GetRealmName = function() return "Forever" end
UnitIsSkinnable = nil -- this client has never answered (see SkinFlag)

-- The sub-toggle ON so the recorder persists into the character bucket the
-- beast panel reads (NodeTrail owns that key; this spec sets it directly).
NodeTrailDB = { skinning = { enabled = true } }

local pkg = {}
local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return false end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. path .. ": " .. tostring(e))
  return ok
end

loadFile("Modules/NodeTrail/Data/SkinHints.lua")
loadFile("Modules/Skinning/Record.lua")

local ns = type(pkg.NodeTrail) == "table" and pkg.NodeTrail or {}
local H = ns.SkinHints
local R = type(pkg.Skinning) == "table" and pkg.Skinning.Recorder or nil

check(type(H) == "table" and type(H.Rows) == "function",
  "0: Data/SkinHints.lua loaded (the beast panel's rows)")
check(type(R) == "table" and type(R.OnSkinLoot) == "function",
  "0: the skinning recorder is loaded (this spec drives the real one)")

-- ── fixture: one ooze corpse, one skin window filed to it ──────────────
-- Recorded through the recorder's own entry points, so the bucket below is
-- the shape the panel actually reads (no hand-written totals row).
local OOZE = 4023 -- an ooze entry id; the panel matches by id, never by name
do
  clock = 100
  R:OnKill({ guid = ("Creature-0-7072-1-48-%d-A1"):format(OOZE), t = clock,
    map = 1411, x = 0.5, y = 0.5 })
  clock = 101
  R:OnSkinLoot({
    guid = ("Creature-0-7072-1-48-%d-A1"):format(OOZE), t = clock,
    cast = true, spellID = 8613, castAt = clock,
    items = { { id = 4232, name = "Small Black Pelt", qty = 1 } },
  })
end

-- the left-hand column of the beast block, one row per line
local function lefts(cid)
  local out = {}
  for _, r in ipairs(H.Rows(cid, "Sap Beast") or {}) do
    if type(r.left) == "string" then out[#out + 1] = r.left end
  end
  return out
end

local function findRow(rows, want)
  for i = 1, #rows do
    if rows[i] == want then return i end
  end
  return nil
end

if type(H) == "table" and type(R) == "table" then
  -- ══════════════════════════════════════════════════════════════════
  -- 1. the client does not answer, the creature has one recorded
  --    window: the panel reports the window and asserts nothing.
  -- ══════════════════════════════════════════════════════════════════
  do
    UnitIsSkinnable = nil
    local rows = lefts(OOZE)
    local text = table.concat(rows, "\n")
    local saidSkinnable = false
    for _, r in ipairs(rows) do
      if r:lower():find("skinnable", 1, true) then saidSkinnable = true end
    end
    check(not saidSkinnable,
      "1: no client answer + one window must not print the word 'skinnable' (got:\n"
      .. text .. ")")
    check(findRow(rows, "skin windows recorded: 1") ~= nil,
      "1: the row still reports the one recorded window (got:\n" .. text .. ")")
    check(text:find("skinned: 2", 1, true) == nil,
      "1: the panel never claims more skins than were recorded (got:\n" .. text .. ")")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 2. the client says NO: "not skinnable", and no window chatter.
  -- ══════════════════════════════════════════════════════════════════
  do
    UnitIsSkinnable = function() return false end
    local rows = lefts(OOZE)
    local text = table.concat(rows, "\n")
    check(findRow(rows, "not skinnable") ~= nil,
      "2: a client 'no' still prints exactly 'not skinnable' (got:\n" .. text .. ")")
    check(findRow(rows, "skin windows recorded: 1") == nil,
      "2: a client 'no' does not stack the window row on top of it (got:\n" .. text .. ")")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 3. the client says YES: "skinnable" — and only that adjective.
  -- ══════════════════════════════════════════════════════════════════
  do
    UnitIsSkinnable = function() return true end
    local rows = lefts(OOZE)
    local text = table.concat(rows, "\n")
    check(findRow(rows, "skinnable") ~= nil,
      "3: a client 'yes' still prints exactly 'skinnable' (got:\n" .. text .. ")")
    check(findRow(rows, "skin windows recorded: 1") == nil,
      "3: a client 'yes' does not stack the window row on top of it (got:\n" .. text .. ")")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 4. the three states are still THREE distinguishable states.
  -- ══════════════════════════════════════════════════════════════════
  do
    local function firstRow()
      local rows = lefts(OOZE)
      for _, r in ipairs(rows) do
        if r:lower():find("skinnable", 1, true) or r:find("skin windows", 1, true) then
          return r
        end
      end
      return nil
    end
    UnitIsSkinnable = nil
    local unknown = firstRow()
    UnitIsSkinnable = function() return false end
    local no = firstRow()
    UnitIsSkinnable = function() return true end
    local yes = firstRow()
    check(unknown ~= nil and no ~= nil and yes ~= nil,
      "4: every client state renders a first row (nil/false/true = "
      .. tostring(unknown) .. " / " .. tostring(no) .. " / " .. tostring(yes) .. ")")
    check(unknown ~= no and no ~= yes and unknown ~= yes,
      "4: the three states render three different rows (got:\n  [nil] "
      .. tostring(unknown) .. "\n  [false] " .. tostring(no) .. "\n  [true] " .. tostring(yes) .. ")")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 5. no answer and NO window: nothing is claimed at all. The word
  --    "skinnable" must not appear for a creature we know nothing about.
  -- ══════════════════════════════════════════════════════════════════
  do
    UnitIsSkinnable = nil
    local UNSEEN = 4024
    local rows = lefts(UNSEEN)
    local text = table.concat(rows, "\n")
    for _, r in ipairs(rows) do
      check(not r:lower():find("skinnable", 1, true),
        "5: an unheard-of creature is never called skinnable (got:\n" .. text .. ")")
    end
  end
end

if failed > 0 then
  io.stderr:write(failed .. " failed\n")
  os.exit(1)
end
print("ok")
