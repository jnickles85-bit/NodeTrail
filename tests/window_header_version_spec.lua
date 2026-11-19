-- window_header_version_spec.lua — card t_b1d7cd6a.
--
-- The owner's first retest of v0.3.12-beta read `vv0.3.12-beta` in the window's
-- header. Not stale data and not a new defect: the TOC's `## Version:` line is
-- substituted from the git TAG by the packager, so it arrives as
-- `v0.3.12-beta` — leading v included — and Window.lua's title band built the
-- label as `"v" .. ver`, adding a second one. Every tagged build has carried it
-- since 0.3.10; nobody had read that corner of the header until now.
--
-- What this file pins, for the SHAPE of the string rather than for one release:
-- the header renders the TOC's version as it arrives, with exactly one leading
-- v. Each case is driven through the real header path — the whole TOC loaded in
-- its own order into a fresh package, the real Window.lua title band, and the
-- pack's own pkg.PackVersion -> pkg.GetAddOnMeta -> C_AddOns/legacy chain:
--
--   1. `v0.3.12-beta`   (a tagged release: what the client actually ships)
--      -> `v0.3.12-beta`, not `vv0.3.12-beta`. This is the owner's screen.
--   2. `0.3.12-beta`    (a TOC whose Version line has no v)
--      -> `v0.3.12-beta`: the label still carries one, so the shape of the TOC
--      cannot decide what the header reads.
--   3. `@project-version@` through the MODERN provider — the packager's
--      unsubstituted token, which pkg.GetAddOnMeta answers as "dev"
--      -> `dev`. The pre-fix code read `vdev`.
--   4. `@project-version@` through the LEGACY provider, which returns the raw
--      token -> `dev`. The pre-fix code read `v@project-version@`.
--   5. `dev`            (the same state, answered by the client itself) -> `dev`.
--   6. no version at all -> no version label, and no empty font string.
--
-- Two of these legs are the defect's class rather than its instance: a header
-- that shows whatever the TOC carries must not print the machinery (`v@…`) or a
-- doubled prefix, and both provider paths have to agree about a source checkout.
--
-- AC5 is measured too: the name text, the font token and the anchor of the
-- version label are unchanged — this card is one string, not a title-band edit.
--
-- TEETH: the same detector the legs use is run on what the pre-fix expression
-- produced for case 1 (`"v" .. "v0.3.12-beta"`) and must name it. A detector
-- that cannot redden is not evidence. (The card's non-vacuity gate — restore
-- `"v" .. ver` in the tree and watch this file redden naming the header — was
-- run before this fix was committed.)

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
tinsert, tremove, tsort = table.insert, table.remove, table.sort
format = string.format
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

