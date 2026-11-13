if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUICdmBarGlowConditions.lua
--  Extra conditions on a Bar Glow entry, evaluated after the entry's own
--  Glow When result (ns.BarGlowCombine, called from UpdateOverlayVisuals):
--
--    entry.andMode       = "and" | nil (off)
--    entry.conditions[1] = { spellID = n, state = nil (active) | "missing" }
--        The glow also needs a second buff active (or missing). Read from the
--        same active-aura cache the trigger uses (ns._tickBlizzActiveCache:
--        plain booleans, so safe in combat). An "or" is simply a second glow
--        entry on the same button. A second buff not chosen yet changes nothing.
--
--    entry.heroTree      = hero talent subTreeID | nil (any)
--        The glow only runs while that hero tree is active, so one button can
--        carry different glows per hero tree. Ignored on WoW Forever (no hero
--        talents), so a glow imported from retail still lights there.
--
--    entry.healthBelow   = percentage | nil
--    entry.healthAbove   = percentage | nil
--        The glow only runs while the player's health percentage is strictly
--        below or above the selected value. Older healthBelow entries remain
--        below-threshold rules. This can be combined with Glow When Usable and
--        its resource policy, or with the buff condition above.
--
--  Cost: nothing for entries without these keys. The hero
--  tree is one C call per hero-gated entry per glow pass, no cache and no
--  events of our own; ns._barGlowAnyHero (set by SetupOverlays) lets the
--  talent-change handler re-run the glow pass only while such an entry exists.
-------------------------------------------------------------------------------
local _, ns = ...

local function ActiveHeroTree()
    local CT = C_ClassTalents
    local id = CT and CT.GetActiveHeroTalentSpec and CT.GetActiveHeroTalentSpec()
    if type(id) == "number" and id > 0 then return id end
    return nil
end

local healthCurves = {}

local function HealthBelow(entry)
    local threshold = tonumber(entry.healthBelow)
    if not threshold or threshold <= 0 then return true end
    local current = UnitHealth and UnitHealth("player")
    local maximum = UnitHealthMax and UnitHealthMax("player")
    if not current or not maximum or maximum <= 0 then return false end
    if issecretvalue and (issecretvalue(current) or issecretvalue(maximum)) then return true end
    return current / maximum * 100 < threshold
end

local function HealthPass(entry)
    local above = tonumber(entry.healthAbove)
    if above and above > 0 then
        local current = UnitHealth and UnitHealth("player")
        local maximum = UnitHealthMax and UnitHealthMax("player")
        if not current or not maximum or maximum <= 0 then return false end
        if issecretvalue and (issecretvalue(current) or issecretvalue(maximum)) then return true end
        return current / maximum * 100 > above
    end
    return HealthBelow(entry)
end

local function HealthCurve(above, threshold)
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType) then return nil end
    local key = (above and "above:" or "below:") .. threshold
    local curve = healthCurves[key]
    if curve then return curve end
    curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    if above then
        curve:AddPoint(0, 0)
        curve:AddPoint(threshold / 100, 0)
        if threshold < 100 then
            curve:AddPoint(math.min(1, (threshold + 0.0001) / 100), 1)
            curve:AddPoint(1, 1)
        end
    else
        curve:AddPoint(0, 1)
        curve:AddPoint(threshold / 100, 0)
        curve:AddPoint(1, 0)
    end
    healthCurves[key] = curve
    return curve
end

function ns.BarGlowHealthNative(entry)
    local threshold = tonumber(entry.healthAbove) or tonumber(entry.healthBelow)
    local curve = threshold and HealthCurve(entry.healthAbove ~= nil, threshold)
    if not (curve and UnitHealthPercent) then return false end
    return true, UnitHealthPercent("player", false, curve)
end

function ns.BarGlowHealthPass(entry)
    return HealthPass(entry)
end

-- Secret health cannot be compared in Lua. Return a native-consumable
-- percentage and operator so BarGlows.lua can gate the glow with a StatusBar.
function ns.BarGlowHealthSecret(entry)
    local native, value = ns.BarGlowHealthNative(entry)
    if native then return 1, "gte", value end
end

-- The current spec's hero trees, for the options dropdown:
-- { { id = subTreeID, name = "Spellslinger" }, ... }
function ns.BarGlowHeroTrees()
    local out = {}
    local CT = C_ClassTalents
    if not (CT and CT.GetHeroTalentSpecsForClassSpec and CT.GetActiveConfigID) then return out end
    local configID = CT.GetActiveConfigID()
    local ok, ids = pcall(CT.GetHeroTalentSpecsForClassSpec, configID)
    if not ok or type(ids) ~= "table" then return out end
    for _, id in ipairs(ids) do
        local info = configID and C_Traits and C_Traits.GetSubTreeInfo and C_Traits.GetSubTreeInfo(configID, id)
        out[#out + 1] = { id = id, name = (info and info.name) or ("Hero Tree " .. id) }
    end
    return out
end

-- The entry's final glow state, given its own Glow When result `main`.
function ns.BarGlowCombine(entry, main, cache)
    local hero = entry.heroTree
    if hero and not EllesmereUI.IS_FOREVER and ActiveHeroTree() ~= hero then return false end
    if (entry.healthBelow or entry.healthAbove) and not HealthPass(entry) then return false end
    if entry.andMode ~= "and" then return main end
    local c = type(entry.conditions) == "table" and entry.conditions[1]
    local sid = type(c) == "table" and tonumber(c.spellID)
    if not sid or sid <= 0 then return main end
    local active = (cache ~= nil and cache[sid] == true)
    local ok
    if c.state == "missing" then ok = not active else ok = active end
    return (main and ok) and true or false
end
