-- touchstone_version_label_spec.lua — card t_c02c1643.
--
-- WHY THIS FILE EXISTS AT ALL. Card t_8526712d went looking for the doubled "v"
-- in these three surfaces, because the PATTERN `"v" .. x` appears at each of
-- them. Measured, they are innocent: the value they concatenate is `SF.VERSION`,
-- Touchstone's OWN module version — a literal `"0.8.3"` in Constants.lua that
-- carries no v — so prefixing one is correct and they have always read
-- `v0.8.3`. The doubled v was the pack's, in its Options footer, coming from a
-- different value: the TOC's Version line, which the packager substitutes from
-- the git tag, v included.
--
-- This file keeps those three surfaces honest against the mistake that was made
-- about them: it MEASURES the value (SF.VERSION) rather than reading the pattern,
-- and then reads each rendered string off the real drawn surface — a Touchstone
-- window built in STANDALONE mode (no host, so the title bar the host removes is
-- actually built), and the Options tab the window renders:
--
--   1. the window subtitle      `Classic-era item advisor  ·  v0.8.3`
--   2. the Settings About line  `Touchstone v0.8.3  ·  Classic Era item advisor`
--   3. the diagnostics header   `Touchstone diagnostics v0.8.3`
--
-- Each reads exactly ONE v, and none may contain `vv` or `v@`.
--
-- TEETH (and the lesson): if SF.VERSION ever DID carry a leading v — the shape
-- t_8526712d assumed — these three expressions would double it. The detector is
-- run on that hypothetical string and must name it, and the shipped literal is
-- asserted to be v-free, so the file states which fact it stands on.
--
-- Run from the repo root:  lua5.1 tests/touchstone_version_label_spec.lua

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

local pkg = { PackVersion = function() return "0.3.12-beta" end }
_G.MightiePack = pkg

-- The client's global aliases, which the module uses (UI.lua calls tinsert).
tinsert = table.insert
tremove = table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
MightiePackDB = { modules = {} }
StatForgeDB = { ui = { scale = 1 }, firstUse = false }

local TOUCH = root .. "/MightiePack/Modules/Touchstone/"
local function loadFile(name)
  local chunk, err = loadfile(TOUCH .. name)
  check(chunk ~= nil, "loadfile " .. name .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. name .. ": " .. tostring(e))
end

-- The pack's own TOC order for everything this spec touches. No host is
-- installed and SetHostedChrome is never called, so the window is the standalone
-- one: the title bar (which carries the subtitle) is built.
for _, name in ipairs({
  "Bootstrap.lua", "Constants.lua", "Weights.lua", "UI.lua", "OptionsTab.lua",
  "Diagnostics.lua",
  "ChestAdvisor/Marks.lua", "ChestAdvisor/Verdict.lua", "ChestAdvisor/StatOrders.lua",
  "ChestAdvisor/Arbitration.lua", "ChestAdvisor/ChestAdvisor.lua",
}) do
  loadFile(name)
end

local SF = _G.StatForge
check(type(SF) == "table", "the module loads")
if type(SF) ~= "table" then os.exit(1) end

-- ── The value, measured ────────────────────────────────────────────────────
-- The whole point of the card the mistake belongs to: these surfaces prefix a v
-- onto a string that has none. If that fact stops being true, this spec says so
-- instead of silently rendering `vv0.8.3`.
check(type(SF.VERSION) == "string" and SF.VERSION ~= "",
  "SF.VERSION is a non-empty string, got " .. tostring(SF.VERSION))
check(SF.VERSION:match("^%d") ~= nil,
  "SF.VERSION carries no leading v of its own (it is a module version, not a tag) — got \"" ..
  tostring(SF.VERSION) .. "\"")
local ONEV = "v" .. tostring(SF.VERSION)

-- A doubled prefix and an unsubstituted token are the two ways a version surface
-- renders machinery instead of a version.
local function doubleV(text)
  if type(text) ~= "string" then return false end
  return text:find("vv", 1, true) ~= nil or text:find("v@", 1, true) ~= nil
