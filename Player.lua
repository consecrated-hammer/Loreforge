local _, ns = ...
local HC = ns.HammerCore
local UI, T = HC.UI, HC.Theme

-- The player's quiz window: invitation, lobby, question card, reveal, results
-- and saved games.  It only draws the validated model the Party layer hands
-- to Render and calls ns.Party actions; scores and rules live with the host.
-- A host playing along gets the same window: their model comes from Host.lua
-- and carries `handlers`, which take the place of the ns.Party actions.
-- It follows the look of HammerCore's lore quiz (HammerCore/src/Quiz.lua).

local Player = { offered = {}, dismissed = {}, opened = {}, results = {} }
ns.Player = Player

local WIDTH, PAD, MAX_ROWS, MAX_HISTORY = 460, 16, 5, 20
local MAX_ROUNDS, ROUND_COLUMNS, MAX_ROUND_ROWS = 20, 5, 10
-- The body scrolls between a fixed title bar and timer, and a fixed footer of
-- actions.  The scroll bar sits in the right-hand margin.
local HEADER, FOOTER, MIN_BODY, MIN_HEIGHT = 64, 48, 120, 340
local INNER = WIDTH - PAD * 2
local NO_ART = { invitation = true, joining = true, history = true, stopped = true }
-- Question, answers, feedback, score, status and the standings heading.
local GAME_CARD = 270
local ACTIVE = { preparing=true, announcing=true, joining = true, lobby = true, ready = true, presenting = true, accepting = true,
    revealing = true, between = true, paused = true, disconnected = true }
local REVEALED = { revealing = true, between = true, finished = true }
-- The quiz card: question, answers, one feedback line and one score line.
local QUESTION = { announcing = true, presenting = true, accepting = true, revealing = true }
local NOT_CONFIRMED = "Answer not confirmed; use Party chat"

local function act(name, ...)
    local handlers = Player.model and Player.model.handlers
    if handlers then
        if handlers[name] then return handlers[name](...) end
        return
    end
    local party = ns.Party
    local fn = party and party[name]
    if type(fn) == "function" then return fn(...) end
end

local function restricted()
    if InCombatLockdown and InCombatLockdown() then return true end
    return ns.Restricted and ns.Restricted() or false
end

local function now() return GetTime and GetTime() or 0 end

local function text(value) return type(value) == "string" and value or "" end

local function ordinal(n)
    local tail = n % 100
    if tail >= 11 and tail <= 13 then return n .. "th" end
    return n .. (({ "st", "nd", "rd" })[n % 10] or "th")
end

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

local function clampScale(value)
    value = tonumber(value) or 1
    if value ~= value then value = 1 end
    return math.max(0.7, math.min(1.5, value))
end

-- ── Construction ───────────────────────────────────────────────────────────

local function label(parent, font, role, width)
    local fs = UI.FontString(parent, font or "GameFontHighlight", role or "text")
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    return fs
end

local function button(parent, width, run, variant)
    local b = UI.Button(parent, width, 24, variant)
    b:SetScript("OnClick", run)
    return b
end

local function answerButton(parent, index)
    local b = UI.Button(parent, INNER, 30)
    b:RegisterForClicks("LeftButtonUp")
    b.Text:ClearAllPoints()
    b.Text:SetPoint("CENTER")
    b.Text:SetWidth(INNER - 24)
    if b.Text.SetWordWrap then b.Text:SetWordWrap(true) end
    b.index = index
    b:SetScript("OnClick", function() Player.Choose(index) end)
    return b
end

local function standingRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(INNER, 20)
    row.name = label(row, "GameFontHighlightSmall", "text", INNER - 170)
    row.name:SetPoint("LEFT", 0, 0)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.score = label(row, "GameFontHighlightSmall", "muted", 170)
    row.score:SetPoint("RIGHT", 0, 0)
    row.score:SetJustifyH("RIGHT")
    return row
end

local function anchor(frame, invitation)
    local db = ns.db or {}
    frame:ClearAllPoints()
    if invitation then
        -- Invitations sit near the top of the screen, out of the way.
        frame:SetPoint("TOP", UIParent, "TOP", 0, -110)
    elseif type(db.playerLeft) == "number" and type(db.playerTop) == "number" then
        -- Pinned by its top edge, so a change of height only moves the bottom.
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.playerLeft, db.playerTop)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

local function savePosition(frame)
    if not ns.db then return end
    ns.db.playerLeft, ns.db.playerTop = frame:GetLeft(), frame:GetTop()
end

