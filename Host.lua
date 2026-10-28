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
function ns.StartGame()
    local function failed(message)
        ns.setupError = message
        HC.Print(message)
        ns.RefreshHost()
    end
    if ns.Restricted() then failed("Wait until combat and chat restrictions have ended."); return end
    local roster, err, localOnly = ns.Roster(ns.db.channel, ns.db.hostParticipates)
    if err then failed(err); return end
    local serial = math.floor(math.max(0, math.min(tonumber(ns.db.gameSerial) or 0, 1000000000))) + 1
    local ok
    local config = {}
    for key, value in pairs(ns.db) do config[key] = value end
    config.localOnly = localOnly == true
    ok, err = ns.game:Start(config, ns.era, roster, serial)
    if not ok then failed(err); return end
    ns.setupError, ns.readyNotice, ns.lastUnmatched = nil, nil, nil
    ns.db.gameSerial, ns.scorePage = serial, 1
    ns.groupSignature = ns.db.channel ~= "GUILD" and groupSignature(ns.db.channel) or nil
    ns.nextSendAt = GetTime() + 1
    if ns.Party then ns.Party.HostStarted() end
    ns.OpenHost()
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
        ns.readyNotice = "Roster refreshed: " .. added .. " added. New players should type ready again."
        ns.lastUnmatched = nil
        HC.Print(ns.readyNotice)
    end
    ns.RefreshHost()
end

