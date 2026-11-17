-- Stub harness: Self Combat Text's power gains. Loads
-- EllesmereUIQoL_SelfCombatText.lua over stubs of the frame, font string and
-- animation API and C_CombatText, then drives COMBAT_TEXT_UPDATE ENERGIZE and
-- PERIODIC_ENERGIZE through its event handler. Checks the category is off by
-- default, shows "+amount Power" in its colour once on, skips a known gain of
-- zero, never compares or indexes a secret amount or token, and keeps
-- COMBAT_TEXT_UPDATE registered while it is the only category on.
-- The model is this file's reading of the client, not the client.
--   lua .tools/tests/test_sct_power_gains.lua   (from the repository root)
local SCT = SCT_FILE or "EllesmereUIQoL/EllesmereUIQoL_SelfCombatText.lua"

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local function Read(path)
    local fh = assert(io.open(path, "rb"))
    local s = fh:read("*a")
    fh:close()
    return s
end
local SRC = Read(SCT)

-- A secret value: any compare, index, arithmetic or concat on it raises.
local function Boom() error("operated on a secret value", 2) end
local SECRET_MT = { __lt = Boom, __le = Boom, __index = Boom, __newindex = Boom, __add = Boom,
    __sub = Boom, __concat = Boom, __len = Boom, __call = Boom, __tostring = function() return "<secret>" end }
local function Secret() return setmetatable({}, SECRET_MT) end
local function IsSecret(v) return type(v) == "table" and getmetatable(v) == SECRET_MT end

-------------------------------------------------------------------------------
--  Game stubs
-------------------------------------------------------------------------------
local shown, registered, onEvent, eventInfo

local function Anim()
    local a = {}
    function a:SetOffset() end
    function a:SetDuration() end
    function a:SetCurveType() end
    function a:SetStartDelay() end
    function a:SetFromAlpha() end
    function a:SetToAlpha() end
    function a:CreateControlPoint() return Anim() end
    return a
end

