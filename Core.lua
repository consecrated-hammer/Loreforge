local addonName, ns = ...
local HC = ns.HammerCore
local function partyReport()
    if not (ns.Party and ns.Party.Report) then return "" end
    local ok, report = pcall(ns.Party.Report)
    return "\n\n" .. (ok and report or ("Party diagnostics failed: " .. tostring(report)))
end
ns.DEFAULTS = { rounds = 3, perRound = 5, seconds = 20, channel = "PARTY", difficulty = "mixed", replayRecords = true,
    autoMode = false, questionGap = 5, idleLimit = 3, readyCheck = true, readySeconds = 30, hostParticipates = true,
    compactChoices = false, sound = true, hostScale = 1, playerScale = 1 }
-- Setup ranges. The engine and Party protocol accept wider values from older
-- clients; the setup controls offer what makes a sensible game.
ns.LIMITS = { rounds = { 1, 10, 1 }, perRound = { 1, 15, 1 }, seconds = { 5, 60, 5 }, questionGap = { 3, 30, 1 },
    idleLimit = { 0, 10, 1 }, readySeconds = { 5, 60, 5 } }
HC:Init({
    name = "Loreforge", command = "loreforge", aliases = { "lf" }, savedVariable = "LoreforgeDB",
    icon = "Interface\\Icons\\INV_Misc_Book_09", db = function() return ns.db end,
    resetSettings = function()
        local records, serial = ns.db.records, ns.db.gameSerial
        LoreforgeDB = { records = records, gameSerial = serial, matches = ns.db.matches, partySerial = ns.db.partySerial,
            lastParty = ns.db.lastParty, pendingMatches = ns.db.pendingMatches, games = ns.db.games, activeGame = ns.db.activeGame }
        ReloadUI()
    end,
    clientLabel = function() return ns.era == "classic" and "WoW Forever" or "Retail" end,
    diagnostics = function() return "Client: " .. tostring(ns.era) .. "\nQuestions: " .. #HC.QUIZ
        .. "\nGame: " .. (ns.game and ns.game.phase or "not loaded")
        .. "\nPacing: " .. (ns.game and ns.game.config and ns.game.config.autoMode and "Auto-advance" or "Host-paced")
        .. "\nDelivery: " .. (ns.game and ns.game.config and ns.game.config.manualSend and "Click-to-send fallback" or "Automatic")
        .. "\nChannel: " .. (ns.game and ns.game.config and ns.game.config.channel or ns.db.channel)
        .. "\nHost status: " .. (ns.game and ns.game.reason or "Ready")
        .. "\nLast unmatched quiz sender: " .. (ns.lastUnmatched or "None")
        .. partyReport() end,
    status = function() return ns.game and ("Game: " .. ns.game.phase) or "Ready to host" end,
    about = { note = "AT THE TAVERN", action = "Open the book", tips = {
        "Have you considered reading the quest text?", "The real loot was knowing who dropped it.",
        "Someone in this party has memorised every boss line.", "The Headless Horseman has requested a rematch." } },
    railButton = { label = "Back to game", run = function() HC.Settings:Hide(); ns.OpenMain() end },
    minimap = { leftClick = function() ns.OpenMain() end, leftClickLabel = "open Loreforge",
        rightClick = function() HC.Settings:Show() end, rightClickLabel = "settings" },
})
-- Loreforge's main action is the game table; settings remain a separate command.
HC.Commands.byName[""].help = "Open Loreforge, or the Party game you joined"
HC.Commands.byName[""].run = function() ns.OpenMain() end
function ns.OpenMain(tab)
    if not tab and ns.Party and ns.Party.client and (ns.Party.client.joined or ns.Party.client.model.state == "invitation") and ns.Party.client.model.state~="finished"
        and ns.Party.client.model.state~="stopped" and ns.Player then
        ns.Party.viewHistory=false;ns.Player.Render(ns.Party.client.model);ns.Player.Show()
    else ns.OpenHost(tab) end
end

-- Short interface sounds, all optional. Kit IDs are shared by Retail and
-- Forever; a missing PlaySound or kit is ignored.
local SOUNDS = { invite = 880, question = 875, tick = 856, correct = 878, wrong = 846, win = 888, finish = 851 }
function ns.Sound(kind)
    if not ns.db or ns.db.sound == false or type(PlaySound) ~= "function" or not SOUNDS[kind] then return end
    pcall(PlaySound, SOUNDS[kind], "SFX")
end

