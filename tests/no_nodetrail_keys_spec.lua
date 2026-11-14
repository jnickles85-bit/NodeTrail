-- no_nodetrail_keys_spec.lua — the pack's side of the migration window
-- (card t_75309c97).
--
-- NodeTrail is its own addon again, and the history it needs belongs to
-- `NodeTrailDB` — one global, stored by the game in one file per declaring
-- addon. The pack keeps DECLARING that global, because that declaration is what
-- makes the game load an existing history for the NodeTrail addon to adopt on
-- the first login with both installed.
--
-- What must be true, and why each is a fact rather than a restatement:
--
--   1. The declaration is still in the TOC, exactly once, unchanged.
--   2. No shipping file READS OR WRITES a key of the store. The declaration is
--      the whole of the pack's involvement: the moment a line of code touches
--      the table, the pack becomes a second owner and the two can disagree.
--   3. None of NodeTrail's files ship here any more, so nothing of the pack can
--      record into that store either.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local function readAll(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

-- ── 1. the declaration ───────────────────────────────────────────────────
local toc = readAll(root .. "/MightiePack/MightiePack.toc")
check(toc ~= nil, "the TOC is readable")
local decl = (toc or ""):match("## SavedVariables: ([^\r\n]+)")
check(decl ~= nil, "the TOC declares SavedVariables")
local seen = 0
for _ in (decl or ""):gmatch("NodeTrailDB") do seen = seen + 1 end
check(seen == 1, "NodeTrailDB is declared exactly once (found " .. seen .. ")")
check((decl or ""):find("MightiePackDB", 1, true) ~= nil, "MightiePackDB is still declared")
check((decl or ""):find("StatForgeDB", 1, true) ~= nil, "StatForgeDB is still declared")

-- ── 2. no shipping file touches the store ────────────────────────────────
-- The shipping files are the ones the TOC lists, so a file that is not loaded
-- cannot be blamed for a write either.
local files = {}
for line in (toc or ""):gmatch("[^\r\n]+") do
  local t = line:gsub("^%s+", ""):gsub("%s+$", "")
  if t:match("%.lua$") then files[#files + 1] = t end
end
check(#files > 10, "the TOC lists the shipping files (" .. #files .. ")")

local offenders = {}
for _, rel in ipairs(files) do
  local text = readAll(root .. "/MightiePack/" .. rel) or ""
  local lineNo = 0
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lineNo = lineNo + 1
    -- A comment that names the variable is documentation, not a read or a write.
    local code = line:gsub("^%s*%-%-.*$", "")
    if code:find("NodeTrailDB", 1, true) then
      offenders[#offenders + 1] = rel .. ":" .. lineNo .. ": " .. code:gsub("^%s+", "")
    end
  end
end
check(#offenders == 0, "no shipping file reads or writes NodeTrailDB (found: "
  .. table.concat(offenders, " | ") .. ")")

-- ── 3. none of NodeTrail's files ship here ───────────────────────────────
for _, rel in ipairs(files) do
  check(rel:sub(1, #"Modules/NodeTrail/") ~= "Modules/NodeTrail/",
    "the TOC ships no Modules/NodeTrail file (" .. rel .. ")")
  check(rel:sub(1, #"Modules/Skinning/") ~= "Modules/Skinning/",
    "the TOC ships no Modules/Skinning file (" .. rel .. ")")
  check(rel ~= "Window/Herbs.lua" and rel ~= "Window/Skinning.lua",
    "the TOC ships no Herbs/Skinning tab body (" .. rel .. ")")
end

-- The two declarations that are NOT about our store must still be there: the
-- pack's own settings and the vendored module's data.
check(decl and decl:find("MightiePackDB", 1, true) ~= nil, "the pack's own store is declared")

if failed == 0 then
  print("no_nodetrail_keys_spec: ok (" .. #files .. " shipping files, NodeTrailDB declared once)")
else
  os.exit(1)
end