local function FontString()
    local fs = {}
    function fs:Hide() end
    function fs:Show() end
    function fs:ClearAllPoints() end
    function fs:SetPoint() end
    function fs:SetFont() end
    function fs:SetAlpha() end
    function fs:SetTextColor(r, g, b) self._c = { r, g, b } end
    -- C-side in the client: secret arguments are fine here, and only here.
    function fs:SetFormattedText(fmt, ...)
        local args = { ... }
        for i = 1, select("#", ...) do
            if IsSecret(args[i]) then args[i] = "<secret>" end
        end
        shown[#shown + 1] = { text = string.format(fmt, unpack(args, 1, select("#", ...))), c = self._c }
    end
    function fs:CreateAnimationGroup()
        local ag = {}
        function ag:CreateAnimation() return Anim() end
        function ag:SetScript() end
        function ag:Stop() end
        function ag:Play() end
        return ag
    end
    return fs
end

local function Frame()
    local f = {}
    function f:SetSize() end
    function f:SetFrameStrata() end
    function f:SetPoint() end
    function f:ClearAllPoints() end
    function f:Show() end
    function f:Hide() end
    function f:CreateFontString() return FontString() end
    function f:RegisterEvent(e) registered[e] = true end
    function f:RegisterUnitEvent(e) registered[e] = true end
    function f:UnregisterEvent(e) registered[e] = nil end
    function f:UnregisterAllEvents() for k in pairs(registered) do registered[k] = nil end end
    function f:SetScript(name, fn) if name == "OnEvent" then onEvent = fn end end
    return f
end

local ns, profile
local function Load(settings)
    shown, registered, onEvent, eventInfo = {}, {}, nil, {}
    profile = { selfCombatText = settings }
    EUI_CLIENT_BLOCKED = nil
    issecretvalue = IsSecret
    CreateFrame = Frame
    UIParent = Frame()
    STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    CombatText = nil
    GetTime = function() return 0 end
    UnitHasVehicleUI = function() return false end
    BreakUpLargeNumbers = function(n)
        if IsSecret(n) then return n end
        return tostring(n)
    end
    AbbreviateNumbers = BreakUpLargeNumbers
    C_CombatText = {
        SetActiveUnit = function() end,
        GetCurrentEventInfo = function() return eventInfo[1], eventInfo[2], eventInfo[3] end,
    }
    MANA, RAGE, ENERGY, HOLY_POWER = "Mana", "Rage", "Energy", "Holy Power"
    COMBAT_TEXT_DODGE = "Dodge"
    EllesmereUIDB = {}
    EllesmereUI = {
        Lite = { NewDB = function() return { profile = profile } end },
        GetFontPath = function() return "x" end,
        ResolveFontName = function() return "x" end,
        SlugFlag = function(s) return s end,
        PrimeFontShadow = function() end,
        MakeUnlockElement = function(t) return t end,
        RegisterUnlockElements = function() end,
    }
    _G.EllesmereUI = EllesmereUI
    ns = {}
    assert(loadstring(SRC, "=EllesmereUIQoL_SelfCombatText.lua"))("EllesmereUIQoL", ns)
    ns.SCT_Refresh()
end

local function Fire(kind, amount, token)
    shown = {}
    eventInfo = { amount, token }
    local ok, err = pcall(onEvent, nil, "COMBAT_TEXT_UPDATE", kind)
    return ok, err
end

-------------------------------------------------------------------------------
--  1. Off by default: an existing profile gains no power messages
-------------------------------------------------------------------------------
Load({ enabled = true })
check(ns.SCT_Get("power") == false, "power gains are not off by default")
Fire("ENERGIZE", 25, "RAGE")
check(#shown == 0, "a power gain showed with the category at its default")

-------------------------------------------------------------------------------
--  2. On: "+amount Power" in the power colour, for both energize kinds
-------------------------------------------------------------------------------
Load({ enabled = true, power = true, powerColor = { r = 0.2, g = 0.4, b = 0.6 } })
for _, kind in ipairs({ "ENERGIZE", "PERIODIC_ENERGIZE" }) do
    local ok, err = Fire(kind, 25, "RAGE")
    check(ok, kind .. ": raised " .. tostring(err))
    check(#shown == 1 and shown[1].text == "+25 Rage", kind .. ": showed " .. tostring(shown[1] and shown[1].text))
    local c = shown[1] and shown[1].c
    check(c and c[1] == 0.2 and c[2] == 0.4 and c[3] == 0.6, kind .. ": not in the power colour")
end
Fire("ENERGIZE", 1, "HOLY_POWER")
check(shown[1] and shown[1].text == "+1 Holy Power", "a secondary power gain showed " .. tostring(shown[1] and shown[1].text))

-- A token with no localized string, or one naming a non-string global, shows the amount alone
Fire("ENERGIZE", 3, "NOT_A_POWER")
check(shown[1] and shown[1].text == "+3", "an unknown token showed " .. tostring(shown[1] and shown[1].text))
Fire("ENERGIZE", 3, "C_CombatText")
check(shown[1] and shown[1].text == "+3", "a token naming a table showed " .. tostring(shown[1] and shown[1].text))

-------------------------------------------------------------------------------
--  3. A known gain of zero or less is no gain
-------------------------------------------------------------------------------
for _, amount in ipairs({ 0, -5 }) do
    local ok, err = Fire("ENERGIZE", amount, "MANA")
    check(ok and #shown == 0, "a gain of " .. amount .. " showed or raised " .. tostring(err))
end
local ok, err = Fire("ENERGIZE", nil, "MANA")
check(ok and #shown == 0, "a missing amount showed or raised " .. tostring(err))

-------------------------------------------------------------------------------
--  4. Secrets reach only the formatter
-------------------------------------------------------------------------------
ok, err = Fire("ENERGIZE", Secret(), "MANA")
check(ok, "a secret amount raised " .. tostring(err))
check(shown[1] and shown[1].text == "+<secret> Mana", "a secret amount showed " .. tostring(shown[1] and shown[1].text))
ok, err = Fire("ENERGIZE", 10, Secret())
check(ok, "a secret token raised " .. tostring(err))
check(shown[1] and shown[1].text == "+10", "a secret token showed " .. tostring(shown[1] and shown[1].text))
ok, err = Fire("PERIODIC_ENERGIZE", Secret(), Secret())
check(ok and shown[1] and shown[1].text == "+<secret>", "a secret amount and token raised or showed wrong")

-------------------------------------------------------------------------------
--  5. The other categories are untouched, and the event follows the category
-------------------------------------------------------------------------------
Fire("DODGE")
check(shown[1] and shown[1].text == "Dodge", "an avoid no longer shows with power gains on")

Load({ enabled = true, power = true, damage = false, heal = false, avoid = false })
check(registered.COMBAT_TEXT_UPDATE, "COMBAT_TEXT_UPDATE is not registered with only power gains on")
Fire("ENERGIZE", 5, "ENERGY")
check(shown[1] and shown[1].text == "+5 Energy", "power gains alone showed " .. tostring(shown[1] and shown[1].text))
Fire("DODGE")
check(#shown == 0, "an avoid showed with avoidance off")

Load({ enabled = true, damage = false, heal = false, avoid = false })
check(not registered.COMBAT_TEXT_UPDATE, "COMBAT_TEXT_UPDATE is registered with every combat text category off")
ns.SCT_Set("power", true)
check(registered.COMBAT_TEXT_UPDATE, "turning power gains on did not register COMBAT_TEXT_UPDATE")

print(string.format("self combat text power gains harness: %d checks, %d failed", count, fails))
if fails > 0 then error("self combat text power gains harness failed") end