-- Key bindings (Bindings.xml): answer the open question in whichever window
-- is in front, the joined Party game first.
BINDING_HEADER_LOREFORGE = "Loreforge"
for i = 1, 4 do _G["BINDING_NAME_LOREFORGE_ANSWER" .. i] = "Answer " .. i end
function LoreforgeAnswer(index)
    local model = ns.Player and ns.Player.model
    if model and model.joined and model.state == "accepting" then ns.Player.Choose(index); return end
    local g = ns.game
    if g and g.phase == "accepting" and g.config and g.config.hostParticipates then ns.SubmitHostAnswer(tostring(index)) end
end
function ns.AnswerKey(index)
    local key = GetBindingKey and GetBindingKey("LOREFORGE_ANSWER" .. index)
    return type(key) == "string" and key ~= "" and key or nil
end
local loginMessage = HC.LoginMessage
HC.LoginMessage = function(coloured) return (loginMessage(coloured):gsub(" for settings,", " for Host game,")) end
HC.Commands:Add({ name = "settings", section = "Core", help = "Open general addon settings", run = function() HC.Settings:Show() end })
HC.Commands:Add({ name = "host", section = "Trivia", help = "Open game setup", run = function() ns.OpenHost("play") end })
HC.Commands:Add({ name = "records", section = "Trivia", help = "Open the Hall of Fame", run = function() ns.OpenHost("records") end })
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loaded)
    if loaded ~= addonName then return end
    if type(LoreforgeDB) ~= "table" then LoreforgeDB = {} end
    ns.db = LoreforgeDB
    local newChannel = ns.db.channel == nil
    for key, value in pairs(ns.DEFAULTS) do if type(ns.db[key]) ~= type(value) then ns.db[key] = value end end
    -- Restore the separate-choice layout on upgrade from the compact default.
    if ns.db.choiceLayoutVersion ~= 1 then
        ns.db.compactChoices, ns.db.choiceLayoutVersion = false, 1
    end
    if ns.db.startCountdownVersion ~= 1 then
        if ns.db.readySeconds == 10 then ns.db.readySeconds = 30 end
        ns.db.startCountdownVersion = 1
    end
    if type(ns.db.categories) ~= "table" then ns.db.categories = {} end
    for _, category in ipairs(ns.Game.CATEGORIES) do
        if ns.db.categories[category[1]] == nil then ns.db.categories[category[1]] = true end
    end
    -- Values from older, wider ranges are clamped to the setup range rather
    -- than reset, so a 20-round host keeps the longest game on offer.
    for key, spec in pairs(ns.LIMITS) do
        local value = ns.db[key]
        if value ~= value then ns.db[key] = ns.DEFAULTS[key]
        else ns.db[key] = math.max(spec[1], math.min(spec[2], math.floor(value))) end
    end
    for _, key in ipairs({ "hostScale", "playerScale" }) do
        local value = ns.db[key]
        if value ~= value or value < 0.7 or value > 1.5 then ns.db[key] = 1 end
    end
    if type(ns.db.games) ~= "table" then ns.db.games = {} end
    if type(ns.db.activeGame) ~= "table" then ns.db.activeGame = nil end
    if not ns.Game.CHANNELS[ns.db.channel] then ns.db.channel = "PARTY" end
    if newChannel then ns.db.channel = ns.SuggestChannel() end
    if ns.db.difficulty ~= "mixed" and ns.db.difficulty ~= "easy" and ns.db.difficulty ~= "hard" then ns.db.difficulty = "mixed" end
    if type(ns.db.records) ~= "table" then ns.db.records = {} end
    ns.era = WOW_PROJECT_ID == (WOW_PROJECT_MAINLINE or 1) and "retail" or "classic"
    local interface = select(4, GetBuildInfo())
    if type(interface) == "number" and interface >= 16000 and interface < 17000 then ns.era = "classic" end
    if type(ns.db.records[ns.era]) ~= "table" then ns.db.records[ns.era] = {} end
    if type(ns.db.games[ns.era]) ~= "table" then ns.db.games[ns.era] = {} end
    -- A game still marked active at load was cut short by a reload or
    -- disconnect; setup offers to post where it got to.
    local interrupted = ns.db.activeGame
    ns.interrupted = interrupted and interrupted.era == ns.era and interrupted or nil
    ns.game = ns.Game.New(HC.QUIZ, GetTime, nil, ns.db.records[ns.era])
    ns.InitialiseHost()
    ns.Probe.Initialise()
    ns.Party.Initialise()
    ns.Player.Initialise()
    local partyEvent = ns.game.onEvent
    ns.game.onEvent = function(event)
        if partyEvent then partyEvent(event) end
        ns.HostEvent(event)
    end
    HC:Start()
    self:UnregisterEvent("ADDON_LOADED")
end)
