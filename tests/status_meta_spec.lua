-- status_meta_spec.lua — t_5507a0ba
--
-- /mpack status must read the TOC metadata on the Forever 16001 client,
-- where the legacy global GetAddOnMetadata does not exist and the modern
-- surface is C_AddOns.GetAddOnMetadata. Live output before this fix:
--
--   MightiePack: version unknown
--   MightiePack: interface unknown, build unknown, client unknown, locale enUS, GatherMate2: unknown
--
-- The spec drives the REAL status branch of the real Core.lua in three
-- client shapes the card names — only C_AddOns, only the global, neither —
-- plus the precedence and degradation details of the chain. Nothing here
-- re-implements the status builder: every assertion reads the chat lines
-- SlashCmdList.MIGHTIEPACK("status") actually printed.
--
-- The provider is resolved at CALL time (never cached), so cases (d)–(g)
-- swap the globals between runs on the same loaded package — that is also
-- what the client does (C_AddOns arrives with a later API generation).
--
-- RED on fc8e5d6: the status branch called only the global, so case (a) —
-- the real client shape — printed "version unknown / interface unknown"
-- and the first two checks fail there.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- ── chat capture ────────────────────────────────────────────────────
local chat = {}
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end,
}
local function clearChat()
  for i = #chat, 1, -1 do chat[i] = nil end
end
local function chatText()
  return table.concat(chat, "\n")
end

-- ── frame harness (Core.lua registers an ADDON_LOADED frame) ────────
CreateFrame = function()
  local f = { scripts = {}, events = {} }
  f.RegisterEvent = function(self, e) self.events[e] = true end
  f.UnregisterEvent = function(self, e) self.events[e] = nil end
  f.SetScript = function(self, n, fn) self.scripts[n] = fn end
  return f
end
SlashCmdList = {}
StaticPopupDialogs = {}
MightiePackDB = nil
NodeTrailDB = nil

-- ── load the real umbrella Core.lua (no module files needed) ────────
local pkg = {}
local loaded = {}
for _, name in ipairs({ "Core.lua", "Modules.lua" }) do
  local chunk = assert(loadfile(root .. "/MightiePack/" .. name))
  local ok, err = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. name .. ": " .. tostring(err))
  loaded[name] = ok
end
check(loaded["Core.lua"], "Core.lua loaded")
check(type(SlashCmdList.MIGHTIEPACK) == "function",
  "the real /mpack dispatcher is registered")

local function runStatus()
  clearChat()
  local ok, err = pcall(SlashCmdList.MIGHTIEPACK, "status")
  return chatText(), ok, err
end

local function lineStarting(text, prefix)
  for _, l in ipairs(chat) do
    -- the chat lines carry the |cff33ff99MightiePack|r: prefix
    if l:find(prefix, 1, true) then return l end
  end
  return nil
end