local function create()
    if Player.frame then return Player.frame end
    local f = CreateFrame("Frame", "LoreforgePlayerWindow", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 300)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- An invitation sits at its own spot; only the game window's position is kept.
        if not Player.anchoredInvite then savePosition(self) end
    end)
    T.Surface(f, "outer", "edge")
    local db = ns.db or {}
    f:SetScale(clampScale(db.playerScale))
    anchor(f, false)

    -- Below the title and close button, which sit on top of the painting.
    f.art = f:CreateTexture(nil, "BORDER")
    f.introBand = f:CreateTexture(nil, "BORDER", nil, 1)
    f.introBand:SetColorTexture(0, 0, 0, 0.7)
    f.introBand:SetPoint("BOTTOMLEFT", 1, 1)
    f.introBand:SetPoint("BOTTOMRIGHT", -1, 1)
    f.introBand:SetHeight(84)
    f.introRound = UI.FontString(f, "GameFontNormalHuge", "flavour")
    f.introRound:SetPoint("BOTTOM", 0, 46)
    f.introTheme = UI.FontString(f, "GameFontHighlightLarge", "text")
    f.introTheme:SetPoint("BOTTOM", 0, 20)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(20, 20)
    f.icon:SetPoint("TOPLEFT", PAD, -14)
    f.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    f.title = UI.FontString(f, "GameFontNormalLarge")
    f.title:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
    f.title:SetText("Loreforge")
    f.hide = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.hide:SetPoint("TOPRIGHT", -5, -5)
    f.hide:SetScript("OnClick", function() Player.Hide() end)
    UI.AttachHint(f.hide, "Hide", "You stay in the game. Click the Loreforge quiz button to come back.")
    f.position = UI.FontString(f, "GameFontHighlightSmall", "muted")
    f.position:SetPoint("TOPRIGHT", -40, -18)
    f.position:SetWidth(300)
    f.position:SetJustifyH("RIGHT")
    if f.position.SetWordWrap then f.position:SetWordWrap(false) end

    f.timer = CreateFrame("Frame", nil, f)
    f.timer:SetSize(INNER, 4)
    f.timer:SetPoint("TOPLEFT", PAD, -46)
    T.Fill(f.timer:CreateTexture(nil, "BACKGROUND"), "rail"):SetAllPoints()
    f.timer.fill = T.Fill(f.timer:CreateTexture(nil, "ARTWORK"), "selected")
    f.timer.fill:SetPoint("TOPLEFT")
    f.timer.fill:SetPoint("BOTTOMLEFT")

    f.scroll = CreateFrame("ScrollFrame", nil, f)
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -HEADER)
    f.scroll:SetSize(INNER, MIN_BODY)
    local body = CreateFrame("Frame", nil, f.scroll)
    body:SetSize(INNER, 1)
    f.scroll:SetScrollChild(body)
    f.body = body
    f.scroll:EnableMouseWheel(true)
    f.scroll:SetScript("OnMouseWheel", function(_, delta) Player.Scroll(delta) end)
    f.bar = CreateFrame("Slider", nil, f)
    f.bar:SetOrientation("VERTICAL")
    f.bar:SetSize(6, MIN_BODY)
    f.bar:SetPoint("TOPLEFT", f.scroll, "TOPRIGHT", 5, 0)
    T.Fill(f.bar:CreateTexture(nil, "BACKGROUND"), "rail"):SetAllPoints()
    local thumb = T.Fill(f.bar:CreateTexture(nil, "ARTWORK"), "selected")
    thumb:SetSize(6, 28)
    if f.bar.SetThumbTexture then f.bar:SetThumbTexture(thumb) end
    f.bar:SetScript("OnValueChanged", function(_, value)
        if not Player.syncingBar then Player.ScrollTo(value) end
    end)

    -- Completion view: a headline, the winner line and your result.
    f.headline = label(body, "GameFontNormalLarge", "flavour", INNER)
    f.winner = label(body, "GameFontHighlight", "text", INNER)
    f.status = label(body, "GameFontHighlight", "text", INNER)
    f.detail = label(body, "GameFontHighlightSmall", "muted", INNER)
    f.question = label(body, "GameFontHighlight", "text", INNER)
    f.answers = {}
    for i = 1, 4 do f.answers[i] = answerButton(body, i) end
    f.feedback = label(body, "GameFontNormal", "flavour", INNER)
    f.feedback:SetJustifyH("CENTER")
    f.you = label(body, "GameFontHighlightSmall", "muted", INNER)
    f.standTitle = label(body, "GameFontNormal", "accent", INNER)
    f.rows = {}
    for i = 1, MAX_ROWS + 1 do f.rows[i] = standingRow(body) end
    f.history = {}
    for i = 1, MAX_HISTORY do
        local entry = UI.Button(body, INNER, 26)
        entry.Text:ClearAllPoints()
        entry.Text:SetPoint("LEFT", 10, 0)
        entry.Text:SetWidth(INNER - 20)
        entry.Text:SetJustifyH("LEFT")
        entry:SetScript("OnClick", function(self) if self.entryId then act("OpenHistory", self.entryId) end end)
        f.history[i] = entry
    end
    -- Saved games can carry per-round standings; the finished view lists a
    -- button per round under the final standings, which stay in place.
    f.roundTitle = label(body, "GameFontNormal", "accent", INNER)
    f.roundBar = CreateFrame("Frame", nil, body)
    f.roundBar:SetSize(INNER, 24)
    f.roundButtons = {}
    for i = 1, MAX_ROUNDS do
        local b = UI.Button(f.roundBar, 70, 22)
        b:SetPoint("TOPLEFT", ((i - 1) % ROUND_COLUMNS) * 76, -math.floor((i - 1) / ROUND_COLUMNS) * 26)
        b:SetScript("OnClick", function() Player.ToggleRound(i) end)
        f.roundButtons[i] = b
    end
    f.roundRows = {}
    for i = 1, MAX_ROUND_ROWS + 1 do f.roundRows[i] = standingRow(body) end
    f.primary = button(f, 170, function() Player.Primary() end, "primary")
    f.secondary = button(f, 120, function() Player.Secondary() end)
    f.leave = button(f, 90, function() Player.Leave() end, "danger")
    f.leave:SetText("Leave")
    UI.AttachHint(f.leave, "Leave", "Leave the game. Points you've scored stay on the board.")

    -- Hiding by any route (Hide, Escape) keeps the player joined and leaves
    -- the restore button; only Player.Show brings the window back.
    f:SetScript("OnHide", function()
        if Player.drawing then return end
        local model = Player.model
        Player.hiddenFor = model and model.id
        Player.RefreshRestore()
    end)
    f:SetScript("OnUpdate", function(self, elapsed)
        self.tick = (self.tick or 0) + (elapsed or 0)
        if self.tick < 0.1 then return end
        self.tick = 0
        Player.UpdateTimer()
    end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = f:GetName() end
    Player.drawing = true
    f:Hide()
    Player.drawing = false
    Player.frame = f

    local restore = UI.Button(UIParent, 150, 24, "primary")
    restore:SetPoint("TOP", UIParent, "TOP", 0, -140)
    restore:SetFrameStrata("DIALOG")
    restore:SetFrameLevel(10)
    restore:SetMovable(true)
    restore:RegisterForDrag("LeftButton")
    restore:SetScript("OnDragStart", function(self) self:StartMoving() end)
    restore:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    restore:SetScript("OnClick", function()
        if ns.Party and ns.Party.viewHistory then act("RequestSync") end
        Player.Show()
    end)
    restore:SetText("Loreforge quiz")
    -- A gentle pulse while a question waits for this player's answer.
    restore:SetScript("OnUpdate", function(self, elapsed)
        if not self.pulsing then return end
        self.phase = ((self.phase or 0) + (elapsed or 0) * 3) % (math.pi * 2)
        self:SetAlpha(0.65 + 0.35 * math.cos(self.phase))
    end)
    restore:Hide()
    Player.restore = restore
    return f
end

-- ── Drawing ────────────────────────────────────────────────────────────────

local function myRow(model)
    if type(model.rows) ~= "table" then return nil end
    for _, row in ipairs(model.rows) do
        if row.key and row.key == model.me then return row end
    end
end

local function choiceText(model, index)
    local choices = type(model.choices) == "table" and model.choices or {}
    return text(choices[index])
end

-- The answer this client should show as chosen, and whether the host has
-- accepted it.  A click shows Sending at once, before the model catches up.
local function chosen(model)
    if model.locked then return model.locked, "locked" end
    if model.selected then return model.selected, model.pending and "pending" or "unconfirmed" end
    local mine = Player.clicked
    if mine and mine.id == model.id and mine.index == model.index and mine.attempt == model.attempt
        and now() - mine.at < 5 then
        return mine.choice, "pending"
    end
end

local function remaining(model)
    if type(model.deadline) ~= "number" then return nil end
    return math.max(0, model.deadline - now())
end

local STATUS = {
    invitation = function(m) return (m.host or "The host") .. " invited you to a quiz." end,
    joining = function(m) return "Joining. Waiting for " .. (m.host or "the host") .. " to confirm." end,
    lobby = function(m) return "You're in. Waiting for " .. (m.host or "the host") .. " to start." end,
    ready = function(m)
        if (m.remaining or 0)>0 and (remaining(m) or 0)<=0 then return "Countdown complete. Waiting for the first question." end
        if m.ready then return "You're ready. Waiting for everyone else." end
        if m.readyPending then return "Ready sent. Waiting for the host to confirm." end
        return m.readyStatus or "Ready check: are you ready?"
    end,
    preparing = function() return "Preparing the next question for everyone." end,
    revealing = function(m)
        if tonumber(m.index) and m.index == tonumber(m.totalQuestions) then return "Final scores coming up." end
    end,
    between = function(m)
        if type(m.nextAt) == "number" then
            return "Next question in " .. math.max(0, math.ceil(m.nextAt - now())) .. "s."
        end
        return m.hostPaced and "The host will start the next question." or "Waiting for the next question."
    end,
    paused = function() return "The game is paused." end,
    finished = function(m) return "Final results from " .. (m.host or "the host") .. "." end,
    stopped = function(m) return (m.host or "The host") .. " stopped the game." end,
    disconnected = function(m) return "Lost contact with " .. (m.host or "the host") .. "." end,
    history = function() return "Your games" end,
}

local function configLine(config)
    if type(config) ~= "table" then return "" end
    local parts = {}
    if config.rounds and config.perRound then
        parts[#parts + 1] = plural(config.rounds, "round") .. " of " .. plural(config.perRound, "question")
    end
    if config.seconds then parts[#parts + 1] = config.seconds .. "s to answer" end
    if config.difficulty then
        local d = tostring(config.difficulty)
        parts[#parts + 1] = d:sub(1, 1):upper() .. d:sub(2)
    end
    if config.readyCheck then parts[#parts + 1] = "Ready check" end
    local line = table.concat(parts, " · ")
    if text(config.categories) ~= "" then line = line .. (line ~= "" and "\n" or "") .. config.categories end
    return line
end

local function positionLine(model)
    local parts = {}
    local config = type(model.config) == "table" and model.config or {}
    -- Same numbering as the host: the question within its round.
    local rounds = tonumber(config.rounds) or 1
    if model.round and rounds > 1 then
        parts[#parts + 1] = "Round " .. model.round .. (text(model.theme) ~= "" and (": " .. model.theme) or (" of " .. rounds))
    end
    local per = tonumber(config.perRound)
    if tonumber(model.index) and model.index > 0 and per and per > 0 then
        parts[#parts + 1] = ((model.index - 1) % per + 1) .. " of " .. per
    end
    return table.concat(parts, " · ")
end

local function scoreText(row, state, rounds)
    local total = tonumber(row.total) or 0
    local parts = { plural(total, "point") }
    if rounds > 1 and (state == "between" or state == "revealing") then
        local round = tonumber(row.round)
        if round and round > 0 then parts[#parts + 1] = "+" .. round .. " this round" end
    end
    local streak = tonumber(state == "finished" and row.bestStreak or row.streak) or 0
    if streak >= 2 then parts[#parts + 1] = (state == "finished" and "best streak " or "streak ") .. streak end
    return table.concat(parts, " · ")
end

local function drawRows(f, model)
    local rows = type(model.rows) == "table" and model.rows or {}
    local shown, pinned = {}, nil
    for i = 1, math.min(#rows, MAX_ROWS) do shown[#shown + 1] = rows[i] end
    local me = myRow(model)
    if me then
        local visible = false
        for _, row in ipairs(shown) do if row == me then visible = true end end
        if not visible then pinned = me; shown[#shown + 1] = me end
    end
    local winners = 0
    for _, row in ipairs(rows) do if row.winner then winners = winners + 1 end end
    local lobby = model.state == "lobby" or model.state == "ready" or model.state == "joining"
    for i, widget in ipairs(f.rows) do
        local row = shown[i]
        widget:SetShown(row ~= nil)
        if row then
            local name = text(row.name) ~= "" and row.name or tostring(row.key or "?")
            local rank = row.rank and (row.rank .. ".  ") or ""
            if lobby then rank = "" end
            local suffix = ""
            if row == me then suffix = " (you)" end
            if row.winner and model.state == "finished" then suffix = suffix .. (winners > 1 and " · Shared win" or " · Winner") end
            widget.name:SetText((row == pinned and "... " or "") .. rank .. name .. suffix)
            -- Final standings read at normal size; live standings stay compact.
            local font = model.state == "finished" and "GameFontHighlight" or "GameFontHighlightSmall"
            if widget.name.SetFontObject then widget.name:SetFontObject(font); widget.score:SetFontObject(font) end
            local medal = model.state == "finished" and (tonumber(row.total) or 0) > 0 and ns.MEDALS and ns.MEDALS[tonumber(row.rank) or 0]
            if row == me then T.Text(widget.name, "selected")
            elseif medal then widget.name:SetTextColor(medal[1], medal[2], medal[3])
            else T.Text(widget.name, "text") end
            widget.score:SetText(lobby and "" or scoreText(row, model.state, tonumber(type(model.config) == "table" and model.config.rounds) or 1))
        end
    end
    return #shown
end

-- The quiz's look: plain rows, with borders doing the talking.  Returns the
-- feedback line under them.
local function drawAnswers(f, model)
    local state = model.state
    local choice, confirm = chosen(model)
    local left = remaining(model)
    -- Open until time's up: another click changes the answer.
    local open = state == "accepting" and (left == nil or left > 0)
    local correct = REVEALED[state] and tonumber(model.correct) or nil
    for i, b in ipairs(f.answers) do
        b:SetText(choiceText(model, i))
        local border, role = "edge", "text"
        if correct then
            if i == correct then border = "accent"
            elseif i == choice then border = "danger"
            else role = "muted" end
        elseif i == choice then
            border = "selected"
        elseif not open then
            role = "muted"
        end
        T.Border(b, border)
        T.Text(b.Text, role)
        b:SetEnabled(open)
        local height = b.Text.GetStringHeight and b.Text:GetStringHeight() or 14
        b:SetHeight(math.max(30, math.ceil(height) + 16))
    end
    if correct then
        if choice == correct then
            local me = myRow(model)
            local streak = me and tonumber(me.streak) or 0
            return streak >= 2 and ("Correct! Streak " .. streak .. ".") or "Correct!"
        end
        if choice then return "Not quite." end
        return model.joined and "Out of time!" or ""
    end
    if state == "announcing" or state == "presenting" then return "Answers open in a moment." end
    if state ~= "accepting" then return "" end
    if confirm == "locked" then return "Answer in. Click another to change it." end
    if confirm == "pending" then return "Sending..." end
    if confirm == "unconfirmed" then return text(model.answerStatus) ~= "" and model.answerStatus or NOT_CONFIRMED end
    if left and left <= 0 then return "Out of time!" end
    return text(model.answerStatus)
end

-- Top scorers of a finished game: names of everyone sharing the best total
-- above zero, and that total.
local function winners(model)
    local rows = type(model.rows) == "table" and model.rows or {}
    local best = 0
    for _, row in ipairs(rows) do best = math.max(best, tonumber(row.total) or 0) end
    local names = {}
    if best > 0 then
        for _, row in ipairs(rows) do
            if (tonumber(row.total) or 0) == best then
                names[#names + 1] = text(row.name) ~= "" and row.name or tostring(row.key or "?")
            end
        end
    end
    return names, best
end

-- Completion view: "Game complete", then the winner or a shared win.
local function headlineText(model)
    return model.state == "finished" and "Game complete" or ""
end

local function winnerText(model)
    if model.state ~= "finished" then return "" end
    if model.resultsPending and #(type(model.rows) == "table" and model.rows or {}) == 0 then return "Final scores are on their way." end
    local names, best = winners(model)
    if #names == 0 then return "No correct answers, so no winner this time." end
    if #names == 1 then return names[1] .. " wins with " .. plural(best, "point") .. "." end
    return "Shared win: " .. table.concat(names, ", ") .. ", " .. plural(best, "point") .. " each."
end

local function finishedYouText(model)
    local me = myRow(model)
    if not me then
        -- Only players who answered appear in the standings.
        if not model.joined then return "" end
        return model.resultsPending and "Your result arrives with the final scores."
            or "You didn't answer any questions in this game."
    end
    local rank, total = tonumber(me.rank) or 0, tonumber(me.total) or 0
    local rows = type(model.rows) == "table" and model.rows or {}
    local result
    if rank == 1 and total > 0 then
        result = (#winners(model) > 1 and "You shared the win with " or "You won with ") .. plural(total, "point")
    elseif rank > 0 then
        result = "You finished " .. ordinal(rank) .. " of " .. #rows .. " with " .. plural(total, "point")
    else
        result = "You scored " .. plural(total, "point")
    end
    local parts = { result }
    local best = tonumber(me.bestStreak) or 0
    if best >= 2 then parts[#parts + 1] = "best streak " .. best end
    return table.concat(parts, " · ")
end

local function youText(model)
    if model.state == "finished" then return finishedYouText(model) end
    local me = myRow(model)
    if not me then return model.joined and "You: no points yet" or "" end
    local parts = { "You: " .. plural(tonumber(me.total) or 0, "point") }
    if (tonumber(me.streak) or 0) >= 1 and model.state ~= "finished" then parts[#parts + 1] = "streak " .. me.streak end
    if me.rank then parts[#parts + 1] = ordinal(tonumber(me.rank) or 0) end
    if model.state == "accepting" and model.answeredCount then parts[#parts + 1] = model.answeredCount .. " answered" end
    return table.concat(parts, " · ")
end

local function historyText(entry)
    local date = entry.date
    if type(date) == "number" and _G.date then date = _G.date("%d %b %H:%M", date) end
    local parts = { tostring(date or "?"), text(entry.host) ~= "" and entry.host or "Unknown host" }
    if entry.rank then parts[#parts + 1] = ordinal(tonumber(entry.rank) or 0) end
    if entry.score then
        parts[#parts + 1] = entry.score .. (entry.totalQuestions and ("/" .. entry.totalQuestions) or "") .. " correct"
    end
    return table.concat(parts, " · ")
end

local function roundEntries(model)
    if model.state ~= "finished" or type(model.rounds) ~= "table" or #model.rounds < 2 then return {} end
    local entries = {}
    for i = 1, math.min(#model.rounds, MAX_ROUNDS) do
        if type(model.rounds[i]) == "table" then entries[#entries + 1] = model.rounds[i] end
    end
    return entries
end

-- Round rows carry keys and scores; names come from the final standings.
local function drawRoundRows(f, model, entry)
    local names = {}
    for _, row in ipairs(type(model.rows) == "table" and model.rows or {}) do
        if row.key then names[row.key] = row.name end
    end
    local rows = entry and type(entry.rows) == "table" and entry.rows or {}
    local shown, pinned = {}, nil
    for i = 1, math.min(#rows, MAX_ROUND_ROWS) do shown[#shown + 1] = rows[i] end
    for i = MAX_ROUND_ROWS + 1, #rows do
        if rows[i].key and rows[i].key == model.me then pinned = rows[i]; shown[#shown + 1] = rows[i] end
    end
    for i, widget in ipairs(f.roundRows) do
        local row = shown[i]
        widget:SetShown(row ~= nil)
        if row then
            local name = text(row.name) ~= "" and row.name or text(names[row.key]) ~= "" and names[row.key]
                or tostring(row.key or "?")
            local mine = row.key and row.key == model.me
            widget.name:SetText((row == pinned and "... " or "") .. (row.rank and (row.rank .. ".  ") or "")
                .. name .. (mine and " (you)" or ""))
            T.Text(widget.name, mine and "selected" or "text")
            local parts = { "+" .. (tonumber(row.round) or 0) .. " this round" }
            if row.total then parts[#parts + 1] = "total " .. row.total end
            widget.score:SetText(table.concat(parts, " · "))
        end
    end
    return #shown
end

local function actions(model)
    if model.handlers then
        local step = model.hostStep
        -- The console button stays out of the way on the quiz card.
        local console = model.consoleHidden and not QUESTION[model.state] and "Host console" or nil
        if step then return step.label, true, not step.console and console or nil end
        if model.state == "ready" and not model.ready then
            return (remaining(model) or 1) > 0 and "I'm ready" or "Starting...", (remaining(model) or 1) > 0, console
        end
        return nil, false, console
    end
    if model.activeMatch then return "Return to match",true,"Close" end
    local state = model.state
    if state == "invitation" then return "Join quiz", true, "Decline" end
    if state == "joining" then return "Joining...", false end
    if state == "ready" then
        if (model.remaining or 0) > 0 and (remaining(model) or 0) <= 0 then return "Starting...", false end
        if model.ready then return "Ready", false end
        if model.readyPending then return "Ready sent...", false end
        return model.readyStatus and "Try ready again" or "I'm ready", true
    end
    if state == "accepting" then
        local _, confirm = chosen(model)
        if confirm == "unconfirmed" then return "Retry answer", true end
    end
    if state == "disconnected" then return "Reconnect", true end
    if state == "finished" or state == "stopped" then return "Your games", true, "Close" end
    if state == "history" then return nil, false, "Close" end
end

-- Stack visible regions top to bottom; heights follow wrapped text so long
-- questions and choices push later rows down rather than overlap; the
-- body scrolls once it outgrows the screen.
local function layout(body, items)
    local y = 0
    for _, item in ipairs(items) do
        local region, gap = item[1], item[2] or 8
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
        local height = item[3] or (region.GetStringHeight and region:GetStringHeight()) or region:GetHeight()
        y = y - math.ceil(height) - gap
    end
    return y
end

function Player.Draw()
    local f, model = Player.frame, Player.model
    if not (f and model) then return end
    local state = model.roundIntro and "round_intro" or model.state
    local artKey = ns.db.questionArt ~= false and model.joined and not NO_ART[state] and Player.ArtPath(model) or nil
    local items = {}
    local function add(region, show, gap, height)
        region:SetShown(show and true or false)
        if show then items[#items + 1] = { region, gap, height } end
    end

    f.position:SetText((state == "history" or state == "round_intro") and "" or positionLine(model))
    local headline = headlineText(model)
    f.headline:SetText(headline)
    add(f.headline, headline ~= "", 8)
    local winner = winnerText(model)
    f.winner:SetText(winner)
    add(f.winner, winner ~= "", 6)
    -- On the quiz card the feedback line speaks for the state; between
    -- questions the status follows the score line instead.
    local status = (not QUESTION[state] or state == "revealing") and STATUS[state] and STATUS[state](model) or ""
    f.status:SetText(status)
    add(f.status, status ~= "" and state ~= "between" and state ~= "revealing", 4)
    local detail = text(model.status)
    if state == "history" and (type(model.history) ~= "table" or #model.history == 0) then
        detail = "No saved games yet. Finished games you play in appear here."
    elseif state == "invitation" or state == "lobby" or state == "joining" or state == "ready" then
        local config = configLine(model.config)
        detail = detail ~= "" and (detail .. "\n" .. config) or config
    elseif state == "stopped" or state == "disconnected" then
        detail = detail ~= "" and detail or text(model.reason)
    end
    if state == "round_intro" then detail = "" end
    f.detail:SetText(detail)
    add(f.detail, detail ~= "", 10)

    f.timer:SetShown((state == "accepting" or (state == "ready" and (model.remaining or 0) > 0))
        and type(model.deadline) == "number")
    -- The completion view leaves the last question and choices behind.
    local finished = state == "finished"
    local question = not finished and (QUESTION[state] or REVEALED[state]) and text(model.question) or ""
    f.question:SetText(question)
    add(f.question, question ~= "", 14)
    local hasChoices = question ~= "" and type(model.choices) == "table"
    local feedback = hasChoices and drawAnswers(f, model) or ""
    for _, b in ipairs(f.answers) do add(b, hasChoices, 6, b:GetHeight()) end
    f.feedback:SetText(feedback)
    add(f.feedback, feedback ~= "", 10)

    local you = (ACTIVE[state] and state ~= "joining" or finished) and youText(model) or ""
    f.you:SetText(you)
    if f.you.SetFontObject then f.you:SetFontObject(finished and "GameFontHighlight" or "GameFontHighlightSmall") end
    T.Text(f.you, finished and "selected" or "muted")
    add(f.you, you ~= "", finished and 16 or 12)
    add(f.status, status ~= "" and (state == "between" or state == "revealing"), 12)

    local history = state == "history"
    local count = (history or QUESTION[state] or state == "round_intro") and 0 or drawRows(f, model)
    local heading = ""
    if count > 0 then
        heading = (state == "lobby" or state == "ready" or state == "joining") and "Players"
            or state == "finished" and "Final standings" or "Standings"
        if model.resultsPending then heading = heading .. " · Results pending" end
    end
    f.standTitle:SetText(heading)
    add(f.standTitle, heading ~= "", 6)
    for i, row in ipairs(f.rows) do add(row, i <= count, finished and 4 or 2, finished and 22 or 20) end

    local rounds = roundEntries(model)
    local view = Player.roundView
    local selected = view and view.id == model.id and rounds[view.round] and view.round or nil
    f.roundTitle:SetText(#rounds > 0 and ("Round scores" .. (selected and (" · Round "
        .. (rounds[selected].round or selected)) or "")) or "")
    if #rounds > 0 then
        local lastItem = items[#items]
        if lastItem then lastItem[2] = 12 end
    end
    add(f.roundTitle, #rounds > 0, 6)
    for i, b in ipairs(f.roundButtons) do
        local entry = rounds[i]
        b:SetShown(entry ~= nil)
        if entry then
            b:SetText("Round " .. tostring(entry.round or i))
            T.Border(b, i == selected and "selected" or "edge")
        end
    end
    add(f.roundBar, #rounds > 0, 8, math.ceil(#rounds / ROUND_COLUMNS) * 26)
    local roundCount = selected and drawRoundRows(f, model, rounds[selected]) or 0
    for i, row in ipairs(f.roundRows) do add(row, i <= roundCount, 2, 20) end

    local entries = history and type(model.history) == "table" and model.history or {}
    for i, entry in ipairs(f.history) do
        local data = entries[i]
        entry.entryId = data and data.id
        if data then entry:SetText(historyText(data)) end
        add(entry, data ~= nil, 4, 26)
    end
    local primary, enabled, secondary = actions(model)
    f.primary:SetShown(primary ~= nil)
    if primary then
        f.primary:SetText(primary); f.primary:SetEnabled(enabled)
        -- A waiting label ("Ready", "Joining...") mustn't look clickable.
        T.Border(f.primary, enabled and "accent" or "edge")
        T.Text(f.primary.Text, enabled and "text" or "muted")
    end
    f.secondary:SetShown(secondary ~= nil)
    if secondary then f.secondary:SetText(secondary) end
    f.leave:SetShown(model.joined and ACTIVE[state] and not QUESTION[state] and not model.handlers or false)
    local content = math.max(1, -layout(f.body, items))
    f.primary:ClearAllPoints(); f.primary:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 16)
    f.secondary:ClearAllPoints()
    f.secondary:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", primary and PAD + 180 or PAD, 16)
    local footer = (primary or secondary or f.leave:IsShown()) and FOOTER or 16
    local viewHeight = math.min(content, Player.MaxBody(footer))
    f.body:SetHeight(content)
    f.scroll:SetSize(INNER, viewHeight)
    f.bar:SetHeight(viewHeight)
    f:SetHeight(Player.StableHeight(model, HEADER + viewHeight + footer))
    Player.DrawArt(f, model, artKey, state == "round_intro")
    -- A new question or phase starts at the top; ticks keep the position.
    local key = tostring(model.id) .. ":" .. tostring(state) .. ":" .. tostring(model.index)
    if key ~= Player.scrollKey then Player.scrollKey, Player.scrollOffset = key, 0 end
    Player.scrollRange = math.max(0, content - viewHeight)
    f.bar:SetShown(Player.scrollRange > 0)
    Player.ScrollTo(Player.scrollOffset or 0)
    Player.UpdateTimer()
end

function Player.ArtPath(model)
    local key = text(model.art)
    if key ~= "mixed" then
        local known = false
        for _, category in ipairs(ns.Game and ns.Game.CATEGORIES or {}) do
            if category[1] == key then known = true end
        end
        if not known then key = "mixed" end
    end
    return "Interface\\AddOns\\Loreforge\\Textures\\theme-" .. key .. ".tga"
end

-- The square paintings are never cropped: the window widens by the panel's full
-- height. A window too tall for the screen's width keeps a smaller square, in
-- the middle of the panel. A round intro centres it across the whole window.
function Player.DrawArt(f, model, path, intro)
    local height = f:GetHeight() - 2
    local side = height
    if path then
        local screen = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
        local scale = f:GetScale() or 1
        if screen and screen > 0 and scale > 0 then
            side = math.max(1, math.min(side, math.floor(screen * 0.95 / scale) - WIDTH - 2))
        end
    end
    f:SetWidth(path and WIDTH + side + 2 or WIDTH)
    local rightGap = path and side + 1 or 0
    f.position:ClearAllPoints()
    f.position:SetPoint("TOPRIGHT", path and -(rightGap + PAD) or -40, -18)
    f.leave:ClearAllPoints(); f.leave:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD + rightGap), 16)
    f.art:SetShown(path ~= nil)
    f.art:ClearAllPoints()
    if path then
        f.art:SetTexture(path)
        f.art:SetSize(side, side)
        if intro then f.art:SetPoint("CENTER")
        else f.art:SetPoint("RIGHT", -1, 0) end
        f.art:SetTexCoord(0, 1, 0, 1)
    end
    f.introBand:SetShown(intro)
    f.introRound:SetShown(intro)
    f.introTheme:SetShown(intro)
    if intro then
        f.introRound:SetText("Round " .. (tonumber(model.round) or 1))
        f.introTheme:SetText(text(model.theme) ~= "" and model.theme or "A bit of everything")
    end
end

-- A game's window holds its height: it starts tall enough for the card plus
-- the standings it will show, and after that only ever grows.
function Player.StableHeight(model, wanted)
    local height = MIN_HEIGHT
    if model.joined and model.id then
        if Player.heightFor ~= model.id then Player.heightFor, Player.heldHeight = model.id, nil end
        local rows = type(model.rows) == "table" and math.min(#model.rows, MAX_ROWS + 1) or 0
        height = math.max(height, HEADER + GAME_CARD + rows * 22 + FOOTER)
        height = math.max(height, Player.heldHeight or 0, wanted)
        height = math.min(height, math.max(wanted, HEADER + Player.MaxBody(FOOTER) + FOOTER))
        Player.heldHeight = height
        return height
    end
    return math.max(height, wanted)
end

-- The tallest body that keeps the window, title and footer on screen at the
-- window's scale.
function Player.MaxBody(footer)
    local screen = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
    if not screen or screen <= 0 then screen = 768 end
    local scale = Player.frame and Player.frame:GetScale() or 1
    if not scale or scale <= 0 then scale = 1 end
    return math.max(MIN_BODY, math.floor(screen * 0.85 / scale) - HEADER - (footer or FOOTER))
end

function Player.ScrollTo(offset)
    local f = Player.frame
    if not f then return end
    local range = Player.scrollRange or 0
    offset = math.max(0, math.min(range, tonumber(offset) or 0))
    Player.scrollOffset = offset
    f.scroll:SetVerticalScroll(offset)
    Player.syncingBar = true
    f.bar:SetMinMaxValues(0, math.max(1, range))
    f.bar:SetValue(offset)
    Player.syncingBar = false
end

function Player.Scroll(delta)
    Player.ScrollTo((Player.scrollOffset or 0) - (tonumber(delta) or 0) * 40)
end

function Player.ToggleRound(index)
    local model = Player.model
    if not model then return end
    local view = Player.roundView
    if view and view.id == model.id and view.round == index then Player.roundView = nil
    else Player.roundView = { id = model.id, round = index } end
    Player.Draw()
end

function Player.UpdateTimer()
    local f, model = Player.frame, Player.model
    if not (f and model and (model.state == "accepting" or model.state == "ready") and f.timer:IsShown()) then return end
    local left = remaining(model) or 0
    local seconds = type(model.config) == "table" and tonumber(model.state == "ready"
        and (model.config.readySeconds or (model.remaining or 0) / 1000) or model.config.seconds) or nil
    local fraction = seconds and seconds > 0 and math.min(1, left / seconds) or 0
    f.timer.fill:SetShown(fraction > 0)
    f.timer.fill:SetWidth(math.max(1, INNER * fraction))
    if ns.TimerColour then ns.TimerColour(f.timer.fill, left, seconds) end
    if model.state == "ready" then f.position:SetText("Starting in " .. math.ceil(left) .. "s") end
    -- A soft tick for each of the last five seconds, until this player answers.
    local whole = math.ceil(left)
    if model.state == "accepting" and whole >= 1 and whole <= 5 and whole ~= Player.lastTick and not chosen(model) then
        Player.lastTick = whole
        if ns.Sound then ns.Sound("tick") end
    end
    -- The deadline passing closes the choices without waiting for a model tick.
    if left <= 0 and not f.timer.expired then
        f.timer.expired = true
        Player.Draw()
    elseif left > 0 then
        f.timer.expired = nil
    end
end

function Player.RefreshRestore()
    local restore, model = Player.restore, Player.model
    if not restore then return end
    local frame = Player.frame
    local browsing=ns.Party and ns.Party.viewHistory and ns.Party.client and ns.Party.client.joined
    if browsing then model=ns.Party.client.model end
    local show = model and model.joined and ACTIVE[model.state] and not Player.dismissed[model.id]
        and (browsing or not (frame and frame:IsShown())) or false
    local urgent = show and model.state == "accepting" and not chosen(model)
    restore:SetText(urgent and "Loreforge: answer now" or "Loreforge quiz")
    restore.pulsing = urgent or nil
    if not urgent then restore:SetAlpha(1) end
    restore:SetShown(show)
end

-- ── Visibility ─────────────────────────────────────────────────────────────

local function open()
    local f = create()
    if ns.hostFrame then f:SetFrameLevel(ns.hostFrame:GetFrameLevel() + 10) end
    Player.hiddenFor = nil
    local invitation = Player.model and Player.model.state == "invitation" or false
    if Player.anchoredInvite ~= invitation then
        Player.anchoredInvite = invitation
        anchor(f, invitation)
    end
    if not f:IsShown() then
        f:Raise()
        Player.drawing = true
        f:Show()
        Player.drawing = false
    end
end

local function close()
    local f = Player.frame
    if f and f:IsShown() then
        Player.drawing = true
        f:Hide()
        Player.drawing = false
    end
end

-- Decides whether a model should bring the window up.  Each session opens
-- the window at most once on its own; after the player hides it, only the
-- restore button or Player.Show reopens it, so ticks never pop it back.
local function wantsWindow(model)
    local id, state = model.id, model.state
    local frame = Player.frame
    if state == "history" then return true end
    if id and Player.dismissed[id] then return false end
    -- Final results open once even if the player hid the window mid-game.
    if state == "finished" and model.joined and id and not Player.results[id] then
        Player.results[id] = true
        return true
    end
    if id and Player.hiddenFor == id then return false end
    if frame and frame:IsShown() then return true end
    if state == "invitation" then
        if not id or Player.offered[id] then return false end
        if restricted() then Player.deferred = id; return false end
        Player.offered[id], Player.deferred = true, nil
        if ns.Sound then ns.Sound("invite") end
        return true
    end
    if model.joined and (ACTIVE[state] or state == "finished") and not Player.opened[id] then
        Player.opened[id] = true
        return true
    end
    return false
end

function Player.Initialise()
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function()
        local model = Player.model
        if model and Player.deferred == model.id then Player.Render(model) end
    end)
    Player.events = events
end

function Player.Render(model)
    if type(model) ~= "table" then
        Player.model = nil
        close()
        Player.RefreshRestore()
        return
    end
    local previous = Player.model
    if previous and previous.id ~= model.id then Player.clicked = nil end
    Player.model = model
    Player.Cue(previous, model)
    if wantsWindow(model) then
        local id = model.id
        if id and model.joined then Player.opened[id] = true end
        open()
        Player.Draw()
    else
        close()
    end
    Player.RefreshRestore()
end

-- Sound cues for a joined player: a new question, the reveal and the finish.
function Player.Cue(previous, model)
    if not ns.Sound or not model.joined then return end
    local key = tostring(model.id) .. ":" .. tostring(model.index) .. ":" .. tostring(model.attempt)
    local state = model.state
    if model.roundIntro and Player.cueIntro ~= key then
        Player.cueIntro = key
        ns.Sound("invite")
    elseif state == "accepting" and Player.cueQuestion ~= key then
        Player.cueQuestion, Player.lastTick = key, nil
        ns.Sound("question")
    elseif (state == "revealing" or state == "between") and Player.cueReveal ~= key and tonumber(model.correct) then
        Player.cueReveal = key
        local choice = chosen(model)
        if choice then ns.Sound(choice == tonumber(model.correct) and "correct" or "wrong") end
    elseif state == "finished" and Player.cueFinish ~= model.id and not (ns.Party and ns.Party.viewHistory) then
        Player.cueFinish = model.id
        local me = myRow(model)
        ns.Sound(me and tonumber(me.rank) == 1 and (tonumber(me.total) or 0) > 0 and "win" or "finish")
    end
end

function Player.ApplyScale()
    if Player.frame then Player.frame:SetScale(clampScale(ns.db and ns.db.playerScale)) end
end

function Player.Show()
    if not Player.model then return end
    if Player.model.id then Player.dismissed[Player.model.id] = nil end
    open()
    Player.Draw()
    Player.RefreshRestore()
end

function Player.Hide()
    local f = Player.frame
    if f and f:IsShown() then f:Hide() else Player.RefreshRestore() end
end

-- ── Actions ────────────────────────────────────────────────────────────────

function Player.Choose(index)
    if restricted() then return end
    local model = Player.model
    if not (model and model.state == "accepting") then return end
    if chosen(model) == index then return end
    local left = remaining(model)
    if left and left <= 0 then return end
    Player.clicked = { id = model.id, index = model.index, attempt = model.attempt, choice = index, at = now() }
    Player.Draw()
    local accepted=act("Answer", index)
    if accepted==false then
        Player.clicked=nil
        if not model.selected then model.answerStatus="Answer not sent. Check your Party and try again." end
        Player.Draw()
    end
end

function Player.Primary()
    local model = Player.model
    if not model then return end
    if model.activeMatch then act("RequestSync");Player.Show();return end
    if model.hostStep then
        act(model.hostStep.console and "Console" or "Advance")
        return
    end
    local state = model.state
    if restricted() and (state=="invitation" or state=="ready" or state=="accepting" or state=="disconnected") then return end
    if state == "invitation" then
        if model.id then Player.opened[model.id] = true end
        act("Join")
    elseif state == "ready" then
        if not model.ready and not model.readyPending and ((model.remaining or 0) <= 0 or (remaining(model) or 0) > 0) then act("Ready") end
    elseif state == "accepting" then act("RetryAnswer")
    elseif state == "disconnected" then act("RequestSync")
    elseif state == "finished" or state == "stopped" then act("ShowHistory")
    end
    if Player.frame and Player.frame:IsShown() then Player.Draw() end
end

function Player.Secondary()
    local model = Player.model
    if not model then return end
    if model.handlers then act("Console"); return end
    local state = model.state
    if state == "invitation" or state == "finished" or state == "stopped" or state == "history" then
        if model.id then Player.dismissed[model.id] = true end
        if state == "invitation" then act("Decline") end
        close()
        Player.RefreshRestore()
    else
        Player.Hide()
    end
end

function Player.Leave()
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs.LOREFORGE_LEAVE_GAME = {
            text = "Leave this game? Your points so far stay on the board.", button1 = "Leave", button2 = "Stay",
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            OnAccept = function() Player.ConfirmLeave() end,
        }
        StaticPopup_Show("LOREFORGE_LEAVE_GAME")
        return
    end
    Player.ConfirmLeave()
end

function Player.ConfirmLeave()
    local model = Player.model
    if model and model.id then Player.dismissed[model.id] = true end
    act("Leave")
    close()
    Player.RefreshRestore()
end
