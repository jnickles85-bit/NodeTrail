-- slash_retirement_spec.lua — card t_2d2c37b0 (the reshape).
--
-- The card's third done-when: *every removed slash alias is retired explicitly
-- and listed; every surviving alias resolves to a live tab.*
--
-- Both halves are checked here, and both are needed:
--
--   A. THE INVENTORY. Every `SLASH_*` assignment in the pack is collected from
--      the source and compared against the pack's own published table
--      (pkg.SlashAliases). A new alias that nobody listed fails; an alias that
--      is listed but no longer registered fails. /nt and /nodetrail must not
--      appear at all — they belong to the NodeTrail addon now.
--
--   B. THE RESOLUTION. Each registered handler is DRIVEN and the window must
--      land on the tab the inventory names. A retired subcommand (/mp skindiag
--      — it answered for the Skinning tab) must answer with a sentence saying
--      where the diagnostics went, and must not open a tab that no longer
--      exists.
--
-- Not a screenshot: harness/source evidence.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

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

-- The TOC is the list of files the client loads; it is also the list this spec
-- scans, so a file that is not shipped cannot hide an alias from the inventory.
local tocText = readFile(root .. "/MightiePack/MightiePack.toc") or ""
local shipped = {}
for line in tocText:gmatch("[^\r\n]+") do
  local t = line:gsub("^%s+", ""):gsub("%s+$", "")
  if t ~= "" and not t:match("^##") then shipped[#shipped + 1] = t end
end
check(#shipped > 0, "the TOC lists the pack's files")

-- ── A. THE INVENTORY ──────────────────────────────────────────────────────
local found = {}     -- alias -> file
for _, rel in ipairs(shipped) do
  local text = readFile(root .. "/MightiePack/" .. rel) or ""
  for alias in text:gmatch("SLASH_%u[%w_]-%s*=%s*\"([^\"]+)\"") do
    found[alias:lower()] = rel
  end
end

local function sortedKeys(tbl)
  local out = {}
  for k in pairs(tbl) do out[#out + 1] = k end
  table.sort(out)
  return out
end

local actual = table.concat(sortedKeys(found), " ")
local expected = "/chestadvice /mightiepack /mp /mpack /sf /statforge /touchstone /ts /up /upgrade"
check(actual == expected,
  "the pack registers exactly the shipped alias set\n    expected: " .. expected
    .. "\n    actual:   " .. actual)

-- The retirements, at the source level: the pack must not register them.
for _, dead in ipairs({ "/nt", "/nodetrail" }) do
  check(found[dead] == nil,
    "the pack does not register " .. dead .. " any more (it belongs to the NodeTrail addon, "
      .. "found in " .. tostring(found[dead]) .. ")")
end

-- ── B. THE RESOLUTION ─────────────────────────────────────────────────────
local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })
tinsert, tremove, tsort = table.insert, table.remove, table.sort
format = string.format
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

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
-- NodeTrail is NOT installed in this scenario: the retired commands must still
-- answer sensibly rather than assuming it is there.
IsAddOnLoaded = function() return false end
C_AddOns = nil

for _, rel in ipairs(shipped) do loadFile(rel) end
check(pcall(pkg.EnableModules), "the enabled modules start")

local W = pkg.Window
check(type(W) == "table", "the window exists")

-- The published inventory: every live alias, the tab it opens, and no overlap
-- with the retired list.
check(type(pkg.SlashAliases) == "table", "the pack publishes pkg.SlashAliases")
local listed = {}
for _, group in ipairs(pkg.SlashAliases or {}) do
  check(type(group.tab) == "string" and W.TAB_LABELS[group.tab] ~= nil,
    "alias group '" .. tostring(group.tab) .. "' names a tab that exists")
  for _, alias in ipairs(group.aliases or {}) do
    listed[alias] = group.tab
  end
end
local listedKeys = table.concat(sortedKeys(listed), " ")
check(listedKeys == expected,
  "pkg.SlashAliases lists exactly the registered aliases\n    expected: " .. expected
  .. "\n    actual:   " .. listedKeys)

check(type(pkg.RetiredSlashAliases) == "table", "the pack publishes pkg.RetiredSlashAliases")
local retired = {}
for _, entry in ipairs(pkg.RetiredSlashAliases or {}) do
  retired[entry.alias] = entry.reason
  check(type(entry.reason) == "string" and entry.reason ~= "",
    "retired alias " .. tostring(entry.alias) .. " states why it was retired")
end
for _, must in ipairs({ "/nt", "/nodetrail", "/mp skindiag" }) do
  check(retired[must] ~= nil, "the retired list names " .. must)
end

-- Drive every alias handler the pack registers, and require the window to land
-- on the tab the inventory names. Registered handler -> alias family:
local families = {
  { handlers = { "MIGHTIEPACK" }, tab = "settings",
    aliases = { "/mightiepack", "/mpack", "/mp" } },
  { handlers = { "CHESTADVISOR" }, tab = "touchstone",
    aliases = { "/up", "/upgrade", "/chestadvice", "/ts" } },
  { handlers = { "TOUCHSTONE" }, tab = "touchstone",
    aliases = { "/touchstone", "/sf", "/statforge" } },
}
local driven = 0
for _, family in ipairs(families) do
  for _, handlerName in ipairs(family.handlers) do
    local handler = SlashCmdList and SlashCmdList[handlerName]
    check(type(handler) == "function",
      "SlashCmdList." .. handlerName .. " is registered (the alias family is live)")
    if type(handler) == "function" then
      -- Start CLOSED and on the other tab, so a handler that does nothing (or
      -- toggles the wrong way) cannot pass by leaving the window where it was.
      W.Open(family.tab == "settings" and "touchstone" or "settings")
      W.Close()
      check(not W.IsShown(), "precondition: the window is closed before driving " .. handlerName)
      C.ClearChat()
      local ok, err = pcall(handler, "")
      driven = driven + 1
      check(ok, "driving " .. handlerName .. " does not raise: " .. tostring(err))
      check(W.IsShown(), handlerName .. " opens the window")
      check(W.Current() == family.tab,
        handlerName .. " reaches the " .. family.tab .. " tab (got "
          .. tostring(W.Current()) .. ")")
      for _, alias in ipairs(family.aliases) do
        check(listed[alias] == family.tab,
          alias .. " is listed as opening " .. family.tab)
      end
    end
  end
end
check(driven == 3, "all three alias families were driven (got " .. driven .. ")")

-- ── The retired subcommand answers with a sentence, not usage text ────────
W.Open("settings")
C.ClearChat()
local mp = SlashCmdList.MIGHTIEPACK
check(type(mp) == "function", "the pack's own handler is registered")
if type(mp) == "function" then
  local ok, err = pcall(mp, "skindiag")
  check(ok, "/mp skindiag does not raise: " .. tostring(err))
  check(C.ChatHas("moved out of the pack with NodeTrail"),
    "/mp skindiag says where the diagnostics went (chat: "
      .. table.concat(C.chat, " | ") .. ")")
  check(C.ChatHas("NodeTrail"),
    "/mp skindiag names the addon that has them now")
  check(W.Current() == "settings",
    "/mp skindiag opens no tab and leaves the window where it was (got "
      .. tostring(W.Current()) .. ")")
  check(not C.ChatHas("/mpack [options|status]"),
    "a retired subcommand does not fall through to the generic usage text")
end

-- An unknown subcommand still gets the usage text: the new branch must not
-- swallow everything that is not a known command.
C.ClearChat()
if type(mp) == "function" then
  pcall(mp, "nonsense")
  check(C.ChatHas("/mpack [options|status]"),
    "an unknown subcommand still prints the usage line (chat: "
      .. table.concat(C.chat, " | ") .. ")")
end

-- /nt is not the pack's: nothing in the pack may answer for it.
check((SlashCmdList and SlashCmdList.NODETRAIL) == nil,
  "the pack does not register a /nt handler")
local ntRegistered = false
for key in pairs(SlashCmdList or {}) do
  if key == "NODETRAIL" then ntRegistered = true end
end
check(not ntRegistered, "no NodeTrail handler hides under another key either")

if failed == 0 then
  print("slash_retirement_spec: ok")
else
  print(("slash_retirement_spec: %d failure(s)"):format(failed))
  os.exit(1)
end
