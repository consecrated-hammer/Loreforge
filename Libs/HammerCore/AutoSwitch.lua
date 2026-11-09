local addonName, ns = ...
local HC = ns.HammerCore
local Profiles = HC.Profiles

-- Switches profiles when the group or instance changes, by player-defined
-- rules.  Off by default.  Every behaviour here is a setting in
-- db.hcProfiles.auto; the session-crossing bits of state (a declined prompt,
-- a manual pick that should hold) live in db.hcProfiles.autoState.
--
-- A rule = { profile, group, min, max, instance, source }:
--   group     ANY | SOLO | PARTY | RAID
--   instance  ANY | NONE (open world) | PARTY | RAID | PVP | ARENA | SCENARIO
--   source    INSTANCE uses the instance's maximum size inside one, else the
--             group size; GROUP always uses the group size
-- The first rule that matches wins.  profile "" means "No change".

local Auto = { MAX_RULES = 8, DEBOUNCE = 1 }
Profiles.Auto = Auto

Auto.MODES = { "OFF", "AUTO", "ASK" }
Auto.GROUPS = { "ANY", "SOLO", "PARTY", "RAID" }
Auto.INSTANCES = { "ANY", "NONE", "PARTY", "RAID", "PVP", "ARENA", "SCENARIO" }
Auto.SOURCES = { "INSTANCE", "GROUP" }

local DEFAULTS = {
    mode = "OFF",
    onGroup = true, onInstance = true, onSize = true,
    afterNo = "STAY",     -- STAY until the matching rule changes | ASK again
    combatAsk = "NOW",    -- NOW ask, switch after combat | AFTER ask after combat
    manual = "RULE",      -- a manual pick holds until RULE changes | INSTANCE changes | TOGGLE
    message = true,
}
Auto.DEFAULTS = DEFAULTS

local function oneOf(list, value)
    for _, item in ipairs(list) do if item == value then return true end end
    return false
end

local function wholeNumber(value, low, high, fallback)
    value = tonumber(value)
    if not value or value ~= value then value = fallback end
    return math.max(low, math.min(high, math.floor(value + 0.5)))
end

function Auto.NewRule(profile)
    return { profile = profile or "", group = {}, min = 1, max = 40, instance = {}, source = "INSTANCE" }
end

-- A rule's group and instance are each a set of choices, such as
-- { PARTY = true, RAID = true }.  An empty set matches anything.  Older
-- saved rules held one string ("ANY", "RAID"); they read as that set.
local function cleanSet(value, list)
    local set, count, choices = {}, 0, 0
    if type(value) == "string" then value = { [value] = true } end
    for _, item in ipairs(list) do
        if item ~= "ANY" then
            choices = choices + 1
            if type(value) == "table" and value[item] == true then
                set[item], count = true, count + 1
            end
        end
    end
    -- Every choice ticked is the same as none: anything.
    if count == choices then return {} end
    return set
end
Auto.CleanSet = cleanSet

-- Whether a rule's group or instance allows `value`.  Accepts a set, the
-- older single string, or nothing.
function Auto.Allows(field, value)
    if field == nil or field == "ANY" then return true end
    if type(field) == "string" then return field == value end
    if type(field) ~= "table" or next(field) == nil then return true end
    return field[value] == true
end

local function cleanRule(rule)
    if type(rule) ~= "table" then return nil end
    local clean = {
        profile = type(rule.profile) == "string" and rule.profile or "",
        group = cleanSet(rule.group, Auto.GROUPS),
        instance = cleanSet(rule.instance, Auto.INSTANCES),
        source = oneOf(Auto.SOURCES, rule.source) and rule.source or "INSTANCE",
        min = wholeNumber(rule.min, 1, 40, 1),
        max = wholeNumber(rule.max, 1, 40, 40),
    }
    if clean.min > clean.max then clean.min, clean.max = clean.max, clean.min end
    return clean
end

