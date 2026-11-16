local _, ns = ...
local HC = ns.HammerCore
local Campfire = {}
ns.Campfire = Campfire

-- Forever's seated campfire aura. The feature uses Loreforge's own quiz bank.
Campfire.SPELL_ID = 1229739

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
    Campfire.offered = nil
    if ns.QuickCard.prompt and ns.QuickCard.prompt.lfContext == "campfire" then ns.QuickCard.HidePrompt(true) end
    ns.QuickCard.HideLauncher("campfire")
    local owned = Campfire.owned
    Campfire.owned = nil
    if not owned or ns.Quick.state ~= owned then return end
    ns.QuickCard.CloseSession(owned)
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

function Campfire.Mode(mode)
    mode = mode or ns.db.qpMode
    if mode ~= "quick" and mode ~= "streak" and mode ~= "lightning" then mode = "quick" end
    return mode
end

function Campfire.OpenQuiz(mode)
    if not Campfire.CanLaunch() then return end
    Campfire.offered = nil
    ns.QuickCard.Show(Campfire.Mode(mode))
    if ns.QuickCard.IsShown() then Campfire.owned = ns.Quick.state end
end

function Campfire.Refresh()
    if not (ns.db and ns.db.qpCampfire and Campfire.Supported()) then
        Campfire.CloseOwned(); Campfire.atCamp = nil
        return
    end
    local here = seated()
    if InCombatLockdown and InCombatLockdown() then
        if here == false then Campfire.atCamp = false; Campfire.CloseOwned() end
        return
    end
    if here == nil then return end -- unknown/secret aura state cannot open or close a quiz
    if not here then
        Campfire.atCamp = false
        Campfire.CloseOwned()
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
    if not ns.QuickCard.Prompt("campfire") then
        Campfire.offered, Campfire.atCamp = nil, nil -- retry only when aura data becomes known
    end
end

function Campfire.BeforeTakeoff()
    Campfire.CloseOwned()
    Campfire.atCamp = true -- require an observed absence before another visit
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
                -- Keep an already-dismissed quiz paused across combat, but never
                -- resurrect a visible automatic quiz through Card.OnCombat.
                if not (Campfire.offered and not ns.Quick.state) and not (Campfire.owned and ns.Quick.state == Campfire.owned
                    and Campfire.owned.pausedAt and not ns.QuickCard.IsShown()
                    and not ns.QuickCard.combatHidden) then
                    Campfire.CloseOwned()
                end
                return
            end
            if event == "UNIT_AURA" and unit ~= "player" then return end
            Campfire.Refresh()
        end)
    end
    Campfire.events:RegisterUnitEvent("UNIT_AURA", "player")
    Campfire.events:RegisterEvent("PLAYER_ENTERING_WORLD")
    Campfire.events:RegisterEvent("PLAYER_REGEN_DISABLED")
    Campfire.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    Campfire.Refresh()
end
Campfire.Initialise = Campfire.Apply
