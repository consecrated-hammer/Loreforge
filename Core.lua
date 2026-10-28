local addonName, ns = ...
local HC = ns.HammerCore
ns.DEFAULTS = { rounds = 3, perRound = 5, seconds = 20, channel = "PARTY", difficulty = "mixed", replayRecords = true,
    autoMode = false, questionGap = 5, idleLimit = 3, readyCheck = true, readySeconds = 10, hostParticipates = false }
HC:Init({
    name = "Loreforge", command = "loreforge", aliases = { "lf" }, savedVariable = "LoreforgeDB",
    icon = "Interface\\Icons\\INV_Misc_Book_09", db = function() return ns.db end,
    resetSettings = function()
        local records, serial = ns.db.records, ns.db.gameSerial
        LoreforgeDB = { records = records, gameSerial = serial, matches = ns.db.matches, partySerial = ns.db.partySerial, lastParty = ns.db.lastParty, pendingMatches = ns.db.pendingMatches }
        ReloadUI()
    end,
    clientLabel = function() return ns.era == "classic" and "WoW Forever" or "Retail" end,
    diagnostics = function() return "Client: " .. tostring(ns.era) .. "\nQuestions: " .. #HC.QUIZ
        .. "\nGame: " .. (ns.game and ns.game.phase or "not loaded")
        .. "\nPacing: " .. (ns.game and ns.game.config and ns.game.config.autoMode and "Auto-advance" or "Host-paced")
        .. "\nDelivery: " .. (ns.game and ns.game.config and ns.game.config.manualSend and "Click-to-send fallback" or "Automatic")
        .. "\nChannel: " .. (ns.game and ns.game.config and ns.game.config.channel or ns.db.channel)
        .. "\nHost status: " .. (ns.game and ns.game.reason or "Ready")
        .. "\nLast unmatched quiz sender: " .. (ns.lastUnmatched or "None") end,
    status = function() return ns.game and ("Game: " .. ns.game.phase) or "Ready to host" end,
    about = { note = "AT THE TAVERN", action = "Open the book", tips = {
        "Have you considered reading the quest text?", "The real loot was knowing who dropped it.",
        "Someone in this party has memorised every boss line.", "The Headless Horseman has requested a rematch." } },
    railButton = { label = "Host game", run = function() ns.OpenHost() end },
    minimap = { leftClick = function() ns.OpenMain() end, leftClickLabel = "Host or joined match",
        rightClick = function() HC.Settings:Show() end, rightClickLabel = "settings" },
})
-- Loreforge's main action is the game table; settings remain a separate command.
HC.Commands.byName[""].help = "Open Host game or joined match"
HC.Commands.byName[""].run = function() ns.OpenMain() end
function ns.OpenMain()
    if ns.Party and ns.Party.client and ns.Party.client.joined and ns.Party.client.model.state~="finished"
        and ns.Party.client.model.state~="stopped" and ns.Player then
        ns.Party.viewHistory=false;ns.Player.Render(ns.Party.client.model);ns.Player.Show()
    else ns.OpenHost() end
end
local loginMessage = HC.LoginMessage
HC.LoginMessage = function(coloured) return (loginMessage(coloured):gsub(" for settings,", " for Host game,")) end
HC.Commands:Add({ name = "settings", section = "Core", help = "Open general addon settings", run = function() HC.Settings:Show() end })
HC.Commands:Add({ name = "host", section = "Trivia", help = "Open Host game", run = function() ns.OpenHost() end })
HC.Commands:Add({ name = "records", section = "Trivia", help = "View saved player records", run = function() ns.ShowRecords() end })
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loaded)
    if loaded ~= addonName then return end
    if type(LoreforgeDB) ~= "table" then LoreforgeDB = {} end
    ns.db = LoreforgeDB
    local newChannel = ns.db.channel == nil
    for key, value in pairs(ns.DEFAULTS) do if type(ns.db[key]) ~= type(value) then ns.db[key] = value end end
    if type(ns.db.categories) ~= "table" then ns.db.categories = {} end
    for _, category in ipairs(ns.Game.CATEGORIES) do
        if ns.db.categories[category[1]] == nil then ns.db.categories[category[1]] = true end
    end
    for _, spec in ipairs({ { "rounds", 1, 20 }, { "perRound", 1, 50 }, { "seconds", 5, 120 },
        { "questionGap", 3, 30 }, { "idleLimit", 0, 10 }, { "readySeconds", 5, 60 } }) do
        local value = ns.db[spec[1]]
        if value ~= value or value < spec[2] or value > spec[3] then ns.db[spec[1]] = ns.DEFAULTS[spec[1]]
        else ns.db[spec[1]] = math.floor(value) end
    end
    if not ns.Game.CHANNELS[ns.db.channel] then ns.db.channel = "PARTY" end
    if newChannel then ns.db.channel = ns.SuggestChannel() end
    if ns.db.difficulty ~= "mixed" and ns.db.difficulty ~= "easy" and ns.db.difficulty ~= "hard" then ns.db.difficulty = "mixed" end
    if type(ns.db.records) ~= "table" then ns.db.records = {} end
    ns.era = WOW_PROJECT_ID == (WOW_PROJECT_MAINLINE or 1) and "retail" or "classic"
    local interface = select(4, GetBuildInfo())
    if type(interface) == "number" and interface >= 16000 and interface < 17000 then ns.era = "classic" end
    if type(ns.db.records[ns.era]) ~= "table" then ns.db.records[ns.era] = {} end
    ns.game = ns.Game.New(HC.QUIZ, GetTime, nil, ns.db.records[ns.era])
    ns.InitialiseHost()
    ns.Probe.Initialise()
    ns.Party.Initialise()
    ns.Player.Initialise()
    HC:Start()
    self:UnregisterEvent("ADDON_LOADED")
end)