function Auto:DefaultRules()
    local rules = {}
    for _, rule in ipairs(Profiles.spec and Profiles.spec.rules or {}) do
        rules[#rules + 1] = cleanRule(rule)
    end
    return rules
end

function Auto:Normalise(data)
    if type(data.auto) ~= "table" then data.auto = {} end
    local auto = data.auto
    for key, value in pairs(DEFAULTS) do
        if type(auto[key]) ~= type(value) then auto[key] = value end
    end
    if not oneOf(self.MODES, auto.mode) then auto.mode = DEFAULTS.mode end
    if auto.afterNo ~= "STAY" and auto.afterNo ~= "ASK" then auto.afterNo = DEFAULTS.afterNo end
    if auto.combatAsk ~= "NOW" and auto.combatAsk ~= "AFTER" then auto.combatAsk = DEFAULTS.combatAsk end
    if not oneOf({ "RULE", "INSTANCE", "TOGGLE" }, auto.manual) then auto.manual = DEFAULTS.manual end
    if type(auto.rules) ~= "table" then
        auto.rules = self:DefaultRules()
    else
        local rules = {}
        for _, rule in ipairs(auto.rules) do
            local clean = cleanRule(rule)
            if clean and #rules < self.MAX_RULES then
                if clean.profile ~= "" and not Profiles:Exists(clean.profile) then clean.profile = "" end
                rules[#rules + 1] = clean
            end
        end
        auto.rules = rules
    end
    if type(data.autoState) ~= "table" then data.autoState = {} end
end

local function settings()
    local data = Profiles:Data()
    return data and data.auto, data and data.autoState
end
Auto.Settings = settings

-- ── Where the player is ────────────────────────────────────────────────────

local INSTANCE_TYPES = { none = "NONE", party = "PARTY", raid = "RAID", pvp = "PVP",
    arena = "ARENA", scenario = "SCENARIO" }

function Auto.Context()
    local inInstance, kind = false, "none"
    if IsInInstance then inInstance, kind = IsInInstance() end
    local maxPlayers, instanceID = 0, 0
    if inInstance and GetInstanceInfo then
        local _, _, _, _, players, _, _, id = GetInstanceInfo()
        maxPlayers, instanceID = tonumber(players) or 0, tonumber(id) or 0
    end
    local group = (IsInRaid and IsInRaid()) and "RAID" or (IsInGroup and IsInGroup()) and "PARTY" or "SOLO"
    local size = 1
    if group ~= "SOLO" and GetNumGroupMembers then size = math.max(1, tonumber(GetNumGroupMembers()) or 1) end
    local instance = inInstance and (INSTANCE_TYPES[kind] or "NONE") or "NONE"
    return {
        group = group, size = size, instance = instance, maxPlayers = maxPlayers,
        instanceKey = inInstance and (instance .. ":" .. instanceID .. ":" .. maxPlayers) or "NONE",
    }
end

function Auto.RuleSize(rule, context)
    if rule.source == "INSTANCE" and context.maxPlayers > 0 then return context.maxPlayers end
    return context.size
end

-- The first matching rule: index, rule.
function Auto.Match(rules, context)
    for index, rule in ipairs(rules or {}) do
        if Auto.Allows(rule.group, context.group) and Auto.Allows(rule.instance, context.instance) then
            local size = Auto.RuleSize(rule, context)
            if size >= rule.min and size <= rule.max then return index, rule end
        end
    end
end

local function matchKey(index, rule)
    if not index then return "NONE" end
    return index .. ":" .. tostring(rule.profile)
end

-- The profile the rules pick right now, or nil.
function Auto:Target(context)
    local auto = settings()
    local _, rule = Auto.Match(auto and auto.rules, context or Auto.Context())
    if rule and rule.profile ~= "" and Profiles:Exists(rule.profile) then return rule.profile end
end

-- ── Deciding ───────────────────────────────────────────────────────────────

function Auto:NoteManual()
    local auto, state = settings()
    if not state then return end
    local context = Auto.Context()
    state.hold = true
    state.holdRule = matchKey(Auto.Match(auto.rules, context))
    state.holdInstance = context.instanceKey
end

local function unsafe()
    local spec = Profiles.spec
    return spec and spec.unsafe and spec.unsafe() or false
end

function Auto:Ask(target, key)
    local auto, state = settings()
    self.askAfterCombat = nil
    HC.Dialog:Confirm({
        title = HC.name,
        text = "Switch to the " .. target .. " profile?",
        accept = "Switch", cancel = "Not now",
        onAccept = function() Profiles:Switch(target, "auto") end,
        onCancel = function()
            if auto.afterNo == "STAY" then state.declined = key end
        end,
    })
end

-- force: evaluate even if no enabled trigger fired (turning auto-switch on,
-- the deferred combat prompt).
function Auto:Evaluate(force)
    local auto, state = settings()
    if not auto then return end
    local context = Auto.Context()
    local previous = self.lastContext
    self.lastContext = context
    if auto.mode == "OFF" then return end

    local fired = force
        or (auto.onGroup and (not previous or previous.group ~= context.group))
        or (auto.onSize and (not previous or previous.size ~= context.size))
        or (auto.onInstance and (not previous or previous.instanceKey ~= context.instanceKey))

    local index, rule = Auto.Match(auto.rules, context)
    local key = matchKey(index, rule)
    if state.hold then
        if (auto.manual == "RULE" and state.holdRule ~= key)
            or (auto.manual == "INSTANCE" and state.holdInstance ~= context.instanceKey) then
            state.hold, state.holdRule, state.holdInstance = nil, nil, nil
        end
    end
    if state.declined and state.declined ~= key then state.declined = nil end
    if not fired or state.hold then return end

    local target = rule and rule.profile
    if not target or target == "" or not Profiles:Exists(target) then return end
    if target == Profiles:Loaded() and not Profiles.pending then return end

    if auto.mode == "AUTO" then
        Profiles:Switch(target, "auto")
        return
    end
    if state.declined == key then return end
    if HC.Dialog:IsShown() and self.asking == key then return end
    if unsafe() and auto.combatAsk == "AFTER" then
        self.askAfterCombat = true
        return
    end
    self.asking = key
    self:Ask(target, key)
end

-- Roster events arrive in bursts while a group forms; settle first.
function Auto:Request()
    if self.timer then return end
    local function run()
        Auto.timer = nil
        Auto:Evaluate()
        -- The Profiles page shows which rule matches right now.
        Profiles.RefreshSettings()
    end
    if not (C_Timer and C_Timer.After) then return run() end
    self.timer = true
    C_Timer.After(self.DEBOUNCE, run)
end

-- Settings ------------------------------------------------------------------

function Auto:SetMode(mode)
    local auto, state = settings()
    if not oneOf(self.MODES, mode) or auto.mode == mode then return end
    local wasOff = auto.mode == "OFF"
    auto.mode = mode
    if wasOff and mode ~= "OFF" then
        -- Turning it on is a fresh start: forget holds and refusals.
        state.hold, state.holdRule, state.holdInstance, state.declined = nil, nil, nil, nil
        self:Evaluate(true)
    elseif mode == "OFF" then
        self.askAfterCombat = nil
        if HC.Dialog:IsShown() and self.asking then HC.Dialog:Dismiss() end
    end
end

function Auto:Set(key, value)
    local auto = settings()
    if DEFAULTS[key] == nil or type(value) ~= type(DEFAULTS[key]) then return end
    if key == "mode" then return self:SetMode(value) end
    auto[key] = value
end

function Auto:Rules()
    local auto = settings()
    return auto and auto.rules or {}
end

function Auto:AddRule()
    local rules = self:Rules()
    if #rules >= self.MAX_RULES then return nil end
    rules[#rules + 1] = Auto.NewRule(Profiles:Loaded())
    return #rules
end

function Auto:RemoveRule(index)
    table.remove(self:Rules(), index)
end

function Auto:MoveRule(index, delta)
    local rules = self:Rules()
    local other = index + delta
    if not (rules[index] and rules[other]) then return end
    rules[index], rules[other] = rules[other], rules[index]
end

function Auto:SetRule(index, key, value)
    local rule = self:Rules()[index]
    if not rule then return end
    if key == "min" or key == "max" then
        rule[key] = wholeNumber(value, 1, 40, rule[key])
        -- Keep min <= max by moving the other bound, never by swapping.
        if rule.min > rule.max then
            if key == "min" then rule.max = rule.min else rule.min = rule.max end
        end
        return
    end
    if key == "group" or key == "instance" then
        -- value is one choice to tick or untick; "ANY" clears the set.
        local set = cleanSet(rule[key], key == "group" and Auto.GROUPS or Auto.INSTANCES)
        if value == "ANY" then
            set = {}
        else
            set[value] = not set[value] or nil
        end
        value = set
    end
    rule[key] = value
    local clean = cleanRule(rule)
    rule.profile, rule.group, rule.instance, rule.source = clean.profile, clean.group, clean.instance, clean.source
end

function Auto:ResetRules()
    local auto = settings()
    auto.rules = self:DefaultRules()
end

function Auto:ResetSettings()
    local auto, state = settings()
    for key, value in pairs(DEFAULTS) do auto[key] = value end
    auto.rules = self:DefaultRules()
    for key in pairs(state) do state[key] = nil end
    if HC.Dialog:IsShown() and self.asking then HC.Dialog:Dismiss() end
end

-- Events --------------------------------------------------------------------

function Auto:Setup()
    if self.frame then return end
    local frame = CreateFrame("Frame")
    self.frame = frame
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE",
        "PLAYER_REGEN_ENABLED", "ENCOUNTER_END", "PLAYER_LOGOUT" }) do
        if frame.RegisterEvent then pcall(frame.RegisterEvent, frame, event) end
    end
    frame:SetScript("OnEvent", function(_, event) Auto:OnEvent(event) end)
end

function Auto:OnEvent(event)
    if not (Profiles.enabled and Profiles:Data()) then return end
    if event == "PLAYER_LOGOUT" then
        Profiles:Capture()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "ENCOUNTER_END" then
        local function settle()
            Profiles:FlushPending()
            if Auto.askAfterCombat and not unsafe() then Auto:Evaluate(true) end
        end
        -- IsEncounterInProgress can stay true until ENCOUNTER_END finishes.
        if event == "ENCOUNTER_END" and C_Timer and C_Timer.After then C_Timer.After(0, settle) else settle() end
    else
        self:Request()
    end
end