-- The client's load list, exactly as the client runs it.
local tocPath = root .. "/MightiePack/MightiePack.toc"
local toc = assert(io.open(tocPath, "r"), "cannot open " .. tocPath)
local tocText = toc:read("*a")
toc:close()
local files = {}
for line in tocText:gmatch("[^\r\n]+") do
  local t = line:gsub("^%s+", ""):gsub("%s+$", "")
  if t ~= "" and not t:match("^##") then files[#files + 1] = t end
end
check(#files > 0, "the TOC lists files")

-- ── One window, built from a TOC that answers `version` ────────────────────
-- A fresh package per case: the header is read off a window that has just been
-- built, so no case can be answered by a label a previous case left behind.
-- `provider` picks which of the two metadata surfaces the client exposes;
-- both are real shapes on this pack's clients (the modern one on the Forever
-- client, the legacy global where it still exists).
local function build(version, provider)
  if provider == "legacy" then
    C_AddOns = nil
    GetAddOnMetadata = function(_, field)
      if field == "Version" then return version end
      return nil
    end
  else
    GetAddOnMetadata = nil
    C_AddOns = {
      GetAddOnMetadata = function(_, field)
        if field == "Version" then return version end
        return nil
      end,
    }
  end
  MightiePackDB = { modules = { Touchstone = true }, seen = { firstRun = true }, bugCount = 0 }
  StatForgeDB = { ui = { scale = 1 }, firstUse = false }

  local pkg = {}
  _G.MightiePack = pkg
  for _, f in ipairs(files) do
    local chunk, err = loadfile(root .. "/MightiePack/" .. f)
    check(chunk ~= nil, "loadfile " .. f .. ": " .. tostring(err))
    if not chunk then return nil end
    local ok, e = pcall(chunk, "MightiePack", pkg)
    check(ok, "load " .. f .. ": " .. tostring(e))
    if not ok then return nil end
  end
  local W = pkg.Window
  check(type(W) == "table", "pkg.Window exists")
  if type(W) ~= "table" then return nil end
  local ok, frame = pcall(W.Frame)
  check(ok and type(frame) == "table", "the window frame is created: " .. tostring(frame))
  return pkg, W
end

-- The one predicate every leg uses, and the teeth leg runs it backwards.
-- A doubled prefix and an unsubstituted token are the two ways this header has
-- rendered machinery instead of a version.
local function doubleV(text)
  if type(text) ~= "string" then return false end
  return text:find("vv", 1, true) ~= nil or text:find("v@", 1, true) ~= nil
end

local CASES = {
  {
    name = "a tagged release, the TOC carrying the tag's own v",
    version = "v0.3.12-beta", provider = "modern", expect = "v0.3.12-beta",
  },
  {
    name = "a TOC whose Version line has no v",
    version = "0.3.12-beta", provider = "modern", expect = "v0.3.12-beta",
  },
  {
    name = "a source checkout, modern provider (answered as dev)",
    version = "@project-version@", provider = "modern", expect = "dev",
  },
  {
    name = "a source checkout, legacy provider (the raw token)",
    version = "@project-version@", provider = "legacy", expect = "dev",
  },
  {
    name = "a dev answer from the client",
    version = "dev", provider = "modern", expect = "dev",
  },
  {
    name = "no version at all",
    version = nil, provider = "modern", expect = nil,
  },
}

for _, case in ipairs(CASES) do
  local pkg, W = build(case.version, case.provider)
  if pkg and W and type(W.title) == "table" then
    local text = type(W.version) == "table" and W.version:GetText() or nil
    print(string.format("header[%s] = %s", case.name, text and ("\"" .. tostring(text) .. "\"") or "(no label)"))

    -- The name is the title band's own font string and carries no version: the
    -- version is a separate, dimmer, smaller label beside it (card t_2d2c37b0).
    check(W.title:GetText() == "MightiePack",
      case.name .. ": the name text is unchanged, got " .. tostring(W.title:GetText()))

    if case.expect == nil then
      check(W.version == nil,
        case.name .. ": no version label is created, got " .. tostring(text))
    else
      check(type(W.version) == "table", case.name .. ": the header has a version label")
      check(text == case.expect,
        case.name .. ": header version reads \"" .. case.expect .. "\", got " .. tostring(text))
      -- AC2: the check that would have caught the release on the owner's screen.
      check(not doubleV(text),
        case.name .. ": the header version never contains vv or v@ — got \"" ..
        tostring(text) .. "\"")
      check(W.version.fontPath == "GameFontNormalSmall",
        case.name .. ": the label keeps the small font token, got " .. tostring(W.version.fontPath))
      local p = W.version.points and W.version.points[1]
      check(type(p) == "table" and p[1] == "LEFT" and p[2] == W.title and p[3] == "RIGHT"
        and p[4] == pkg.Theme.space.sm and p[5] == 0,
        case.name .. ": the label keeps its anchor (LEFT of the name's RIGHT at the theme gap)")
    end
  end
end

-- ── TEETH ──────────────────────────────────────────────────────────────────
-- The pre-fix expression, verbatim: Window.lua built `"v" .. ver` from a TOC
-- value of `v0.3.12-beta` and put that in the very font string read above.
local prefixBug = "v" .. "v0.3.12-beta"
check(prefixBug == "vv0.3.12-beta", "TEETH: the pre-fix expression really produces a doubled v")
check(doubleV(prefixBug), "TEETH: the detector names the pre-fix header \"" .. prefixBug .. "\"")
check(doubleV("v" .. "@project-version@"),
  "TEETH: the detector names the pre-fix dev header \"v@project-version@\"")
check(not doubleV("v0.3.12-beta"), "TEETH: the detector is silent on the fixed header")

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("window_header_version_spec: ok")
