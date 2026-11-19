-- mightiepack_version_spec.lua — card t_c02c1643.
--
-- THE DEFECT (measured on a v0.3.12-beta build): the pack's Options footer read
-- `MightiePack vv0.3.12-beta`. The window header had the same doubled v and was
-- fixed one consumer at a time (card t_b1d7cd6a's local versionText()), which is
-- the right fix for one site and the wrong shape for a class: the TOC's
-- `## Version:` line is substituted from the git TAG by the packager, so a tagged
-- build arrives as `v0.3.12-beta` — leading v included — and every consumer that
-- adds its own "v" doubles it. Two consumers existed; the next one anybody wrote
-- would have doubled it again.
--
-- WHAT THIS SPEC PINS. The prefix is removed in ONE place — pkg.PackVersion()
-- (MightiePack/Core.lua) — and both pack surfaces are read off the real drawn
-- FontStrings, on a whole TOC loaded in its own order into a fresh package:
--
--   1. `v0.3.12-beta`   (a tagged release: what the client actually ships)
--      -> header `v0.3.12-beta`, footer `MightiePack v0.3.12-beta · …`.
--      This is the owner's screen; the footer leg is the one that survived the
--      first fix.
--   2. `0.3.12-beta`    (a TOC whose Version line has no v): both surfaces still
--      carry exactly one v, so the shape of the TOC cannot decide what the
--      player reads.
--   3. `@project-version@` through the MODERN provider (answered as "dev") and
--      through the LEGACY one (which hands back the raw token): neither surface
--      prints `v@project-version@`. The header reads `dev` and the footer reads
--      `MightiePack dev` — dev is a state, not a version, so it gets no v on
--      either surface, and both read the same label from the same function
--      (pkg.VersionLabel, Core.lua — card t_60042e97).
--   4. no version at all -> no header label, and the footer reads exactly
--      `MightiePack · …` — no stray separator, no empty `v`.
--
-- AC4 of the card is the detector below: NO rendered version string may contain
-- `vv` or `v@`, and it runs over BOTH the header and the footer. A header-only
-- assertion is how the footer survived the first fix.
--
-- AC3 of card t_60042e97 is the AGREEMENT predicate below: the footer's version
-- segment must be the header's label character for character. `vv` was one
-- symptom of two surfaces keeping separate copies of one convention; the
-- property is that they cannot disagree at all, whatever either is called. The
-- teeth leg runs that predicate on `("dev", "MightiePack vdev")` and must
-- redden naming the footer.
--
-- TEETH: the same detector is run on the pre-fix footer expression
-- (`"MightiePack" .. (" v" .. "v0.3.12-beta")`) and must name it. The card's
-- non-vacuity gate — restore the un-normalised PackVersion() and watch this file
-- redden naming the footer — was run, and is quoted in the handoff.
--
-- Card t_60042e97's gate, likewise: restore the footer's own `" v" .. ver`
-- (Options.lua) and watch the AGREEMENT check redden naming the footer, then
-- restore the fix. Quoted in that card's handoff.
--
-- The three Touchstone surfaces (subtitle, About, diagnostics) concatenate
-- Touchstone's OWN module version, SF.VERSION = "0.8.3", which carries no v;
-- they are measured in tests/touchstone_version_label_spec.lua, not here,
-- because the pack window hosts the Touchstone body and therefore builds no
-- Touchstone title bar (SF.Chrome().subtitle is nil under a host, by design).
--
-- Run from the repo root:  lua5.1 tests/mightiepack_version_spec.lua

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

-- ── One pack, built from a TOC that answers `version` ──────────────────────
-- A fresh package per case: both surfaces are read off a window and a panel
-- that have just been built, so no case can be answered by a label a previous
-- case left behind. `provider` picks which of the two metadata surfaces the
-- client exposes; both are real shapes on this pack's clients.
local function build(version, provider)
  if provider == "legacy" then
    C_AddOns = nil
    GetAddOnMetadata = function(_, field)
      if field == "Version" then return version end
      if field == "Interface" then return "16001" end
      return nil
    end
  else
    GetAddOnMetadata = nil
    C_AddOns = {
      GetAddOnMetadata = function(_, field)
        if field == "Version" then return version end
        if field == "Interface" then return "16001" end
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

-- Every FontString under `frame`, depth-first: the surfaces are read off what
-- was drawn, not off a re-derivation of their text.
local function texts(frame, out, seen)
  out, seen = out or {}, seen or {}
  if type(frame) ~= "table" or seen[frame] then return out end
  seen[frame] = true
  if type(frame.GetText) == "function" then
    local ok, t = pcall(frame.GetText, frame)
    if ok and type(t) == "string" and t ~= "" then out[#out + 1] = t end
  end
  local ok, kids = pcall(frame.GetChildren, frame)
  if ok and type(kids) == "table" then
    for _, child in ipairs(kids) do texts(child, out, seen) end
  end
  return out
end

--- The pack's Options footer as drawn: the one label under the panel that
--- carries the diagnostic hint. Exactly one may exist — a second footer would
--- be its own defect and would hide a stale one.
local FOOTER_MARK = "/mp status prints a diagnostic you can paste"
local function footerText(pkg)
  local hits = {}
  for _, t in ipairs(texts(pkg.optionsPanel, {})) do
    if t:find(FOOTER_MARK, 1, true) then hits[#hits + 1] = t end
  end
  check(#hits == 1, "the Options panel draws exactly one footer, got " .. #hits)
  return hits[1]
end

--- The first segment of the footer, up to the ` · ` separator: the part that
--- carries the name and the version.
local function footerHead(text)
  if type(text) ~= "string" then return nil end
  local head = text:match("^([^·]*)") or text
  return (head:gsub("%s+$", ""))
end

-- The one predicate every leg uses, and the teeth leg runs it backwards.
-- A doubled prefix and an unsubstituted token are the two ways these surfaces
-- have rendered machinery instead of a version.
local function doubleV(text)
  if type(text) ~= "string" then return false end
  return text:find("vv", 1, true) ~= nil or text:find("v@", 1, true) ~= nil
end

--- AC4: the check that would have caught the footer. Run on every rendered
--- version string from BOTH surfaces of one case.
local function checkSurface(caseName, surface, text, expectHead)
  check(type(text) == "string", caseName .. ": the " .. surface .. " renders a string")
  if type(text) ~= "string" then return end
  check(not doubleV(text),
    caseName .. ": the " .. surface .. " never contains vv or v@ — got \"" .. text .. "\"")
  if expectHead ~= nil then
    local head = (surface == "footer") and footerHead(text) or text
    check(head == expectHead,
      caseName .. ": the " .. surface .. " reads \"" .. expectHead .. "\", got \"" ..
      tostring(head) .. "\"")
  end
end

--- AC3: the two surfaces of ONE build agree about the version. The footer's
--- head is the name plus — when there is a label — one space and exactly the
--- string the header draws; with no label it is the bare name. Returns nil when
--- they agree, a message naming the footer when they do not, so the teeth leg
--- can run the same predicate backwards.
local function agreementProblem(header, footerHeadText)
  if type(footerHeadText) ~= "string" then
    return "the footer renders no head string"
  end
  local want = header and ("MightiePack " .. header) or "MightiePack"
  if footerHeadText ~= want then
    return "the footer disagrees with the header about the version: the header " ..
      "reads \"" .. tostring(header) .. "\", the footer's head reads \"" ..
      footerHeadText .. "\", expected \"" .. want .. "\""
  end
  return nil
end

local CASES = {
  {
    name = "a tagged release, the TOC carrying the tag's own v",
    version = "v0.3.12-beta", provider = "modern",
    packVersion = "0.3.12-beta",
    header = "v0.3.12-beta", footer = "MightiePack v0.3.12-beta",
  },
  {
    name = "the same tag through the legacy metadata global",
    version = "v0.3.12-beta", provider = "legacy",
    packVersion = "0.3.12-beta",
    header = "v0.3.12-beta", footer = "MightiePack v0.3.12-beta",
  },
  {
    name = "a TOC whose Version line has no v",
    version = "0.3.12-beta", provider = "modern",
    packVersion = "0.3.12-beta",
    header = "v0.3.12-beta", footer = "MightiePack v0.3.12-beta",
  },
  {
    name = "a source checkout, modern provider (answered as dev)",
    version = "@project-version@", provider = "modern",
    packVersion = "dev",
    header = "dev", footer = "MightiePack dev",
  },
  {
    name = "a source checkout, legacy provider (the raw token)",
    version = "@project-version@", provider = "legacy",
    packVersion = "dev",
    header = "dev", footer = "MightiePack dev",
  },
  {
    name = "a dev answer from the client",
    version = "dev", provider = "modern",
    packVersion = "dev",
    header = "dev", footer = "MightiePack dev",
  },
  {
    name = "no version at all",
    version = nil, provider = "modern",
    packVersion = nil,
    header = nil, footer = "MightiePack",
  },
}

for _, case in ipairs(CASES) do
  local pkg, W = build(case.version, case.provider)
  if pkg and W then
    -- The source contract first: one place removes the tag's prefix.
    local okV, got = pcall(pkg.PackVersion)
    check(okV, case.name .. ": pkg.PackVersion does not raise")
    check(got == case.packVersion,
      case.name .. ": pkg.PackVersion reads \"" .. tostring(case.packVersion) ..
      "\", got \"" .. tostring(got) .. "\"")
    check(not doubleV(got), case.name .. ": pkg.PackVersion itself carries one v at most")

    -- The header, straight off the drawn label.
    local header = type(W.version) == "table" and W.version:GetText() or nil
    print(string.format("header[%s] = %s", case.name,
      header and ("\"" .. tostring(header) .. "\"") or "(no label)"))
    if case.header == nil then
      check(W.version == nil, case.name .. ": no header version label is created, got " ..
        tostring(header))
    else
      checkSurface(case.name, "header", header, case.header)
    end

    -- The footer, off the drawn label under the panel.
    local footer = footerText(pkg)
    print(string.format("footer[%s] = %s", case.name,
      footer and ("\"" .. tostring(footer) .. "\"") or "(none)"))
    checkSurface(case.name, "footer", footer, case.footer)
    if case.packVersion == nil then
      -- AC3: no stray separator where the version would have been.
      check(type(footer) == "string" and footer:find("MightiePack  ", 1, true) == nil,
        case.name .. ": no doubled separator after the name — got \"" .. tostring(footer) .. "\"")
    end
    check(type(footer) == "string" and footer:find(FOOTER_MARK, 1, true) ~= nil,
      case.name .. ": the footer still carries the diagnostic hint")

    -- AC3: the two surfaces agree — every case, not only the dev one.
    local problem = agreementProblem(case.header, footerHead(footer))
    check(problem == nil, case.name .. ": " .. tostring(problem))
  end
end

-- ── TEETH ──────────────────────────────────────────────────────────────────
-- The pre-fix footer expression, verbatim: Options.lua built
-- `"MightiePack" .. (ver and (" v" .. ver) or "")` from a PackVersion() that
-- still carried the tag's v.
local prefixBug = "MightiePack" .. (" v" .. "v0.3.12-beta")
check(prefixBug == "MightiePack vv0.3.12-beta",
  "TEETH: the pre-fix footer expression really produces a doubled v")
check(doubleV(prefixBug),
  "TEETH: the detector names the pre-fix footer \"" .. prefixBug .. "\"")
check(doubleV("MightiePack" .. (" v" .. "v@project-version@")),
  "TEETH: the detector names the pre-fix dev footer \"MightiePack v@project-version@\"")
check(not doubleV("MightiePack v0.3.12-beta"), "TEETH: the detector is silent on the fixed footer")

-- TEETH for the AGREEMENT predicate. The pre-fix dev pair is exactly what card
-- t_60042e97 exists to remove: a header reading `dev` and a footer reading
-- `MightiePack vdev` — no `vv` anywhere, and still two surfaces disagreeing.
local devBug = "MightiePack" .. (" v" .. "dev")
check(devBug == "MightiePack vdev",
  "TEETH: the pre-fix dev footer expression is \"MightiePack vdev\"")
check(not doubleV(devBug),
  "TEETH: the `vv` detector alone is blind to it — which is why AC3 is agreement, not a substring")
local devProblem = agreementProblem("dev", devBug)
check(type(devProblem) == "string",
  "TEETH: the agreement check reddens on the pre-fix dev footer \"" .. devBug .. "\"")
check(type(devProblem) == "string" and devProblem:find("footer", 1, true) ~= nil,
  "TEETH: the reddened message names the footer — got " .. tostring(devProblem))
check(agreementProblem("dev", "MightiePack dev") == nil,
  "TEETH: the agreement check is silent on the fixed dev footer")
check(agreementProblem(nil, "MightiePack") == nil,
  "TEETH: the agreement check is silent when neither surface has a label")
check(not doubleV("v0.3.12-beta"), "TEETH: the detector is silent on the fixed header")
check(not doubleV("dev"), "TEETH: the detector is silent on a dev build")

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("mightiepack_version_spec: ok")
