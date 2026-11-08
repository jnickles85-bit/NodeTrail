-- Asset-path invariant for the vendored Touchstone.
--
-- Upstream hardcodes the art path as Interface\AddOns\Touchstone\... , which is
-- where the standalone addon lived. Once the files are vendored under
-- MightiePack/Modules/Touchstone/, that path resolves to nothing: the bag arrow
-- and the toast arrow render as empty textures, so an upgrade is judged (the
-- item tooltip says "Touchstone: Upgrade") but never marked in the bags.
--
-- Every vendored file must therefore build the path from the addon name it was
-- loaded with, via MIGHTIEPACK_TOUCHSTONE_ASSETS.
--
-- Fails on build 51656e0, which still hardcoded the standalone path.

local here = (arg and arg[0] or "tests/touchstone_assets_spec.lua"):match("^(.*)[/\\][^/\\]*$") or "."
local root = here:gsub("[/\\]tests$", "")
if root == "tests" then root = "." end
local dir = root .. "/MightiePack/Modules/Touchstone"

local fails = 0
local function check(cond, msg)
  if not cond then
    print("FAIL: " .. msg)
    fails = fails + 1
  end
end

local function readAll(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- The literal, as bytes: AddOns\\Touchstone (two backslashes inside the string).
local HARDCODED = "AddOns\\\\Touchstone"

local files = {}
local p = io.popen('find "' .. dir .. '" -name "*.lua" 2>/dev/null')
if p then
  for line in p:lines() do files[#files + 1] = line end
  p:close()
end
check(#files > 0, "found vendored Touchstone lua files under " .. dir)

local usesMarker = 0
for _, path in ipairs(files) do
  local src = readAll(path)
  check(src ~= nil, "readable: " .. path)
  if src then
    local short = path:match("([^/\\]+)$")
    check(not src:find(HARDCODED, 1, true),
      short .. ": no hardcoded AddOns\\Touchstone asset path")
    if src:find("marker.tga", 1, true) then
      usesMarker = usesMarker + 1
      check(src:find("MIGHTIEPACK_TOUCHSTONE_ASSETS", 1, true) ~= nil,
        short .. ": marker.tga is built from MIGHTIEPACK_TOUCHSTONE_ASSETS")
      check(src:find("local MIGHTIEPACK_TOUCHSTONE_ASSETS%s*=") ~= nil,
        short .. ": defines MIGHTIEPACK_TOUCHSTONE_ASSETS before use")
    end
  end
end
check(usesMarker >= 2, "at least the bag/toast file and the upgrades tab reference marker.tga")

-- The constant must resolve to the vendored folder, not the standalone one.
local probe = readAll(dir .. "/ChestAdvisor/ChestAdvisor.lua") or ""
check(probe:find('"\\\\Modules\\\\Touchstone\\\\ChestAdvisor\\\\"') ~= nil,
  "asset root appends Modules\\Touchstone\\ChestAdvisor\\")

if fails == 0 then
  print("touchstone_assets_spec: ok")
else
  print(("touchstone_assets_spec: %d failure(s)"):format(fails))
  os.exit(1)
end