end

local function stripEscapes(text)
  text = tostring(text or "")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return text
end

-- ── The surfaces, as drawn ─────────────────────────────────────────────────
check(type(SF.ShowMain) == "function", "SF.ShowMain exists")
local okShow, showErr = pcall(SF.ShowMain, "options")
check(okShow, "SF.ShowMain(\"options\"): " .. tostring(showErr))

local chrome = type(SF.Chrome) == "function" and SF.Chrome() or nil
check(type(chrome) == "table" and type(chrome.subtitle) == "table",
  "the standalone window built its title bar, so it has a subtitle")
local subtitle = type(chrome) == "table" and type(chrome.subtitle) == "table"
  and chrome.subtitle:GetText() or nil
print("subtitle = " .. tostring(subtitle))

local function walk(frame, out, seen)
  out, seen = out or {}, seen or {}
  if type(frame) ~= "table" or seen[frame] then return out end
  seen[frame] = true
  if type(frame.GetText) == "function" then
    local ok, t = pcall(frame.GetText, frame)
    if ok and type(t) == "string" and t ~= "" then out[#out + 1] = stripEscapes(t) end
  end
  local ok, kids = pcall(frame.GetChildren, frame)
  if ok and type(kids) == "table" then
    for _, child in ipairs(kids) do walk(child, out, seen) end
  end
  return out
end

-- The About block, off the drawn label in the window's content frame.
local content = type(SF.ContentFrame) == "function" and SF.ContentFrame() or nil
local aboutBlock = nil
for _, t in ipairs(walk(content, {})) do
  if t:find("Touchstone v", 1, true) and t:find("About", 1, true) then aboutBlock = t end
end
check(aboutBlock ~= nil, "the Options tab draws its About block")
local aboutLine = type(aboutBlock) == "string" and aboutBlock:match("Touchstone v[^\n]*") or nil
print("about    = " .. tostring(aboutLine))

-- The diagnostics header. The module is loaded, so the report is real.
local diagLine = nil
if type(SF.BuildDiagnosticsReportLines) == "function" then
  local ok, lines = pcall(SF.BuildDiagnosticsReportLines)
  if ok and type(lines) == "table" then diagLine = lines[1] end
end
print("diag     = " .. tostring(diagLine))

-- ── The assertions ─────────────────────────────────────────────────────────
local function checkSurface(name, text, expect)
  check(type(text) == "string", name .. ": renders a string")
  if type(text) ~= "string" then return end
  check(text == expect, name .. ": reads \"" .. expect .. "\", got \"" .. text .. "\"")
  check(not doubleV(text), name .. ": never contains vv or v@ — got \"" .. text .. "\"")
end

checkSurface("the window subtitle", subtitle, "Classic-era item advisor  ·  " .. ONEV)
checkSurface("the About line", aboutLine, "Touchstone " .. ONEV .. "  ·  Classic Era item advisor")
checkSurface("the diagnostics header", diagLine,
  "Touchstone diagnostics " .. ONEV)

-- ── TEETH ──────────────────────────────────────────────────────────────────
-- The shape t_8526712d assumed SF.VERSION had: a tag's leading v. Every one of
-- these three expressions would then read a doubled v.
local wrongValue = "v" .. tostring(SF.VERSION)
check(doubleV("Classic-era item advisor  ·  v" .. wrongValue),
  "TEETH: the detector names the subtitle built from a v-carrying value")
check(doubleV("Touchstone v" .. wrongValue .. "  ·  Classic Era item advisor"),
  "TEETH: the detector names the About line built from a v-carrying value")
check(doubleV("Touchstone diagnostics v" .. wrongValue),
  "TEETH: the detector names the diagnostics header built from a v-carrying value")
check(not doubleV(ONEV), "TEETH: the detector is silent on the surface as shipped")

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("touchstone_version_label_spec: ok")