function ns.RequestStop()
    if not ns.game:Active() then ns.game:Stop(); ns.RefreshHost(); return end
    StaticPopupDialogs.LOREFORGE_STOP_GAME = {
        text = "Stop this quiz? Unfinished results will not be saved.", button1 = "Stop game", button2 = "Cancel",
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
        else HC.Print("Your character is not enrolled. Check Game Master participation and the player roster.") end
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
    g:Pause(reason .. (preservePending and " Confirm the visible line below. If it did not appear, Resume game, then Resend line and Send."
        or " Click Resume game for click-to-send controls."), preservePending)
    HC.Print(g.reason)
end

-- One line in flight. The question and four options form a short burst;
-- other announcements keep a two-second gap. No automatic retries.
-- Exact chat echoes still control timers, advancement and saved records.
function ns.PumpAutomatic()
    local g, now = ns.game, GetTime()
    if not g:Active() or g.config.manualSend or g.phase == "paused" or ns.Restricted() then return end
    if g.pending then
        if now - g.pending.sentAt >= 8 then ns.AutomaticFailed("No chat confirmation for automatic output.", true) end
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
    if type(send) ~= "function" then ns.AutomaticFailed("Automatic chat is unavailable."); return end
    g:Sent() -- arm before calling the API, including synchronous test echoes
    ns.nextSendAt = now + interval
    local ok, result = pcall(send, line, g.config.channel)
    if not ok or result == false then ns.AutomaticFailed("The client refused automatic chat.") end
end
function ns.ShowRecords()
    local rows, lines = {}, { "Loreforge player records (" .. (ns.era == "classic" and "WoW Forever" or "Retail") .. ")" }
    for key, r in pairs(ns.db.records[ns.era]) do
        if type(r) == "table" then rows[#rows + 1] = { key = key, record = r } end
    end
    table.sort(rows, function(a, b) return a.key < b.key end)
    for _, p in ipairs(rows) do
        local r = p.record
        lines[#lines + 1] = tostring(r.name or p.key) .. ": " .. tostring(r.games or 0) .. " games, " .. tostring(r.wins or 0)
            .. " wins, " .. tostring(r.correct or 0) .. " correct / " .. tostring(r.answered or 0)
            .. " answered, best streak " .. tostring(r.bestStreak or 0)
    end
    if #rows == 0 then lines[#lines + 1] = "Finish a game to start recording results." end
    HC.Copy:Show("Loreforge player records", table.concat(lines, "\n"))
end
local function createHost()
    -- Secure children live in their own root, never under HammerCore settings.
    -- The state driver hides this root in combat without an insecure Hide call.
    local f = CreateFrame("Frame", "LoreforgeHostTable", UIParent, "SecureHandlerStateTemplate,BackdropTemplate")
    f:SetSize(760, 510); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    T.Surface(f, "outer", "edge")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) if not InCombatLockdown() then self:StopMovingOrSizing() end end)
    f.play = CreateFrame("Frame", nil, f)
    f.play:SetAllPoints()
    local function label(x, y, width, font, role, parent)
        local fs = UI.FontString(parent or f.play, font or "GameFontHighlight", role or "text")
        fs:SetPoint("TOPLEFT", x, y); fs:SetWidth(width); fs:SetJustifyH("LEFT")
        return fs
    end
    local function button(text, x, y, width, run, parent)
        local b = UI.Button(parent or f.play, width, 26)
        b:SetPoint("TOPLEFT", x, y); b:SetText(text); b:SetScript("OnClick", run)
        return b
    end
    label(18, -16, 500, "GameFontNormalLarge", "accent", f):SetText("Loreforge | Host game")
    f.status = label(18, -48, 720, nil, nil, f)
    f.instruction = label(18, -68, 720, "GameFontHighlightSmall", "accent", f)
    f.instruction:SetWordWrap(false)
    f.question = label(18, -82, 430, "GameFontNormalLarge")
    f.question:SetHeight(70); f.question:SetWordWrap(true)
    f.choices, f.answerButtons, f.scores = {}, {}, {}
    for i = 1, 4 do
        f.choices[i] = label(18, -166 - (i - 1) * 46, 430)
        f.choices[i]:SetHeight(42); f.choices[i]:SetWordWrap(true)
        local index = i
        local answer = UI.Button(f.play, 430, 42)
        answer:EnableMouse(true); answer:RegisterForClicks("LeftButtonUp")
        answer:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
        if answer:GetHighlightTexture() then answer:GetHighlightTexture():SetAlpha(0.12) end
        answer:SetPoint("TOPLEFT", 18, -166 - (i - 1) * 46)
        answer.Text:SetWordWrap(true)
        answer:SetScript("OnClick", function()
            local checkingIn = ns.game.phase == "ready" or ns.game.phase == "ready_announcing"
            ns.SubmitHostAnswer(checkingIn and "ready" or tostring(index))
        end)
        answer:Hide()
        f.answerButtons[i] = answer
    end
    f.scoreTitle = label(476, -82, 266, "GameFontNormal", "accent")
    for i = 1, 10 do f.scores[i] = label(476, -110 - (i - 1) * 24, 266, "GameFontHighlightSmall") end
    button("More scores", 476, -362, 130, function()
        local ready = ns.game.phase == "ready" or ns.game.phase == "ready_announcing"
        local rows = ready and ns.game:ReadyPlayers() or ns.game:Standings(false)
        ns.scorePage = (ns.scorePage or 1) % math.max(1, math.ceil(#rows / 10)) + 1
        ns.RefreshHost()
    end)
    f.preview = label(18, -398, 720, "GameFontHighlightSmall", "muted")
    f.preview:SetHeight(45); f.preview:SetWordWrap(true)
    local send = CreateFrame("Button", nil, f.play, "SecureActionButtonTemplate,BackdropTemplate")
    send:SetPoint("BOTTOMLEFT", 18, 18); send:SetSize(244, 30)
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
    f.next = button("Next question", 18, -462, 244, function()
        if ns.Restricted() then return end
        if ns.game.phase == "paused" then ns.game:Resume()
        elseif ns.game.phase == "finished" then ns.game:Stop()
        else ns.game:Next() end
        ns.RefreshHost()
    end)
    T.Surface(f.next, "raised", "accent")
    f.mode = button("Use automatic", 280, -462, 128, function()
        if ns.Restricted() then return end
        if ns.game.config.manualSend then ns.game.config.manualSend = false
        else ns.game:SetAutomatic(not ns.game.config.autoMode) end
        ns.RefreshHost()
    end)
    f.pause = button("Pause", 420, -462, 90, function()
        if ns.Restricted() then return end
        if ns.game.phase == "paused" then ns.game:Resume()
        else ns.game:Pause("Paused by the host; an open question is voided.") end
        ns.RefreshHost()
    end)
    f.retry = button("Resend line", 524, -462, 100, function()
        if not ns.Restricted() then ns.game:Retry(); ns.RefreshHost() end
    end)
    UI.AttachHint(f.retry, "Resend line", "Only for a line that did not appear. This prepares it again; click Send to post it.")
    f.newGame = button("Stop game", 650, -462, 90, ns.RequestStop)
    f.recover = button("Refresh players", 18, -362, 244, function()
        if ns.Restricted() then return end
        local g = ns.game
        if g.pending and GetTime() - g.pending.sentAt >= 8 then
            -- Explicit human confirmation, never an automatic fabricated echo.
            g:ConfirmVisible(); ns.RefreshHost()
        end
    end)
    f.rosterRefresh = button("Refresh players", 280, -362, 180, function()
        if not ns.Restricted() then ns.RefreshReadyPlayers() end
    end)
    button("Settings", 540, -12, 98, function() HC.Settings:Show() end, f)
    button("Close", 650, -12, 90, function()
        if not InCombatLockdown() then UnregisterStateDriver(f, "visibility"); f:Hide() end
    end, f)
    f.setup = ns.BuildSetup(f)
    ns.hostFrame = f
    f:Hide()
end
function ns.OpenHost()
    if InCombatLockdown() then HC.Print("Host game is available outside combat."); return end
    if ns.game:Active() and ns.Restricted() then ns.game:Pause("Chat is restricted; resume after the restriction ends.") end
    if not ns.hostFrame then createHost() end
    RegisterStateDriver(ns.hostFrame, "visibility", "[combat] hide; show")
    ns.hostFrame:Show()
    ns.RefreshHost()
end
function ns.RefreshHost()
    local f, g = ns.hostFrame, ns.game
    if not f or not g or not f:IsShown() then return end
    if InCombatLockdown() then return end
    local setup = g.phase == "setup" or g.phase == "stopped"
    if f.showingSetup ~= setup then f:SetHeight(setup and 590 or 510); f.showingSetup = setup end
    f.setup:SetShown(setup)
    f.play:SetShown(not setup)
    f.instruction:SetShown(not setup)
    if setup then
        f.status:SetText(ns.setupError or "Choose a section below, check your players, then Start game.")
        f.setup.Refresh()
        return
    end
    local deadline = g.deadline or g.readyDeadline
    local remaining = deadline and math.max(0, math.ceil(deadline - GetTime()))
    local replies = 0
    for _ in pairs(g.answers or {}) do replies = replies + 1 end
    local labels = { setup = "Ready to host", ready_announcing = "Announcing ready check", ready = "Ready check",
        announcing = "Announcing question", presenting = "Waiting for addon question delivery", opening = "Opening answers", accepting = "Answers open",
        revealing = "Results ready", between = "Between questions", paused = "Paused", finished = "Game complete", stopped = "Game stopped" }
    f.status:SetText((labels[g.phase] or g.phase) .. (g.config and (" | " .. (g.config.localOnly and "Local test" or ns.Game.CHANNELS[g.config.channel].label)
        .. (g.config.autoMode and " | Auto-advance" or " | Host-paced")
        .. (g.config.manualSend and " | Click-to-send" or "")) or "")
        .. (remaining and (" | " .. remaining .. "s | " .. (g.phase == "ready"
            and (#g:ReadyPlayers() .. " ready") or (replies .. " replies"))) or "")
        )
    local item = g.run and g.run[g.index]
    local ready = g.phase == "ready" or g.phase == "ready_announcing"
        or (g.phase == "paused" and (g.resumePhase == "readyRestart"
            or g.resumePhase == "ready_announcing" or g.resumePhase == "ready"))
    if f.wasReady and not ready then ns.scorePage = 1 end
    f.wasReady = ready
    f.question:SetText(ready and "Quiz starting soon. Type ready in chat to check in." or item and item.text or "Set up a game here, then start hosting.")
    for i, fs in ipairs(f.choices) do fs:SetText(not ready and item and (i .. ") " .. item.choices[i]) or "") end
    local host = person("player")
    local hostPlayer = host and g:FindPlayer(host.key, host.guid)
    local selected = hostPlayer and g.answers[hostPlayer.key]
    local answering = g.config.hostParticipates and g.phase == "accepting"
    local checkingIn = g.config.hostParticipates and (g.phase == "ready" or g.phase == "ready_announcing")
    for i, answer in ipairs(f.answerButtons) do
        local shown = answering or (checkingIn and i == 1)
        answer:SetShown(shown)
        f.choices[i]:SetShown(not shown)
        if shown then
            answer:SetText(checkingIn and "I'm ready" or ((selected == i and "Locked: " or "") .. i .. ") " .. item.choices[i]))
            T.Surface(answer, selected == i and "selected" or "raised", selected == i and "accent" or "edge")
            local player = hostPlayer
            answer:SetEnabled(player ~= nil and not ns.Restricted()
                and not (checkingIn and player.ready or not checkingIn and selected))
        end
    end
    local rows = ready and g:ReadyPlayers() or g:Standings(false)
    local offset = ((ns.scorePage or 1) - 1) * 10
    local eligible = 0
    for _ in pairs(g.players) do eligible = eligible + 1 end
    f.scoreTitle:SetText(ready and (#rows .. " ready / " .. eligible .. " enrolled") or ("Leaderboard | " .. eligible .. " enrolled"))
    for i, fs in ipairs(f.scores) do
        local p = rows[offset + i]
        fs:SetText(p and (ready and p.name or (p.name .. "  " .. p.total .. " pts | streak " .. p.streak)) or "")
    end
    f.pause:SetText(g.phase == "paused" and "Resume" or "Pause")
    f.newGame:SetText("Stop game")
    local pending, message = g.pending, g:NextMessage()
    f.preview:SetText(pending and ("Waiting for chat echo. " .. pending.text)
        or message and ((g.config.manualSend and "To send: " or "Sending: ") .. message)
        or g.nextQuestionAt and ("Next question in " .. math.max(0, math.ceil(g.nextQuestionAt - GetTime())) .. " seconds.")
        or g.phase == "accepting" and (selected and ("Answer locked: " .. selected .. ") " .. item.choices[selected]
            .. ". Scoring happens when the timer closes.") or "Click an answer or reply 1-4 in chat. Your first answer locks.")
        or g.phase == "ready" and "Check-in is optional. Start questions now, or wait for the countdown."
        or g.phase == "finished" and "Game complete. Player records saved."
        or g.phase == "paused" and (g.reason or "Paused. Resume when everyone is ready.")
        or "Time for chat. Click Next question when everyone is ready.")
    if InCombatLockdown() then return end -- includes attribute clearing
    local restricted = ns.Restricted()
    local prepared = not restricted and g.config.manualSend and message or nil
    if ns.preparedMessage ~= prepared then
        ns.preparedMessage = prepared
        f.send:SetAttribute("macrotext", prepared and not g.config.localOnly and (ns.Game.CHANNELS[g.config.channel].macro .. prepared) or nil)
    end
    local lineProgress = " (" .. g.cursor .. "/" .. #g.queue .. ")"
    local sendLabel = g.phase == "ready_announcing" and "Send ready notice" or g.phase == "announcing" and "Send question" or g.phase == "opening" and "Open answers" or "Send results"
    f.send.Text:SetText(pending and "Confirming chat..." or (sendLabel .. lineProgress))
    f.send:SetEnabled(prepared ~= nil)
    local manualLines = g.phase ~= "paused" and g.config.manualSend and (message ~= nil or pending ~= nil)
    f.send:SetShown(manualLines)
    f.next:SetShown(not manualLines)
    local action, canAdvance = "Sending announcements...", false
    if g.phase == "ready" then action, canAdvance = "Start questions now", true
    elseif g.phase == "between" then
        action = g.config.autoMode and ("Next question in " .. math.max(0, math.ceil((g.nextQuestionAt or GetTime()) - GetTime())) .. "s") or "Ask next question"
        canAdvance = not g.config.autoMode
    elseif g.phase == "paused" then action, canAdvance = "Resume game", true
    elseif g.phase == "finished" then action, canAdvance = "New game", true
    elseif g.phase == "accepting" then action = "Answers open: " .. (remaining or 0) .. "s" end
    f.next:SetText(action); f.next:SetEnabled(not restricted and canAdvance)
    local instructions = g.phase == "paused" and (pending
        and "Check chat: confirm the visible line, or Resume game to use Resend line."
        or "Paused: read the message below, then Resume game.")
        or ready and ns.lastUnmatched and "An unenrolled player replied. Refresh players, then ask them to type ready again."
        or ready and ns.readyNotice
        or pending and "Waiting for chat. After 8s, confirm the line below if you can see it."
        or manualLines and "Manual sending: click Send for each line. The timer waits for the final line."
        or g.phase == "ready" and "Check-ins are optional. Wait for the countdown, or Start questions now."
        or g.phase == "between" and (g.config.autoMode and "Automatic play continues after this gap." or "Chat break: click Ask next question when everyone is ready.")
        or g.phase == "finished" and "All results confirmed and records saved. New game returns to setup."
        or g.phase == "accepting" and "Players answer 1-4. Results follow when the timer expires."
        or "Sending announcements automatically, one confirmed line at a time."
    f.instruction:SetText((not ready and g.phase ~= "finished" and ("Round " .. g.round .. "/" .. g.config.rounds .. " | Q" .. ((g.index - 1) % g.config.perRound + 1) .. "/" .. g.config.perRound .. ": ") or "") .. instructions)
    f.mode:SetText(g.config.manualSend and "Retry auto send" or g.config.autoMode and "Use host pacing" or "Auto-advance")
    f.mode:SetEnabled(not restricted and g:Active())
    f.mode:SetShown(g:Active())
    local canRecover = pending and GetTime() - pending.sentAt >= 8
    f.recover:SetText("I saw this line in chat: continue")
    f.recover:SetShown(not restricted and canRecover)
    f.recover:SetEnabled(not restricted and canRecover)
    f.rosterRefresh:SetShown(ready)
    f.rosterRefresh:SetEnabled(not restricted)
    f.newGame:SetShown(g:Active()); f.newGame:SetEnabled(true)
    f.pause:SetShown(g:Active() and g.phase ~= "paused")
    f.pause:SetEnabled(not restricted and g:Active())
    f.retry:SetEnabled(not restricted and pending ~= nil and not g.config.autoMode and GetTime() - pending.sentAt >= 8)
    f.retry:SetShown(g.phase ~= "paused" and g.config.manualSend and pending ~= nil and GetTime() - pending.sentAt >= 8)
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
                ns.AutomaticFailed("The client blocked automatic output.")
            elseif ns.Restricted() then g:Pause("Chat is restricted; resume when it is safe.")
            elseif event == "PLAYER_ENTERING_WORLD" then g:Pause("Zone changed; resume when everyone is ready.")
            elseif event == "GROUP_ROSTER_UPDATE" and g.config.channel ~= "GUILD" and not g.config.localOnly then
                local signature = groupSignature(g.config.channel)
                if signature ~= ns.groupSignature then
                    ns.groupSignature = signature
                    if g.phase == "ready" or g.phase == "ready_announcing" then ns.RefreshReadyPlayers()
                    else g:Pause("Group membership changed; original players remain enrolled.") end
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
        if ns.game:Active() and ns.Restricted() then ns.game:Pause("Chat is restricted; resume when it is safe.") end
        ns.game:Tick()
        ns.PumpAutomatic()
        local second = math.floor(GetTime())
        if previous ~= ns.game.phase or second ~= ns.lastRefreshSecond then
            ns.lastRefreshSecond = second
            ns.RefreshHost()
        end
    end)
end