-- ════════════════════════════════════════════════════════════════════
-- (a) The Forever client shape: C_AddOns.GetAddOnMetadata only.
--     The client has no global GetAddOnMetadata, no GetBuildInfo and no
--     IsAddOnLoaded (its live output said "build unknown, client unknown,
--     GatherMate2: unknown"), but GetLocale works. Only the TOC metadata
--     is in scope for this card — the other fields stay exactly as they
--     were, and are asserted here so a change to them shows up.
-- ════════════════════════════════════════════════════════════════════
C_AddOns = {
  GetAddOnMetadata = function(name, field)
    if name ~= "MightiePack" then return nil end
    if field == "Version" then return "0.3.0" end
    if field == "Interface" then return "16001" end
    return nil
  end,
}
GetAddOnMetadata = nil
GetBuildInfo = nil
IsAddOnLoaded = nil
GetLocale = function() return "enUS" end

local st, ok = runStatus()
check(ok, "(a) status does not error on the C_AddOns-only client: " .. tostring(st))
check(st:find("version 0.3.0", 1, true) ~= nil,
  "(a) C_AddOns-only: real Version from the TOC (got: " .. st:gsub("\n", " | ") .. ")")
check(st:find("interface 16001", 1, true) ~= nil,
  "(a) C_AddOns-only: real Interface from the TOC")
check(st:find("build unknown", 1, true) ~= nil,
  "(a) C_AddOns-only: build stays unknown (GetBuildInfo absent — untouched by this card)")
check(st:find("client unknown", 1, true) ~= nil,
  "(a) C_AddOns-only: client version stays unknown")
check(st:find("locale enUS", 1, true) ~= nil,
  "(a) C_AddOns-only: locale still reads (GetLocale present)")
check(st:find("GatherMate2: unknown", 1, true) ~= nil,
  "(a) C_AddOns-only: GatherMate2 stays unknown (IsAddOnLoaded absent)")
check(st:find("version unknown", 1, true) == nil,
  "(a) C_AddOns-only: no 'version unknown' line")

-- ════════════════════════════════════════════════════════════════════
-- (b) The legacy shape: only the global GetAddOnMetadata (pre-C_AddOns).
-- ════════════════════════════════════════════════════════════════════
C_AddOns = nil
GetAddOnMetadata = function(name, field)
  if name ~= "MightiePack" then return nil end
  if field == "Version" then return "0.3.0" end
  if field == "Interface" then return "16001" end
  return nil
end
GetBuildInfo = function() return "16", "0", "0", "16001" end
IsAddOnLoaded = function(n) return n == "GatherMate2" end

st, ok = runStatus()
check(ok, "(b) status does not error on the global-only client")
check(st:find("version 0.3.0", 1, true) ~= nil,
  "(b) global-only: real Version from the TOC (got: " .. st:gsub("\n", " | ") .. ")")
check(st:find("interface 16001", 1, true) ~= nil,
  "(b) global-only: real Interface from the TOC")
check(st:find("build 16001", 1, true) ~= nil, "(b) global-only: build from GetBuildInfo")
check(st:find("client 16.0.0.16001", 1, true) ~= nil, "(b) global-only: full client version")
check(st:find("GatherMate2: loaded", 1, true) ~= nil, "(b) global-only: GatherMate2 loaded")

-- ════════════════════════════════════════════════════════════════════
-- (c) Neither provider: "unknown", and no error anywhere.
-- ════════════════════════════════════════════════════════════════════
C_AddOns = nil
GetAddOnMetadata = nil
GetBuildInfo = nil
GetLocale = nil
IsAddOnLoaded = nil

st, ok = runStatus()
check(ok, "(c) neither provider: status does not error")
check(st:find("version unknown", 1, true) ~= nil, "(c) neither provider: version unknown")
check(st:find("interface unknown", 1, true) ~= nil, "(c) neither provider: interface unknown")
check(st:find("build unknown", 1, true) ~= nil, "(c) neither provider: build unknown")
check(st:find("locale unknown", 1, true) ~= nil, "(c) neither provider: locale unknown")
check(st:find("GatherMate2: unknown", 1, true) ~= nil, "(c) neither provider: GatherMate2 unknown")
check(type(pkg.GetAddOnMeta) == "function"
  and pkg.GetAddOnMeta("MightiePack", "Version") == nil,
  "(c) pkg.GetAddOnMeta returns nil when no provider exists")

-- ════════════════════════════════════════════════════════════════════
-- (d) Both providers present and disagreeing: C_AddOns wins.
-- ════════════════════════════════════════════════════════════════════
C_AddOns = {
  GetAddOnMetadata = function(_, field)
    if field == "Version" then return "1.2.3-modern" end
    if field == "Interface" then return "17000" end
    return nil
  end,
}
GetAddOnMetadata = function(_, field)
  if field == "Version" then return "9.9.9-legacy" end
  if field == "Interface" then return "10000" end
  return nil
end
st, ok = runStatus()
check(ok, "(d) both providers: no error")
check(st:find("version 1.2.3-modern", 1, true) ~= nil,
  "(d) C_AddOns is preferred over the global (got: " .. st:gsub("\n", " | ") .. ")")
check(st:find("interface 17000", 1, true) ~= nil, "(d) C_AddOns Interface wins")
check(st:find("legacy", 1, true) == nil, "(d) the legacy value is not used")

-- ════════════════════════════════════════════════════════════════════
-- (e) C_AddOns present but returns nil / empty: fall through to the
--     global. This is the "partial C_AddOns" shape — a client that has
--     the table but not the field.
-- ════════════════════════════════════════════════════════════════════
C_AddOns = { GetAddOnMetadata = function() return nil end }
st, ok = runStatus()
check(ok, "(e) C_AddOns returning nil: no error")
check(st:find("version 9.9.9-legacy", 1, true) ~= nil,
  "(e) nil from C_AddOns falls back to the global (got: " .. st:gsub("\n", " | ") .. ")")

C_AddOns = { GetAddOnMetadata = function() return "" end }
st, ok = runStatus()
check(ok, "(e) C_AddOns returning an empty string: no error")
check(st:find("version 9.9.9-legacy", 1, true) ~= nil,
  "(e) an empty string is not metadata; it falls back to the global")

-- ════════════════════════════════════════════════════════════════════
-- (f) C_AddOns raising: pcall'd, falls through, never errors.
-- ════════════════════════════════════════════════════════════════════
C_AddOns = {
  GetAddOnMetadata = function() error("C_AddOns exploded") end,
}
st, ok = runStatus()
check(ok, "(f) C_AddOns raising does not error through the status branch")
check(st:find("C_AddOns exploded", 1, true) == nil,
  "(f) the raised message is not printed as metadata")
check(st:find("version 9.9.9-legacy", 1, true) ~= nil,
  "(f) after a raise the global provider still answers")
check(type(pkg.GetAddOnMeta) == "function"
  and pkg.GetAddOnMeta("MightiePack", "Version") == "9.9.9-legacy",
  "(f) direct helper call: falls through after a raise")

-- ════════════════════════════════════════════════════════════════════
-- (g) A non-string return is not metadata (the guard the card keeps).
-- ════════════════════════════════════════════════════════════════════
C_AddOns = nil
GetAddOnMetadata = function(_, field)
  if field == "Version" then return 16001 end -- a number, not a string
  return nil
end
st, ok = runStatus()
check(ok, "(g) non-string metadata does not error")
check(st:find("version unknown", 1, true) ~= nil,
  "(g) a non-string Version degrades to unknown (got: " .. st:gsub("\n", " | ") .. ")")

-- ════════════════════════════════════════════════════════════════════
-- (h) The provider is resolved per call, never cached at load: restore
--     the real client shape and the very same package answers again.
-- ════════════════════════════════════════════════════════════════════
GetAddOnMetadata = nil
C_AddOns = {
  GetAddOnMetadata = function(_, field)
    if field == "Version" then return "0.3.0" end
    if field == "Interface" then return "16001" end
    return nil
  end,
}
st, ok = runStatus()
check(ok, "(h) back to the C_AddOns-only shape: no error")
check(st:find("version 0.3.0", 1, true) ~= nil,
  "(h) the same loaded package reads C_AddOns again (no cached provider)")

-- pkg.PackVersion tracks the TOC at call time (no stale "0.3.0" constant).
check(type(pkg.PackVersion) == "function", "pkg.PackVersion exists")
check(pkg.PackVersion() == "0.3.0", "PackVersion follows the current C_AddOns stub")
check(pkg.version == nil, "the hardcoded pkg.version assignment is gone")
local savedC = C_AddOns
C_AddOns = nil
GetAddOnMetadata = nil
check(pkg.PackVersion() == nil, "PackVersion is nil-safe when no provider exists")
C_AddOns = savedC

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("status_meta_spec: ok")
