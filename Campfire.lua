local _, ns = ...
local HC = ns.HammerCore
local Campfire = {}
ns.Campfire = Campfire

-- Forever's seated campfire aura. The feature uses Loreforge's own quiz bank.
Campfire.SPELL_ID = 1229739
local DEPARTURE_DELAY = 1

function Campfire.Supported()
    if not GetBuildInfo then return false end
    local interface = select(4, GetBuildInfo())
    return type(interface) == "number" and interface >= 16000 and interface < 17000
end

local function secret(value) return issecretvalue and issecretvalue(value) end
local function seated()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, hidden = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or secret(hidden) or hidden then return nil end
    end
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, Campfire.SPELL_ID)
    if not ok or secret(aura) then return nil end
    if aura == nil then return false end
    if type(aura) ~= "table" then return nil end
    return true
end

-- Only close the exact session this feature opened. Manual replacement and
-- other quiz modes retain their existing dismissal/combat behaviour.
function Campfire.CloseOwned()
    Campfire.pendingDeparture = nil
    Campfire.offered = nil
    ns.QuickCard.HidePrompt(true, "campfire")
    ns.QuickCard.HideLauncher("campfire")
    local owned = Campfire.owned
    Campfire.owned = nil
    if owned and ns.Quick.state == owned then ns.QuickCard.CloseSession(owned)
    elseif ns.Quick.state and ns.Quick.state.mode == "camping" and not ns.Quick.state.landed then ns.Quick.EndCamping() end
end

local function busy()
    local card = ns.QuickCard
    if ns.Quick.state or (card and (card.IsShown() or card.combatHidden
        or card.prompt and card.prompt:IsShown() or card.dailyPrompt and card.dailyPrompt:IsShown())) then return true end
    if ns.game and ns.game.Active and ns.game:Active() then return true end
    local party = ns.Party
    if party and (party.host or party.client and party.client.joined
        and party.client.model and party.client.model.state ~= "finished" and party.client.model.state ~= "stopped") then return true end
    if HC.Welcome and HC.Welcome.Busy and HC.Welcome.Busy() then return true end
    local news = HC.WhatsNew
    if news then
        if news.frame and news.frame:IsShown() then return true end
        local state = HC.State()
        if state and state.whatsNew ~= false and news.Enabled() and #news:Unseen(state.whatsNewSeen,
            news.Base(HC.VERSION_TEXT), state.whatsNewSeenItems) > 0 then return true end
    end
    return false
end

-- Only this visit's offer or its exact owned quiz can use the campfire UI.
function Campfire.CanLaunch()
    return ns.db and ns.db.qpCampfire and Campfire.Supported() and Campfire.atCamp
        and ((Campfire.offered and not ns.Quick.state)
            or (Campfire.owned ~= nil and ns.Quick.state == Campfire.owned))
        and not ns.Quick.Flying() and not (InCombatLockdown and InCombatLockdown())
        and seated() == true and not ns.QuickCard.IsShown() and not ns.QuickCard.combatHidden
end

function Campfire.Here()
    return ns.db and ns.db.qpCampfire and Campfire.Supported() and seated() == true
end

function Campfire.OpenQuiz(mode, options)
    if not Campfire.CanLaunch() then return false end
    mode = mode == "quick" and "quick" or "camping"
    Campfire.offered = nil
    options = options or {}
    options.campfireConfirmed = true
    ns.QuickCard.Show(mode, options)
    if ns.QuickCard.IsShown() then Campfire.owned = ns.Quick.state; return true end
    return false
end

function Campfire.Leave()
    local state = ns.Quick.state
    if not Campfire.owned and not Campfire.offered and not (state and state.mode == "camping" and not state.landed) then return end
    local owned = Campfire.owned
    Campfire.owned, Campfire.offered = nil, nil
    ns.QuickCard.HidePrompt(true, "campfire")
    ns.QuickCard.HideLauncher("campfire")
    local state = ns.Quick.state
    if (owned and state == owned) or (state and state.mode == "camping" and not state.landed) then ns.Quick.EndCamping() end
end

local function waitForAuraRefresh()
    if Campfire.pendingDeparture then return true end
    if not (C_Timer and C_Timer.After) then return false end
    local departure = {}
    Campfire.pendingDeparture = departure
    C_Timer.After(DEPARTURE_DELAY, function()
        if Campfire.pendingDeparture ~= departure then return end
        Campfire.pendingDeparture = nil
        Campfire.Refresh(true)
    end)
    return true
end

function Campfire.Refresh(confirmingDeparture)
    if not (ns.db and ns.db.qpCampfire and Campfire.Supported()) then
        Campfire.CloseOwned(); Campfire.atCamp = nil
        return
    end
    local here = seated()
    if here == nil then return end -- unknown/secret aura state cannot open or close a quiz
    if here or confirmingDeparture then
        Campfire.pendingDeparture = nil
    elseif Campfire.atCamp and not confirmingDeparture and waitForAuraRefresh() then
        -- Sleeping bag stacks can replace the seated aura during the same visit.
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        if here == false then Campfire.atCamp = false; Campfire.Leave() end
        return
    end
    if not here then
        Campfire.atCamp = false
        Campfire.Leave()
        return
    end
    if Campfire.atCamp then
        if Campfire.CanLaunch() then ns.QuickCard.ShowLauncher("campfire")
        else ns.QuickCard.HideLauncher("campfire") end
        return
    end
    Campfire.atCamp = true -- closing manually stays closed until the next visit
    if busy() or ns.Quick.Flying() then return end
    Campfire.offered = true
    if ns.db.qpCampfireStart then
        if not Campfire.OpenQuiz("camping", { countdown = true }) then Campfire.offered, Campfire.atCamp = nil, nil end
        return
    end
    if not ns.QuickCard.Prompt("campfire") then
        Campfire.offered, Campfire.atCamp = nil, nil -- retry only when aura data becomes known
    end
end

function Campfire.BeforeTakeoff()
    local state, card = ns.Quick.state, ns.QuickCard
    if state and state == Campfire.owned and state.mode ~= "camping" and (card.IsShown() or card.combatHidden) then
        Campfire.owned = nil
    end
    local here = seated()
    Campfire.CloseOwned()
    -- A stale seated aura must clear before offering again after a flight.
    Campfire.atCamp = here == true or (here == nil and Campfire.atCamp) or nil
end

function Campfire.Apply()
    if Campfire.events then Campfire.events:UnregisterAllEvents() end
    if not (ns.db and ns.db.qpCampfire and Campfire.Supported()) then
        Campfire.CloseOwned(); Campfire.atCamp = nil
        return
    end
    if not Campfire.events then
        Campfire.events = CreateFrame("Frame")
        Campfire.events:SetScript("OnEvent", function(_, event, unit)
            if event == "PLAYER_REGEN_DISABLED" then
                ns.QuickCard.HideLauncher("campfire")
                return
            end
            if event == "UNIT_AURA" and unit ~= "player" then return end
            Campfire.Refresh(event == "PLAYER_ENTERING_WORLD")
        end)
    end
    Campfire.events:RegisterUnitEvent("UNIT_AURA", "player")
    Campfire.events:RegisterEvent("PLAYER_ENTERING_WORLD")
    Campfire.events:RegisterEvent("PLAYER_REGEN_DISABLED")
    Campfire.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    Campfire.Refresh()
end
Campfire.Initialise = Campfire.Apply
