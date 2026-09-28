-- Thunderstore rejects a package whose manifest.json, icon.png and
-- README.md are not at the ZIP ROOT, and rejects an icon that is not
-- exactly 256x256. A published version can never be replaced, so a
-- regression in scripts/build-package.sh that a green suite did not catch
-- would burn a version number on a package Thunderstore refuses.
--
-- This test runs the real build script. If the script or a tool it needs
-- is missing (a CI image without zip/unzip, say) it reports pending with a
-- reason rather than failing for a reason that has nothing to do with the
-- package layout.

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function shell(cmd)
  local p = io.popen(cmd)
  if not p then return nil end
  local out = p:read("a")
  p:close()
  return out
end

local function have(cmd)
  local out = shell("command -v " .. cmd .. " 2>/dev/null")
  return out ~= nil and out:match("%S") ~= nil
end

local function missing_prerequisite()
  if not file_exists("scripts/build-package.sh") then
    return "scripts/build-package.sh is not present"
  end
  for _, tool in ipairs({ "bash", "zip", "unzip" }) do
    if not have(tool) then
      return tool .. " is not available on this machine"
    end
  end
  return nil
end

describe("built package", function()
  it("has the Thunderstore-required files at the zip root with a 256x256 icon", function()
    local skip = missing_prerequisite()
    if skip then
      pending("skipped: " .. skip)
      return
    end

    local manifest = io.open("manifest.json", "r")
    local manifest_body = manifest:read("a")
    manifest:close()
    local version = manifest_body:match('"version_number"%s*:%s*"([^"]+)"')
    assert.truthy(version, "manifest.json has no version_number")

    assert.is_true(os.execute("bash scripts/build-package.sh >/dev/null 2>&1") == true,
      "scripts/build-package.sh exited non-zero")

    local zip = "dist/RVAdminMenu-" .. version .. ".zip"
    assert.is_true(file_exists(zip), "build script did not produce " .. zip)

    local listing = shell(string.format("unzip -Z1 %q", zip)) or ""
    local entries = {}
    for name in listing:gmatch("[^\r\n]+") do entries[name] = true end
    for _, required in ipairs({ "manifest.json", "icon.png", "README.md" }) do
      assert.is_true(entries[required] == true,
        required .. " is not at the root of " .. zip)
    end

    local png = shell(string.format("unzip -p %q icon.png", zip)) or ""
    assert.equal("\137PNG\r\n\26\n", png:sub(1, 8), "icon.png is not a PNG")
    assert.equal("IHDR", png:sub(13, 16), "icon.png has no IHDR chunk where one must be")
    assert.equal(256, string.unpack(">I4", png, 17), "icon.png width is not 256")
    assert.equal(256, string.unpack(">I4", png, 21), "icon.png height is not 256")
  end)
end)
