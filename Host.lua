local _, ns = ...
local HC = ns.HammerCore
local UI, T = HC.UI, HC.Theme
local CHAT_CHANNELS = {
    CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT", CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
    CHAT_MSG_GUILD = "GUILD",
}
local function readable(v) return not (issecretvalue and issecretvalue(v)) end
local function realm()
    local value = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName and GetRealmName() or ""
    return tostring(value):gsub("%s", "")
end
function ns.Identity(name, server)
    if not readable(name) or type(name) ~= "string" or name == "" then return nil end
    local character, world = name, readable(server) and type(server) == "string" and server or nil
    if not world or world == "" then
        local first, suffix = name:match("^(.*)%-([^%-]+)$")
        -- Forever names can contain surname spaces/hyphens. Only strip our
        -- known realm suffix there; Retail sends explicit cross-realm names.
        if first and (ns.era ~= "classic" or suffix:gsub("%s", ""):lower() == realm():lower()) then
            character, world = first, suffix
        end
    end
    world = (world and world ~= "" and world or realm()):gsub("%s", "")
    local full = character .. "-" .. world
    return full:lower(), full
end
local function person(unit)
    local name, server
    if ns.era == "classic" then
        -- Forever's tuple APIs return first name and surname, not realm.
        name = GetUnitName and GetUnitName(unit, true)
        if not readable(name) then return nil end
        if not name then
            local first, last
            if UnitFullName then first, last = UnitFullName(unit) else first, last = UnitName(unit) end
            if readable(first) and type(first) == "string" then
                name = first .. (readable(last) and type(last) == "string" and last ~= "" and (" " .. last) or "")
            end
        end
        server = realm()
    elseif UnitFullName then name, server = UnitFullName(unit)
    else name, server = UnitName(unit) end
    local key, full = ns.Identity(name, server)
    local guid = UnitGUID and UnitGUID(unit)
    if not readable(guid) then guid = nil end
    if key then return { key = key, name = full, guid = guid } end
end
ns.Person = person
function ns.Restricted()
    if HC.Quiz.ChatRestricted() then return true end
    local lockdown = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if type(lockdown) == "function" then
        local ok, blocked = pcall(lockdown)
        return not ok or not readable(blocked) or blocked == true
    end
    return false
