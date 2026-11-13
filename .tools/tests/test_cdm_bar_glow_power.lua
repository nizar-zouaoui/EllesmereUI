-- Run from the repository root: lua .tools/tests/test_cdm_bar_glow_power.lua
-- Glow When Usable keeps its legacy power-agnostic behavior by default, while
-- the opt-in resource-aware path treats missing power as unavailable.
local ROOT = arg and arg[1] or "."

local f = assert(io.open(ROOT .. "/EllesmereUICooldownManager/EUI_CDM_HookIconWatch.lua", "rb"))
local src = f:read("*a")
f:close()

local start = assert(src:find("function ns.CdmSpellNotUsable%(liveSid, requirePower%)"))
local finish = assert(src:find("\nend", start))
local fn = assert(loadstring(src:sub(start, finish + 3) .. "\nreturn ns.CdmSpellNotUsable"))

local ns = {}
local usable, noPower
C_Spell = {
    IsSpellUsable = function()
        return usable, noPower
    end,
}
setfenv(fn, setmetatable({ ns = ns, C_Spell = C_Spell }, { __index = _G }))
local notUsable = assert(fn())

local function Check(expectedDefault, expectedRequired, isUsable, lacksPower)
    usable, noPower = isUsable, lacksPower
    assert(notUsable(123) == expectedDefault, "legacy usability result")
    assert(notUsable(123, true) == expectedRequired, "resource-aware usability result")
end

Check(false, false, true, false)
Check(false, true, false, true)
Check(true, true, false, false)

print("test_cdm_bar_glow_power: all checks passed")
