-- theme_tokens_spec.lua — card t_2d2c37b0 (the reshape + design pass).
--
-- The card's first "done when": *theme tokens exist as one source and are
-- consumed by every tab — prove it: grep for raw hex in the window files and
-- report the count, expected 0 outside the token file.*
--
-- This spec is that proof, made repeatable instead of a one-off grep. It has
-- two halves, and both must hold:
--
--   A. THE SOURCE. `MightiePack/Theme.lua` publishes one vocabulary — colour,
--      font objects, spacing, sizes, textures, insets and the item list's own
--      metrics — and the window's own files (Window.lua, Window/TouchstoneTab.lua,
--      Options.lua) contain NO colour or texture literals of their own. A literal
--      that comes back is a second palette, and a second palette is exactly the
--      "panel of panels" look this card exists to end.
--
--   B. THE IDENTITY. The palette the window draws with is the SAME TABLE the
--      vendored Touchstone body draws with (StatForge.Colors). Not a copy that
--      matches today: the same Lua table, so the chrome and the body cannot
--      drift apart when either side is tuned.
--
-- Not a screenshot: harness/source evidence. A true in-game capture needs the
-- live client (the card's OWNER-RUN / BLOCKED note).

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

local function lines(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for line in (text .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = line
  end
  return out
end

-- ── A1. The token file loads and publishes one vocabulary ─────────────────
local pkg = {}
local function loadPack(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return nil end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. path .. ": " .. tostring(e))
  return ok
end

-- The real vendored brand table, not a stub: the whole point is that the
-- window adopts the body's table, so the spec must build the real one.
loadPack("Modules/Touchstone/Constants.lua")
check(type(StatForge) == "table" and type(StatForge.Colors) == "table",
  "precondition: the vendored body publishes StatForge.Colors")

loadPack("Theme.lua")
local T = pkg.Theme
check(type(T) == "table", "MightiePack/Theme.lua publishes pkg.Theme")

-- B. THE IDENTITY: one table, shared.
if type(T) == "table" then
  check(type(T.Brand) == "function", "the theme can name the brand table (T.Brand)")
  if type(T.Brand) == "function" then
    check(T.Brand() == StatForge.Colors,
      "the window's palette IS the body's table (not a matching copy)")
  end

  -- The fallback exists for the one case that needs it: a spec that loads the
  -- window without the body. It must not become a second truth — every brand
  -- value it states must equal the body's.
  check(type(T.fallback) == "table", "the theme carries a fallback palette")
  local brands = { "accent", "accentDim", "bg", "surface", "surfaceHover", "border",
                   "text", "textMuted", "textDim", "success", "warning", "danger",
                   "white", "black" }
  for _, name in ipairs(brands) do
    local real = StatForge.Colors[name]
    local fall = type(T.fallback) == "table" and T.fallback[name] or nil
    check(type(real) == "table" and type(fall) == "table",
      "both tables state colour " .. name)
    if type(real) == "table" and type(fall) == "table" then
      local same = real[1] == fall[1] and real[2] == fall[2] and real[3] == fall[3]
      check(same, "the fallback's " .. name .. " equals the body's (no silent second palette)")
    end
  end

  -- Every group the window needs, named once.
  for _, group in ipairs({ "font", "space", "size", "tex", "inset", "pack", "list" }) do
    check(type(T[group]) == "table", "the theme publishes the " .. group .. " group")
  end

  -- Colour lookup answers with the brand's values, and an unknown name is a
  -- visible white rather than nil (a nil in SetTextColor raises in the client).
  if type(T.R) == "function" then
    local r, g, b = T.R("accent", 1)
    local a = StatForge.Colors.accent
    check(r == a[1] and g == a[2] and b == a[3], "T.R('accent') returns the brand accent")
    local wr, wg, wb, wa = T.R("no_such_token")
    check(wr == 1 and wg == 1 and wb == 1 and wa == 1,
      "an unknown colour token is white, never nil")
  else
    check(false, "the theme exposes T.R(name, alpha)")
  end
end

-- ── A2. The window files carry no literals of their own ───────────────────
local WINDOW_FILES = {
  "Window.lua",
  "Window/TouchstoneTab.lua",
  "Options.lua",
}

-- `{ 0.12, 0.34, 0.56 }` — a colour triple/quad written inline anywhere.
local function hasColourLiteral(line)
  local body = line:gsub("^%s*%-%-.*$", "")
  for a, b, c in body:gmatch("(%d+%.?%d*)%s*,%s*(%d+%.?%d*)%s*,%s*(%d+%.?%d*)") do
    local n1, n2, n3 = tonumber(a), tonumber(b), tonumber(c)
    if n1 and n2 and n3 and n1 <= 1 and n2 <= 1 and n3 <= 1 then
      -- A grid of small integers (1, 2, 3) is not a colour; a colour is at
      -- least one fractional component or an explicit 0..1 triple of floats.
      local fractional = a:find("%.") or b:find("%.") or c:find("%.")
      if fractional then return true end
    end
  end
  return false
end

local offenders = {}
for _, rel in ipairs(WINDOW_FILES) do
  local text = readFile(root .. "/MightiePack/" .. rel)
  check(text ~= nil, rel .. " exists")
  for i, line in ipairs(lines(text)) do
    local trimmed = line:gsub("^%s+", "")
    local inComment = trimmed:sub(1, 2) == "--"
    if not inComment then
      if line:find("0x%x%x") then
        offenders[#offenders + 1] = rel .. ":" .. i .. " raw hex byte literal"
      end
      if line:find("#%x%x%x%x%x%x") then
        offenders[#offenders + 1] = rel .. ":" .. i .. " raw #RRGGBB literal"
      end
      if hasColourLiteral(line) then
        offenders[#offenders + 1] = rel .. ":" .. i .. " inline colour triple"
      end
      if line:find("Interface\\\\", 1, true) then
        offenders[#offenders + 1] = rel .. ":" .. i .. " hard-coded texture path"
      end
    end
  end
end

check(#offenders == 0, "no colour/texture literals in the window files (found "
  .. tostring(#offenders) .. "): " .. table.concat(offenders, "; "))

-- The token file itself is where literals are allowed. If it has none, the
-- palette came from somewhere else and this pass measured nothing.
local themeText = readFile(root .. "/MightiePack/Theme.lua") or ""
check(themeText:find("%d%.%d%d%d"), "Theme.lua is the one file that states colour values")

-- ── A3. The ITEM LIST reads the same token file ───────────────────────────
-- mira's note on the card: the row model's spacing belongs WITH the list's
-- theme tokens, not bolted on. The vendored UpgradesTab is a file we do not
-- own, so its values arrive through the theme's published global; this leg
-- checks the wiring rather than trusting the patch text.
local upg = readFile(root .. "/MightiePack/Modules/Touchstone/UpgradesTab.lua") or ""
check(upg ~= "", "UpgradesTab.lua is readable")
check(upg:find("MightiePackTheme", 1, true) ~= nil,
  "the item list reads the pack's theme (MightiePackTheme) for its metrics")
check(upg:find("local ROW_H   = 34", 1, true) == nil,
  "the item list no longer states ROW_H as a bare literal of its own")
for _, key in ipairs({ "rowMin", "rowPad", "icon", "mark", "inset", "nameGap" }) do
  check(upg:find("LIST%." .. key) ~= nil,
    "the item list takes " .. key .. " from the theme's T.list")
end
if type(T) == "table" and type(T.list) == "table" then
  for _, key in ipairs({ "rowMin", "rowPad", "icon", "mark", "inset", "nameGap" }) do
    check(type(T.list[key]) == "number", "the theme publishes T.list." .. key)
  end
end
-- And the global is the same table as pkg.Theme: one vocabulary, one name the
-- vendored file can reach without depending on the body's load order.
check(MightiePackTheme == T, "MightiePackTheme is the same table as pkg.Theme")

if failed == 0 then
  print("theme_tokens_spec: ok")
else
  print(("theme_tokens_spec: %d failure(s)"):format(failed))
  os.exit(1)
end