end
local HOME, INSTANCE = LE_PARTY_CATEGORY_HOME or 1, LE_PARTY_CATEGORY_INSTANCE or 2
function ns.Roster(channel, includeHost)
    local rows, host = {}, person("player")
    if includeHost and host then
        rows[1] = host
        local grouped = IsInGroup and (IsInGroup(HOME) or IsInGroup(INSTANCE))
        if not grouped and (channel ~= "GUILD" or not IsInGuild or not IsInGuild()) then
            return rows, nil, true -- no channel exists: local testing, never broadcast
        end
    end
    if channel == "GUILD" then
        if not IsInGuild or not IsInGuild() then return rows, "Join a guild before hosting in guild chat." end
        for i = 1, math.min(GetNumGuildMembers and GetNumGuildMembers() or 0, 1000) do
            local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            local key, full = ns.Identity(name)
            if readable(online) and online and key and (not host or key ~= host.key) then rows[#rows + 1] = { key = key, name = full } end
        end
        if #rows == 0 then return rows, "No online guild players are cached. Refresh the guild roster first." end
    else
        local instance = IsInGroup and IsInGroup(INSTANCE)
        if channel == "INSTANCE_CHAT" and not instance then return rows, "Join an instance group before using Instance output." end
        -- Unit tokens describe the active instance group in a dual-group setup.
        -- Never enrol that roster and then send to the separate home group.
        if channel ~= "INSTANCE_CHAT" and instance then return rows, "Use Instance output while an instance group is active." end
        local category = channel == "INSTANCE_CHAT" and INSTANCE or HOME
        local raid = IsInRaid and IsInRaid(category)
        if channel == "RAID" and not raid then return rows, "Form a raid before using Raid output." end
        if channel == "PARTY" and raid then return rows, "Choose Raid output for a raid group." end
        local count = raid and (GetNumGroupMembers and GetNumGroupMembers(category) or 0)
            or (GetNumSubgroupMembers and GetNumSubgroupMembers(category) or 0)
        for i = 1, math.min(count, raid and 40 or 4) do
            local p = person((raid and "raid" or "party") .. i)
            if p and (not host or p.key ~= host.key) then rows[#rows + 1] = p end
        end
        if #rows == 0 then return rows, "No other players are available in the selected group." end
    end
    return rows
end
local function groupSignature(channel)
    local keys = {}
    local roster, err = ns.Roster(channel)
    if err then return err end
    for _, p in ipairs(roster) do keys[#keys + 1] = p.key end
    table.sort(keys)
    return table.concat(keys, "|")
end
local function stamp() return GetServerTime and GetServerTime() or time and time() or 0 end
ns.Stamp = stamp

-- A game in progress is mirrored to saved variables at each reveal, so a
-- reload or disconnect can say where it stopped. Practice games aren't kept.
local function trackActive()
    local g = ns.game
    if not g:Active() or not g.config or g.config.localOnly then ns.db.activeGame = nil; return end
    local rows = {}
    for i, p in ipairs(g:Standings(false)) do
        if i > 5 then break end
        rows[i] = { name = p.name, total = p.total }
    end
    local done = (g.phase == "revealing" or g.phase == "between") and g.index or g.index - 1
    ns.db.activeGame = { era = ns.era, serial = g.serial, channel = g.config.channel, done = math.max(0, done or 0),
        total = #g.run, rows = rows, date = stamp() }
end

-- Every finished game is kept in History, newest first, including chat-only
-- and practice games. Party games also land in the shared match history;
-- partyId lets History show them once.
local MAX_GAMES = 50
local function recordGame()
    local g, list = ns.game, ns.db.games[ns.era]
    local rows, standings = {}, g:Standings(false)
    local host = person("player")
    for i, p in ipairs(standings) do
        if i > 10 then break end
        rows[i] = { key = p.key, name = p.name, total = p.total, bestStreak = p.bestStreak, answered = p.answered }
    end
    local party = ns.Party and ns.Party.host
    table.insert(list, 1, { serial = g.serial, date = stamp(), channel = g.config.channel, practice = g.config.localOnly or nil,
        rounds = g.config.rounds, perRound = g.config.perRound, players = #standings, rows = rows,
        host = host and host.name or nil, partyId = party and party.started and party.serial == g.serial and party.id or nil })
    while #list > MAX_GAMES do table.remove(list) end
end

function ns.HostEvent(event)
    if event == "reveal" then trackActive()
    elseif event == "recorded" then ns.db.activeGame = nil; recordGame()
    elseif event == "stopped" then ns.db.activeGame = nil end
end

function ns.DismissInterrupted()
    ns.interrupted, ns.db.activeGame = nil, nil
    ns.RefreshHost()
end

-- Posts where an interrupted game got to, once, to the channel it used.
function ns.PostInterrupted()
    local a = ns.interrupted
    if not a then return end
    if ns.Restricted() then HC.Print("Wait until combat and chat restrictions have ended."); return end
    local _, err = ns.Roster(a.channel)
    if err then HC.Print(err); return end
    local parts = {}
    for _, row in ipairs(type(a.rows) == "table" and a.rows or {}) do parts[#parts + 1] = tostring(row.name) .. " " .. tostring(row.total) end
    local text = "Game interrupted after question " .. tostring(a.done) .. " of " .. tostring(a.total) .. "."
        .. (#parts > 0 and (" Standings: " .. table.concat(parts, "; ") .. ".") or "")
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if type(send) == "function" then
        for _, line in ipairs(ns.Game.Messages(text, "[Loreforge #" .. tostring(a.serial) .. "] ")) do pcall(send, line, a.channel) end
    end
    ns.DismissInterrupted()
end

-- practice: a local game for the host alone, whatever the group.
function ns.StartGame(practice)
    local function failed(message)
        ns.setupError = message
        HC.Print(message)
        ns.RefreshHost()
    end
    if ns.Restricted() then failed("Wait until combat and chat restrictions have ended."); return end
    local roster, err, localOnly
    if practice then
        local host = person("player")
        if not host then failed("Your character isn't available yet. Try again in a moment."); return end
        roster, localOnly = { host }, true
    else roster, err, localOnly = ns.Roster(ns.db.channel, ns.db.hostParticipates) end
    if err then failed(err); return end
    local serial = math.floor(math.max(0, math.min(tonumber(ns.db.gameSerial) or 0, 1000000000))) + 1
    local ok
    local config = {}
    for key, value in pairs(ns.db) do config[key] = value end
    config.localOnly = localOnly == true
    if practice then config.hostParticipates = true end
    ok, err = ns.game:Start(config, ns.era, roster, serial)
    if not ok then failed(err); return end
    ns.setupError, ns.readyNotice, ns.lastUnmatched = nil, nil, nil
    ns.db.gameSerial, ns.scorePage = serial, 1
    ns.groupSignature = ns.db.channel ~= "GUILD" and groupSignature(ns.db.channel) or nil
    ns.nextSendAt = GetTime() + 1
    ns.interrupted = nil
    trackActive()
    if ns.Party then ns.Party.HostStarted() end
    ns.OpenHost("play")
end

function ns.SuggestChannel()
    if IsInGroup and IsInGroup(INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid(HOME) then return "RAID" end
    return "PARTY"
end

function ns.RefreshReadyPlayers()
    local roster, err = ns.Roster(ns.game.config.channel, ns.game.config.hostParticipates)
    if err then ns.game:Pause(err); HC.Print(err); ns.RefreshHost(); return end
    local added = ns.game:AddReadyPlayers(roster)
    if added then
        ns.readyNotice = added == 1 and "1 player added. They should type ready again."
            or (added .. " players added. They should type ready again.")
        ns.lastUnmatched = nil
        HC.Print(ns.readyNotice)
    end
    ns.RefreshHost()
end

function ns.RequestStop()
    if not ns.game:Active() then ns.game:Stop(); ns.RefreshHost(); return end
    StaticPopupDialogs.LOREFORGE_STOP_GAME = {
        text = "Stop this game? Scores so far won't be saved.", button1 = "Stop game", button2 = "Keep playing",
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnAccept = function()
            ns.game:Stop(); ns.RefreshHost()
        end,
    }
    StaticPopup_Show("LOREFORGE_STOP_GAME")
end

function ns.SubmitHostAnswer(text)
    if ns.Restricted() or not ns.game.config or not ns.game.config.hostParticipates then return false end
    local host = person("player")
    local accepted = host and ns.game:Answer(host.key, text, host.guid)
    if not accepted and ns.game.phase ~= "ready" and ns.game.phase ~= "ready_announcing" then
        local player = host and ns.game:FindPlayer(host.key, host.guid)
        if player and ns.game.answers[player.key] then HC.Print("Your first answer is already locked for this question.")
        elseif ns.game.phase ~= "accepting" then HC.Print("The answer window has closed. Wait for the next question.")
        else HC.Print("You're not on the player list. Turn on Host plays along before starting.") end
    end
    ns.RefreshHost()
    return accepted
end

function ns.SendLocalLine()
    local g = ns.game
    local line = g:NextMessage()
    if not line or not g.config.localOnly or ns.Restricted() then return end
    g:Sent()
    HC.Print("[Local test] " .. line)
    g:Echo(line)
end

function ns.AutomaticFailed(reason, preservePending)
    local g = ns.game
    if not g:Active() or g.config.manualSend then return end
    g.config.autoMode, g.config.manualSend = false, true
    g:Pause(reason .. (preservePending and " Check chat: did the last line post?"
        or " Resume to post each line yourself."), preservePending)
    HC.Print(g.reason)
end

-- One line in flight. The question and four options form a short burst;
-- other announcements keep a two-second gap. No automatic retries.
-- Exact chat echoes still control timers, advancement and saved records.
function ns.PumpAutomatic()
    local g, now = ns.game, GetTime()
    if not g:Active() or g.config.manualSend or g.phase == "paused" or ns.Restricted() then return end
    if g.pending then
        if now - g.pending.sentAt >= 8 then ns.AutomaticFailed("Loreforge couldn't confirm its last chat line.", true) end
        return
    end
    local line = g:NextMessage()
    if not line or now < (ns.nextSendAt or 0) then return end
    local interval = g.phase == "announcing" and g.questionCursor and g.cursor >= g.questionCursor and 0.35 or 2
    if g.config.localOnly then
        ns.nextSendAt = now + interval
        ns.SendLocalLine()
        return
    end
    -- The realm-level outgoing-addon flag can remain true even while chat
    -- sends work on Forever. Actual lockdown is checked by ns.Restricted().
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if type(send) ~= "function" then ns.AutomaticFailed("Automatic posting is unavailable."); return end
    g:Sent() -- arm before calling the API, including synchronous test echoes
    ns.nextSendAt = now + interval
    local ok, result = pcall(send, line, g.config.channel)
    if not ok or result == false then ns.AutomaticFailed("The game client blocked automatic posting.") end
end
-- Hall of Fame order: wins, then correct answers, then name.
function ns.RecordOrder(a, b)
    local ar, br = a.record, b.record
    local aw, bw = tonumber(ar.wins) or 0, tonumber(br.wins) or 0
    if aw ~= bw then return aw > bw end
    local ac, bc = tonumber(ar.correct) or 0, tonumber(br.correct) or 0
    if ac ~= bc then return ac > bc end
    return a.key < b.key
end
function ns.ShowRecords()
    local rows, lines = {}, { "Loreforge player records (" .. (ns.era == "classic" and "WoW Forever" or "Retail") .. ")" }
    for key, r in pairs(ns.db.records[ns.era]) do
        if type(r) == "table" then rows[#rows + 1] = { key = key, record = r } end
    end
    table.sort(rows, ns.RecordOrder)
    for _, p in ipairs(rows) do
        local r = p.record
        lines[#lines + 1] = tostring(r.name or p.key) .. ": " .. tostring(r.games or 0) .. " games, " .. tostring(r.wins or 0)
            .. " wins, " .. tostring(r.correct or 0) .. " correct / " .. tostring(r.answered or 0)
            .. " answered, best streak " .. tostring(r.bestStreak or 0)
    end
    if #rows == 0 then lines[#lines + 1] = "Finish a game to start recording results." end
    HC.Copy:Show("Loreforge player records", table.concat(lines, "\n"))
end

-- ── Main window ────────────────────────────────────────────────────────────
-- One window with three tabs: Play (setup, lobby and the live game), History
-- and Hall of Fame. Settings stay in the shared HammerCore window.

local W, H = 780, 620
local LEFT_W, RIGHT_X, RIGHT_W = 470, 508, 254
local BOARD_ROWS = 10
local AMBER = { 1, 0.69, 0.2, 1 }
ns.HostLayout = { width = W, height = H, leftWidth = LEFT_W, rightX = RIGHT_X, rightWidth = RIGHT_W }
local TABS = { { "play", "Play" }, { "history", "History" }, { "records", "Hall of Fame" } }
local PHASES = { ready_announcing = "Posting the ready check", ready = "Ready check", announcing = "Posting the question",
    presenting = "Sending the question to addon players", opening = "Opening answers", accepting = "Answers open",
    revealing = "Posting results", between = "Between questions", paused = "Paused", finished = "Game complete",
    stopped = "Game stopped" }

local function label(parent, font, role, width)
    local fs = UI.FontString(parent, font or "GameFontHighlight", role or "text")
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    return fs
end

local function button(parent, text, width, height, run, variant)
    local b = UI.Button(parent, width, height or 28, variant)
    b:SetText(text); b:SetScript("OnClick", run)
    return b
end

-- Timer colour: calm, then amber under 30%, then red for the last five seconds.
function ns.TimerColour(texture, left, total)
    if left <= 5 then T.Fill(texture, "danger")
    elseif total and total > 0 and left / total <= 0.3 then texture:SetColorTexture(unpack(AMBER))
    else T.Fill(texture, "selected") end
end

local function timerBar(parent, width)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, 8)
    T.Fill(bar:CreateTexture(nil, "BACKGROUND"), "rail"):SetAllPoints()
    bar.fill = T.Fill(bar:CreateTexture(nil, "ARTWORK"), "selected")
    bar.fill:SetPoint("TOPLEFT"); bar.fill:SetPoint("BOTTOMLEFT")
    bar.count = label(parent, "GameFontNormalLarge", "text", 50)
    bar.count:SetJustifyH("RIGHT")
    bar.count:SetPoint("LEFT", bar, "RIGHT", 6, 0)
    bar.SetTime = function(self, left, total)
        local fraction = total and total > 0 and math.max(0, math.min(1, left / total)) or 0
        self.fill:SetShown(fraction > 0)
        self.fill:SetWidth(math.max(1, width * fraction))
        ns.TimerColour(self.fill, left, total)
        self.count:SetText(math.ceil(left) .. "s")
        T.Text(self.count, left <= 5 and "danger" or "text")
    end
    return bar
end
ns.TimerBar = timerBar

-- A numbered answer row with a reveal tint behind the text.
local function answerRow(parent, index, width)
    local b = UI.Button(parent, width, 38)
    b:RegisterForClicks("LeftButtonUp")
    b.tint = b:CreateTexture(nil, "BORDER")
    b.tint:SetPoint("TOPLEFT", 1, -1); b.tint:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tint:Hide()
    b.num = label(b, "GameFontNormalLarge", "flavour", 24)
    b.num:SetPoint("TOPLEFT", 10, -10); b.num:SetText(tostring(index))
    b.Text:ClearAllPoints()
    b.Text:SetPoint("TOPLEFT", 38, -11)
    b.Text:SetWidth(width - 38 - 110)
    b.Text:SetJustifyH("LEFT")
    if b.Text.SetWordWrap then b.Text:SetWordWrap(true) end
    b.badge = label(b, "GameFontHighlightSmall", "muted", 100)
    b.badge:SetPoint("RIGHT", -10, 0); b.badge:SetJustifyH("RIGHT")
    -- result: "correct", "wrong", "chosen" or nil
    b.Mark = function(self, result, badge)
        self.badge:SetText(badge or "")
        if result == "correct" then
            T.Fill(self.tint, "accent"); self.tint:SetAlpha(0.28); self.tint:Show(); T.Border(self, "accent")
        elseif result == "wrong" then
            T.Fill(self.tint, "danger"); self.tint:SetAlpha(0.28); self.tint:Show(); T.Border(self, "danger")
        elseif result == "chosen" then
            T.Fill(self.tint, "selected"); self.tint:SetAlpha(0.18); self.tint:Show(); T.Border(self, "selected")
        else self.tint:Hide(); T.Border(self, "edge") end
    end
    b.Fit = function(self)
        local height = self.Text.GetStringHeight and self.Text:GetStringHeight() or 14
        self:SetHeight(math.max(38, math.ceil(height) + 22))
    end
    return b
end
ns.AnswerRow = answerRow

local function boardRow(parent, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 22)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(6, 6); row.dot:SetPoint("LEFT", 0, 0)
    row.rank = label(row, "GameFontHighlightSmall", "muted", 22)
    row.rank:SetPoint("LEFT", 10, 0)
    row.name = label(row, "GameFontHighlight", "text", width - 130)
    row.name:SetPoint("LEFT", 34, 0)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.score = label(row, "GameFontHighlightSmall", "muted", 96)
    row.score:SetPoint("RIGHT", 0, 0); row.score:SetJustifyH("RIGHT")
    return row
end

-- A plain scrolling region with a thin bar, shared by the setup, History and
-- Hall of Fame views. Returns the scroll frame, its content frame and a
-- function that sets the content height.
function ns.ScrollArea(parent, x, y, width, height)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", x, y); scroll:SetSize(width, height)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width, 1); scroll:SetScrollChild(child)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0); bar:SetSize(6, height); bar:SetOrientation("VERTICAL")
    T.Fill(bar:CreateTexture(nil, "BACKGROUND"), "rail"):SetAllPoints()
    local thumb = T.Fill(bar:CreateTexture(nil, "ARTWORK"), "selected")
    thumb:SetSize(6, 28)
    if bar.SetThumbTexture then bar:SetThumbTexture(thumb) end
    local range = 0
    bar:SetScript("OnValueChanged", function(_, value)
        if not InCombatLockdown() then scroll:SetVerticalScroll(value) end
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        if InCombatLockdown() then return end
        bar:SetValue(math.max(0, math.min(range, (bar:GetValue() or 0) - delta * 40)))
    end)
    local function setHeight(content, keep)
        child:SetHeight(math.max(1, content))
        range = math.max(0, content - scroll:GetHeight())
        bar:SetMinMaxValues(0, math.max(1, range))
        bar:SetShown(range > 0)
        if not keep then bar:SetValue(0) else bar:SetValue(math.min(range, bar:GetValue() or 0)) end
    end
    scroll.bar = bar
    return scroll, child, setHeight
end

local function createHost()
    -- Secure children live in their own root, never under HammerCore settings.
    -- The state driver hides this root in combat without an insecure Hide call.
    local f = CreateFrame("Frame", "LoreforgeHostTable", UIParent, "SecureHandlerStateTemplate,BackdropTemplate")
    f:SetSize(W, H); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    f:SetScale(ns.db.hostScale or 1)
    T.Surface(f, "outer", "edge")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) if not InCombatLockdown() then self:StopMovingOrSizing() end end)
    -- Escape closes the window out of combat; the combat state driver is
    -- dropped so it doesn't bring the window back afterwards.
    f:SetScript("OnHide", function(self)
        if not InCombatLockdown() then UnregisterStateDriver(self, "visibility") end
    end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = f:GetName() end

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26); icon:SetPoint("TOPLEFT", 16, -13)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    local title = label(f, "GameFontNormalLarge", "flavour")
    title:SetPoint("TOPLEFT", 50, -18); title:SetText("Loreforge")
    f.tabs = {}
    for i, spec in ipairs(TABS) do
        local tab = button(f, spec[2], 110, 28, function() ns.OpenHost(spec[1]) end)
        tab:SetPoint("TOPLEFT", 176 + (i - 1) * 116, -12)
        f.tabs[spec[1]] = tab
    end
    local settings = button(f, "Settings", 92, 28, function()
        if InCombatLockdown() then return end
        -- One window at a time: settings has a Back to game button.
        f:Hide()
        HC.Settings:Show()
    end)
    settings:SetPoint("TOPRIGHT", -100, -12)
    local close = button(f, "Close", 76, 28, function() if not InCombatLockdown() then f:Hide() end end)
    close:SetPoint("TOPRIGHT", -16, -12)
    local rule = T.Fill(f:CreateTexture(nil, "ARTWORK"), "edge")
    rule:SetPoint("TOPLEFT", 16, -50); rule:SetSize(W - 32, 1)

    -- Shared heading area for setup and play.
    f.status = label(f, "GameFontNormalLarge", "flavour", W - 200)
    f.status:SetPoint("TOPLEFT", 18, -64)
    f.tags = label(f, "GameFontHighlightSmall", "muted", W - 36)
    f.tags:SetPoint("TOPLEFT", 18, -88)

    -- ── Live game ──
    f.play = CreateFrame("Frame", nil, f)
    f.play:SetAllPoints()
    local play = f.play
    f.progress = CreateFrame("Frame", nil, play)
    f.progress:SetSize(W - 36, 4); f.progress:SetPoint("TOPLEFT", 18, -106)
    T.Fill(f.progress:CreateTexture(nil, "BACKGROUND"), "rail"):SetAllPoints()
    f.progress.fill = T.Fill(f.progress:CreateTexture(nil, "ARTWORK"), "accent")
    f.progress.fill:SetPoint("TOPLEFT"); f.progress.fill:SetPoint("BOTTOMLEFT")
    f.instruction = label(play, "GameFontHighlightSmall", "accent", W - 36)
    f.instruction:SetPoint("TOPLEFT", 18, -118)
    if f.instruction.SetWordWrap then f.instruction:SetWordWrap(false) end

    -- One banner for anything that needs the host: a line that may not have
    -- posted, a pause reason, or an unknown player checking in.
    f.banner = CreateFrame("Frame", nil, play, "BackdropTemplate")
    f.banner:SetSize(W - 36, 46); f.banner:SetPoint("TOPLEFT", 18, -138)
    T.Surface(f.banner, "raised", "danger")
    f.banner.text = label(f.banner, "GameFontHighlightSmall", "text", W - 36 - 300)
    f.banner.text:SetPoint("LEFT", 12, 0)
    f.recover = button(f.banner, "Yes, it posted", 130, 28, function()
        if ns.Restricted() then return end
        local g = ns.game
        if g.pending and GetTime() - g.pending.sentAt >= 8 then
            -- Explicit human confirmation, never an automatic fabricated echo.
            g:ConfirmVisible(); ns.RefreshHost()
        end
    end, "primary")
    f.recover:SetPoint("RIGHT", -146, 0)
    f.retry = button(f.banner, "Post again", 126, 28, function()
        if ns.Restricted() then return end
        local g = ns.game
        if g.phase == "paused" then g:Resume() end
        g.config.manualSend = true
        g:Retry()
        ns.RefreshHost()
    end)
    f.retry:SetPoint("RIGHT", -12, 0)
    UI.AttachHint(f.retry, "Post again", "Only if the line didn't appear. It's prepared again for you to post.")

    f.question = label(play, "GameFontNormalLarge", "flavour", LEFT_W)
    if f.question.SetWordWrap then f.question:SetWordWrap(true) end
    f.timer = timerBar(play, LEFT_W - 60)
    f.answerButtons = {}
    for i = 1, 4 do
        local index = i
        local row = answerRow(play, i, LEFT_W)
        row:SetScript("OnClick", function() ns.SubmitHostAnswer(tostring(index)) end)
        f.answerButtons[i] = row
    end
    f.readyButton = button(play, "I'm ready", 200, 32, function() ns.SubmitHostAnswer("ready") end, "primary")

    f.scoreTitle = label(play, "GameFontNormal", "flavour", RIGHT_W)
    f.scoreTitle:SetPoint("TOPLEFT", RIGHT_X, -196)
    f.scores = {}
    for i = 1, BOARD_ROWS do
        f.scores[i] = boardRow(play, RIGHT_W)
        f.scores[i]:SetPoint("TOPLEFT", RIGHT_X, -222 - (i - 1) * 24)
    end
    f.page = label(play, "GameFontHighlightSmall", "muted", 120)
    f.page:SetPoint("TOPLEFT", RIGHT_X, -222 - BOARD_ROWS * 24 - 8)
    f.more = button(play, "More", 80, 22, function()
        ns.scorePage = (ns.scorePage or 1) % math.max(1, ns.scorePages or 1) + 1
        ns.RefreshHost()
    end)
    f.more:SetPoint("TOPRIGHT", play, "TOPLEFT", RIGHT_X + RIGHT_W, -222 - BOARD_ROWS * 24 - 4)
    f.rosterRefresh = button(play, "Refresh players", 150, 26, function()
        if not ns.Restricted() then ns.RefreshReadyPlayers() end
    end)
    f.rosterRefresh:SetPoint("TOPLEFT", RIGHT_X, -222 - BOARD_ROWS * 24 - 34)
    UI.AttachHint(f.rosterRefresh, "Refresh players", "Adds anyone who joined the group since the game started.")

    f.preview = label(play, "GameFontHighlightSmall", "muted", W - 36)
    f.preview:SetPoint("BOTTOMLEFT", 18, 62)
    if f.preview.SetWordWrap then f.preview:SetWordWrap(true) end

    local send = CreateFrame("Button", nil, play, "SecureActionButtonTemplate,BackdropTemplate")
    send:SetPoint("BOTTOMLEFT", 18, 18); send:SetSize(250, 34)
    T.Surface(send, "raised", "accent")
    send.Text = UI.FontString(send); send.Text:SetAllPoints(); send.Text:SetJustifyH("CENTER")
    send:RegisterForClicks("LeftButtonUp"); send:SetAttribute("useOnKeyDown", false); send:SetAttribute("type", "macro")
    send:SetScript("PostClick", function()
        if ns.preparedMessage then
            if ns.game.config.localOnly then ns.SendLocalLine() else ns.game:Sent() end
            ns.RefreshHost()
        end
    end)
    f.send = send
    f.next = button(play, "Next question", 250, 34, function()
        if ns.Restricted() then return end
        if ns.game.phase == "paused" then ns.game:Resume()
        elseif ns.game.phase == "finished" then ns.game:Stop()
        else ns.game:Next() end
        ns.RefreshHost()
    end, "primary")
    f.next:SetPoint("BOTTOMLEFT", 18, 18)

    -- Pacing is a two-way switch showing the current mode.
    local function pace(auto)
        if ns.Restricted() or not ns.game:Active() then return end
        ns.game:SetAutomatic(auto)
        ns.RefreshHost()
    end
    f.pacingHost = button(play, "Host-paced", 112, 34, function() pace(false) end)
    f.pacingHost:SetPoint("BOTTOMLEFT", 286, 18)
    UI.AttachHint(f.pacingHost, "Host-paced", "You start each question. Good for a chatty group.")
    f.pacingAuto = button(play, "Auto-advance", 112, 34, function() pace(true) end)
    f.pacingAuto:SetPoint("LEFT", f.pacingHost, "RIGHT", 4, 0)
    UI.AttachHint(f.pacingAuto, "Auto-advance", "The next question starts on its own after a short gap.")
    -- Shown instead of the pacing switch after automatic posting failed.
    f.mode = button(play, "Retry automatic posting", 228, 34, function()
        if ns.Restricted() then return end
        ns.game.config.manualSend = false
        ns.RefreshHost()
    end)
    f.mode:SetPoint("BOTTOMLEFT", 286, 18)
    f.pause = button(play, "Pause", 96, 34, function()
        if ns.Restricted() then return end
        if ns.game.phase == "paused" then ns.game:Resume()
        else ns.game:Pause("Paused by the host. The open question will be asked again.") end
        ns.RefreshHost()
    end)
    f.pause:SetPoint("BOTTOMRIGHT", -118, 18)
    f.newGame = button(play, "Stop game", 96, 34, ns.RequestStop, "danger")
    f.newGame:SetPoint("BOTTOMRIGHT", -16, 18)

    f.setup = ns.BuildSetup(f)
    f.history = ns.BuildHistory(f)
    f.records = ns.BuildRecords(f)
    ns.hostFrame = f
    f:Hide()
end

-- tab: "play", "history" or "records"; nil keeps the current tab.
function ns.OpenHost(tab)
    if InCombatLockdown() then HC.Print("Loreforge opens outside combat."); return end
    if ns.game:Active() and ns.Restricted() then ns.game:Pause("Chat is restricted. Resume when it's safe.") end
    if not ns.hostFrame then createHost() end
    ns.hostTab = tab or ns.hostTab or "play"
    RegisterStateDriver(ns.hostFrame, "visibility", "[combat] hide; show")
    ns.hostFrame:Show()
    ns.RefreshHost()
end

function ns.ApplyHostScale()
    if ns.hostFrame and not InCombatLockdown() then ns.hostFrame:SetScale(ns.db.hostScale or 1) end
end

local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

-- Every enrolled player, best first; those yet to answer still appear.
local function boardRows(g, ready)
    local rows = {}
    for _, p in pairs(g.players) do rows[#rows + 1] = p end
    table.sort(rows, function(a, b)
        if ready and (a.ready and true or false) ~= (b.ready and true or false) then return a.ready and true or false end
        if not ready and a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    local rank, previous = 0, nil
    for i, p in ipairs(rows) do
        if p.total ~= previous then rank, previous = i, p.total end
        p.boardRank = rank
    end
    return rows
end

local function perRound(g) return (g.index - 1) % g.config.perRound + 1 end

local function drawBoard(f, g, ready, host)
    local rows = boardRows(g, ready)
    local pages = math.max(1, math.ceil(#rows / BOARD_ROWS))
    ns.scorePages = pages
    if (ns.scorePage or 1) > pages then ns.scorePage = 1 end
    local offset = ((ns.scorePage or 1) - 1) * BOARD_ROWS
    local answered = count(g.answers)
    local readyCount = #g:ReadyPlayers()
    f.scoreTitle:SetText(ready and ("Ready check · " .. readyCount .. " of " .. #rows .. " ready")
        or g.phase == "accepting" and ("Players · " .. answered .. " of " .. #rows .. " answered")
        or ("Players · " .. #rows))
    local leader = rows[1] and rows[1].total or 0
    for i, row in ipairs(f.scores) do
        local p = rows[offset + i]
        row:SetShown(p ~= nil)
        if p then
            local mine = host and p.key == host.key
            local done = ready and p.ready or (not ready and g.answers[p.key] ~= nil)
            T.Fill(row.dot, done and "accent" or "rail")
            row.dot:SetShown(ready or g.phase == "accepting")
            row.rank:SetText(ready and "" or (p.boardRank .. "."))
            row.name:SetText(p.name .. (mine and " (you)" or ""))
            T.Text(row.name, mine and "selected" or (not ready and leader > 0 and p.total == leader) and "accent" or "text")
            row.score:SetText(ready and (p.ready and "Ready" or "") or ((p.total == 1 and "1 pt" or (p.total .. " pts"))
                .. (p.streak >= 2 and (" · streak " .. p.streak) or "")))
        end
    end
    f.page:SetText(pages > 1 and ("Page " .. (ns.scorePage or 1) .. " of " .. pages) or "")
    f.more:SetShown(pages > 1)
end

local function drawBanner(f, g, pending, ready)
    local stale = pending and GetTime() - pending.sentAt >= 8
    local text, role
    if stale then
        text, role = "Did this line appear in chat?\n" .. pending.text, "danger"
    elseif g.phase == "paused" then
        text, role = g.reason or "Paused. Resume when everyone's ready.", "danger"
    elseif ready and ns.lastUnmatched then
        text, role = "Someone not on the player list replied. Refresh players, then ask them to type ready again.", "accent"
    elseif ready and ns.readyNotice then
        text, role = ns.readyNotice, "accent"
    end
    f.banner:SetShown(text ~= nil)
    if text then
        f.banner.text:SetText(text)
        T.Border(f.banner, role)
    end
    local restricted = ns.Restricted()
    f.recover:SetShown(stale and not restricted or false)
    f.recover:SetEnabled(stale and not restricted or false)
    f.retry:SetShown(stale and not restricted or false)
    f.retry:SetEnabled(stale and not restricted or false)
    return text ~= nil
end

local function drawQuestion(f, g, top, ready, host, hostPlayer, selected)
    local item = g.run and g.run[g.index]
    local finished = g.phase == "finished"
    local revealed = g.phase == "revealing" or g.phase == "between" or (finished and item)
    local text
    if ready then text = "Quiz starting soon. Players type ready in chat to check in."
    elseif finished then
        local standings = g:Standings(false)
        local best = standings[1] and standings[1].total or 0
        local winners = {}
        for _, p in ipairs(standings) do if p.total == best and best > 0 then winners[#winners + 1] = p.name end end
        text = #winners == 0 and "No correct answers this time." or (#winners == 1 and (winners[1] .. " wins with " .. best .. (best == 1 and " point." or " points."))
            or ("Shared win: " .. table.concat(winners, ", ") .. " with " .. best .. "."))
    else text = item and item.text or "" end
    f.question:ClearAllPoints(); f.question:SetPoint("TOPLEFT", 18, top)
    f.question:SetText(text)
    local y = top - math.ceil(f.question:GetStringHeight() or 16) - 14
    local deadline = g.deadline or g.readyDeadline
    local timed = deadline ~= nil and (g.phase == "accepting" or g.phase == "ready")
    f.timer:SetShown(timed); f.timer.count:SetShown(timed)
    if timed then
        f.timer:ClearAllPoints(); f.timer:SetPoint("TOPLEFT", 18, y - 6)
        f.timer:SetTime(math.max(0, deadline - GetTime()), g.phase == "ready" and g.config.readySeconds or g.config.seconds)
        y = y - 30
    end
    local checkingIn = g.config.hostParticipates and ready
    f.readyButton:SetShown(checkingIn)
    if checkingIn then
        f.readyButton:ClearAllPoints(); f.readyButton:SetPoint("TOPLEFT", 18, y)
        f.readyButton:SetText(hostPlayer and hostPlayer.ready and "You're ready" or "I'm ready")
        f.readyButton:SetEnabled(hostPlayer ~= nil and not hostPlayer.ready and not ns.Restricted())
        y = y - 42
    end
    local showChoices = item and not ready and not (finished and not revealed)
    local answering = g.config.hostParticipates and g.phase == "accepting"
    for i, row in ipairs(f.answerButtons) do
        row:SetShown(showChoices and true or false)
        if showChoices then
            row:SetText(item.choices[i])
            local key = answering and not selected and ns.AnswerKey and ns.AnswerKey(i)
            if revealed then
                local mark = i == item.correct and "correct" or (selected == i and "wrong") or nil
                row:Mark(mark, i == item.correct and (selected == i and "Your answer · Correct" or "Correct")
                    or selected == i and "Your answer" or nil)
                T.Text(row.Text, (i == item.correct or selected == i) and "text" or "muted")
            else
                row:Mark(selected == i and "chosen" or nil, selected == i and "Locked" or key and ("Key " .. key) or nil)
                T.Text(row.Text, (selected and selected ~= i) and "muted" or "text")
            end
            row:SetEnabled(answering and hostPlayer ~= nil and not selected and not ns.Restricted())
            row:Fit()
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 18, y)
            y = y - row:GetHeight() - 6
        end
    end
end

function ns.RefreshHost()
    local f, g = ns.hostFrame, ns.game
    if not f or not g or not f:IsShown() then return end
    if InCombatLockdown() then return end
    local tab = ns.hostTab or "play"
    for name, b in pairs(f.tabs) do
        T.Border(b, name == tab and "selected" or "edge")
        T.Text(b.Text, name == tab and "selected" or "text")
    end
    local setup = g.phase == "setup" or g.phase == "stopped"
    f.history:SetShown(tab == "history")
    f.records:SetShown(tab == "records")
    f.setup:SetShown(tab == "play" and setup)
    f.play:SetShown(tab == "play" and not setup)
    f.status:SetShown(tab == "play"); f.tags:SetShown(tab == "play")
    if tab == "history" then f.history.Refresh(); return end
    if tab == "records" then f.records.Refresh(); return end
    if setup then f.setup.Refresh(); return end

    local config = g.config
    local ready = g.phase == "ready" or g.phase == "ready_announcing"
        or (g.phase == "paused" and (g.resumePhase == "readyRestart"
            or g.resumePhase == "ready_announcing" or g.resumePhase == "ready"))
    if f.wasReady and not ready then ns.scorePage = 1 end
    f.wasReady = ready
    local host = person("player")
    local hostPlayer = host and g:FindPlayer(host.key, host.guid)
    local selected = hostPlayer and g.answers[hostPlayer.key]
    local restricted = ns.Restricted()
    local pending, message = g.pending, g:NextMessage()

    f.status:SetText(PHASES[g.phase] or g.phase)
    local tags = { config.localOnly and "Practice" or ns.Game.CHANNELS[config.channel].label,
        config.autoMode and "Auto-advance" or "Host-paced" }
    if config.manualSend then tags[#tags + 1] = "Posting manually" end
    if not ready and g.phase ~= "finished" then
        tags[#tags + 1] = "Round " .. g.round .. " of " .. config.rounds
        tags[#tags + 1] = "Question " .. perRound(g) .. " of " .. config.perRound
    end
    f.tags:SetText(table.concat(tags, "  ·  "))
    local done = g.phase == "finished" and #g.run or ((g.phase == "revealing" or g.phase == "between") and g.index or g.index - 1)
    f.progress.fill:SetWidth(math.max(1, (W - 36) * math.max(0, done) / math.max(1, #g.run)))
    f.progress.fill:SetShown(done > 0)

    local hasBanner = drawBanner(f, g, pending, ready)
    local instruction = ready and "Check-ins are optional. Start now, or wait for the countdown."
        or pending and not (GetTime() - pending.sentAt >= 8) and "Checking the last line posted to chat..."
        or config.manualSend and message and "Automatic posting is off. Post each line with the button below."
        or g.phase == "between" and (config.autoMode and "The next question starts automatically."
            or "Chat break. Ask the next question when everyone's ready.")
        or g.phase == "finished" and "Results posted and records saved."
        or g.phase == "accepting" and "Players answer 1 to 4 in chat. Results post when time runs out."
        or g.phase == "paused" and "Resume when everyone's ready."
        or "Posting to chat one line at a time."
    f.instruction:SetText(instruction)
    drawQuestion(f, g, hasBanner and -194 or -142, ready, host, hostPlayer, selected)
    drawBoard(f, g, ready, host)
    f.rosterRefresh:SetShown(ready)
    f.rosterRefresh:SetEnabled(not restricted)

    f.preview:SetText(pending and ("Checking it posted: " .. pending.text)
        or message and ((config.manualSend and "Next to post: " or "Posting: ") .. message)
        or g.nextQuestionAt and ("Next question in " .. math.max(0, math.ceil(g.nextQuestionAt - GetTime())) .. "s.")
        or g.phase == "accepting" and (selected and ("Your answer is locked: " .. selected .. ") " .. g.run[g.index].choices[selected]
            .. ". Results post when time runs out.")
            or config.hostParticipates and "Click an answer or type 1 to 4 in chat. Your first answer locks." or "")
        or "")

    -- Secure macro button: attributes only change out of combat.
    local prepared = not restricted and config.manualSend and message or nil
    if ns.preparedMessage ~= prepared then
        ns.preparedMessage = prepared
        f.send:SetAttribute("macrotext", prepared and not config.localOnly and (ns.Game.CHANNELS[config.channel].macro .. prepared) or nil)
    end
    local lineProgress = #g.queue > 1 and (" (" .. g.cursor .. " of " .. #g.queue .. ")") or ""
    local sendLabel = g.phase == "ready_announcing" and "Post ready check" or g.phase == "announcing" and "Post question"
        or g.phase == "opening" and "Open answers" or "Post results"
    f.send.Text:SetText(pending and "Checking it posted..." or (sendLabel .. lineProgress))
    f.send:SetEnabled(prepared ~= nil)
    local manualLines = g.phase ~= "paused" and config.manualSend and (message ~= nil or pending ~= nil)
    f.send:SetShown(manualLines)
    f.next:SetShown(not manualLines)
    local action, canAdvance = "Posting...", false
    if g.phase == "ready" then action, canAdvance = "Start questions now", true
    elseif g.phase == "between" then
        action = config.autoMode and ("Next question in " .. math.max(0, math.ceil((g.nextQuestionAt or GetTime()) - GetTime())) .. "s") or "Ask next question"
        canAdvance = not config.autoMode
    elseif g.phase == "paused" then action, canAdvance = "Resume game", true
    elseif g.phase == "finished" then action, canAdvance = "New game", true
    elseif g.phase == "accepting" then action = "Answers open" end
    f.next:SetText(action); f.next:SetEnabled(not restricted and canAdvance)

    local active = g:Active()
    f.mode:SetShown(active and config.manualSend or false)
    f.mode:SetEnabled(not restricted)
    for _, spec in ipairs({ { f.pacingHost, not config.autoMode }, { f.pacingAuto, config.autoMode } }) do
        local b, on = spec[1], spec[2]
        b:SetShown(active and not config.manualSend)
        b:SetEnabled(not restricted)
        T.Border(b, on and "selected" or "edge")
        T.Text(b.Text, on and "selected" or "muted")
    end
    f.newGame:SetShown(active); f.newGame:SetEnabled(true)
    f.pause:SetShown(active and g.phase ~= "paused")
    f.pause:SetEnabled(not restricted and active)
end
function ns.InitialiseHost()
    local events = CreateFrame("Frame")
    ns.events = events
    for _, event in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE",
        "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_ENTERING_WORLD", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do pcall(events.RegisterEvent, events, event) end
    events:SetScript("OnEvent", function(_, event, ...)
        local g = ns.game
        if event:find("^CHAT_MSG_") then
            local text, sender = ...
            local guid = select(12, ...)
            if not readable(text) or not readable(sender) or type(text) ~= "string" then return end
            if not readable(guid) then guid = nil end
            local channel = CHAT_CHANNELS[event]
            if not g.config or channel ~= g.config.channel or not g:Active() or ns.Restricted() then return end
            local key, host = ns.Identity(sender), person("player")
            if host and (key == host.key or (guid and host.guid and guid == host.guid)) then
                if not g:Echo(text) then g:Answer(host.key, text, guid) end
            elseif key then
                -- A real chat event already proves channel membership. The
                -- frozen enrolment and GUID checks belong to the game engine.
                if not g:Answer(key, text, guid) then
                    local lower = text:lower()
                    if (lower:find("ready", 1, true) or lower:match("^%s*rdy%s*[!.]*%s*$") or text:match("^%s*[1-4]%s*$"))
                        and not g:FindPlayer(key, guid) then
                        ns.lastUnmatched = sender .. " -> " .. tostring(key)
                        ns.RefreshHost()
                    end
                    return
                end
            end
        elseif g:Active() then
            if (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") and (...) == "Loreforge" then
                ns.AutomaticFailed("The game client blocked automatic posting.")
            elseif ns.Restricted() then g:Pause("Chat is restricted. Resume when it's safe.")
            elseif event == "PLAYER_ENTERING_WORLD" then g:Pause("Zone changed; resume when everyone is ready.")
            elseif event == "GROUP_ROSTER_UPDATE" and g.config.channel ~= "GUILD" and not g.config.localOnly then
                local signature = groupSignature(g.config.channel)
                if signature ~= ns.groupSignature then
                    ns.groupSignature = signature
                    if g.phase == "ready" or g.phase == "ready_announcing" then ns.RefreshReadyPlayers()
                    else g:Pause("The group changed. Players who started keep their scores.") end
                end
            elseif event == "PLAYER_GUILD_UPDATE" and g.config.channel == "GUILD" and not IsInGuild() then
                g:Pause("Guild chat is no longer available.")
            end
        end
        ns.RefreshHost()
    end)
    local elapsed = 0
    events:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.1 or not ns.game:Active() then return end
        elapsed = 0
        local previous = ns.game.phase
        if ns.game:Active() and ns.Restricted() then ns.game:Pause("Chat is restricted. Resume when it's safe.") end
        ns.game:Tick()
        ns.PumpAutomatic()
        local second = math.floor(GetTime())
        if previous ~= ns.game.phase or second ~= ns.lastRefreshSecond then
            ns.lastRefreshSecond = second
            ns.RefreshHost()
        end
    end)
end
