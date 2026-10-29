local _, ns = ...

-- Pure game rules. The adapter supplies identities, time and chat echoes.
local Game = {}
Game.__index = Game
ns.Game = Game

Game.CHANNELS = {
    PARTY = { label = "Party", macro = "/p " },
    RAID = { label = "Raid", macro = "/raid " },
    INSTANCE_CHAT = { label = "Instance", macro = "/i " },
    GUILD = { label = "Guild", macro = "/g " },
}

Game.CATEGORIES = {
    { "lore", "General lore" }, { "geography", "Geography" },
    { "class", "Classes and mechanics" }, { "race", "Races" },
    { "hallowsend", "Hallow's End" }, { "bossquotes", "Boss quotes" },
    { "lastwords", "Famous Last Words" },
    { "murlocs", "Murlocs and Mischief" }, { "goblins", "Dubious Goblin Engineering" },
    { "items", "Things You Probably Vendored" },
}

local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end

function Game.Categories(entry)
    if entry.categories then return entry.categories end
    if entry.class then return { "class" } end
    if entry.race then return { "race" } end
    if entry[1]:find("zone", 1, true) or entry[1]:find("lies", 1, true) then return { "geography" } end
    return { "lore" }
end

function Game.Pool(bank, config, era)
    local pool = {}
    for _, entry in ipairs(bank) do
        local client = entry.era or "both"
        local difficulty = entry.difficulty or "easy"
        local category = false
        for _, tag in ipairs(Game.Categories(entry)) do
            if config.categories[tag] then category = true end
        end
        if (client == "both" or client == era) and category
            and (config.difficulty == "mixed" or config.difficulty == difficulty) then
            pool[#pool + 1] = entry
        end
    end
    return pool
end

-- Each line fits a conservative chat budget including its prefix. Never split
-- a UTF-8 sequence; all shipped questions are validated before packaging.
function Game.Messages(text, prefix)
    local budget = 240 - #prefix
    assert(budget >= 40, "chat prefix too long")
    local lines = {}
    while #text > budget do
        local cut = budget
        while cut > 0 do
            local nextByte = text:byte(cut + 1)
            if not nextByte or nextByte < 128 or nextByte >= 192 then break end
            cut = cut - 1
        end
        local space = text:sub(1, cut):match(".*() ")
        if space and space > budget / 2 then cut = space - 1 end
        lines[#lines + 1] = prefix .. text:sub(1, cut)
        text = text:sub(cut + 1):gsub("^ +", "")
    end
    if text ~= "" then lines[#lines + 1] = prefix .. text end
    return lines
end

function Game.New(bank, clock, random, records)
    return setmetatable({ bank = bank, clock = clock, random = random or math.random,
        records = records or {}, phase = "setup", queue = {}, cursor = 1, players = {} }, Game)
end

function Game:Active()
    return self.phase ~= "setup" and self.phase ~= "finished" and self.phase ~= "stopped"
end

function Game:Enqueue(text)
    local prefix = "[Loreforge #" .. self.serial .. "] "
    for _, line in ipairs(Game.Messages(text, prefix)) do self.queue[#self.queue + 1] = line end
end

function Game:Start(config, era, roster, serial)
    if self:Active() then return nil, "Finish or stop the current game first." end
    if type(config) ~= "table" or not integer(config.rounds, 1, 20)
        or not integer(config.perRound, 1, 50) or not integer(config.seconds, 5, 120)
        or not Game.CHANNELS[config.channel]
        or (config.autoMode ~= nil and type(config.autoMode) ~= "boolean")
        or (config.questionGap ~= nil and not integer(config.questionGap, 3, 30))
        or (config.idleLimit ~= nil and not integer(config.idleLimit, 0, 10))
        or (config.readyCheck ~= nil and type(config.readyCheck) ~= "boolean")
        or (config.readySeconds ~= nil and not integer(config.readySeconds, 5, 60))
        or (config.hostParticipates ~= nil and type(config.hostParticipates) ~= "boolean")
        or (config.difficulty ~= "mixed" and config.difficulty ~= "easy" and config.difficulty ~= "hard")
        or type(config.categories) ~= "table" then return nil, "Check the game settings." end
    local pool = Game.Pool(self.bank, config, era)
    local count = config.rounds * config.perRound
    if #pool < count then return nil, "Only " .. #pool .. " questions match; this game needs " .. count .. "." end
    local players = {}
    for _, person in ipairs(roster) do
        if person.key and person.name and not players[person.key] then
            players[person.key] = { key = person.key, name = person.name, guid = person.guid,
                total = 0, round = 0, answered = 0, streak = 0, bestStreak = 0 }
        end
    end
    if not next(players) then return nil, "No other eligible players are available." end
    self.config = { rounds = config.rounds, perRound = config.perRound, seconds = config.seconds,
        channel = config.channel, replayRecords = config.replayRecords ~= false,
        autoMode = config.autoMode == true, questionGap = config.questionGap or 5,
        idleLimit = config.idleLimit == nil and 3 or config.idleLimit,
        readyCheck = config.readyCheck ~= false, readySeconds = config.readySeconds or 10,
        hostParticipates = config.hostParticipates == true, localOnly = config.localOnly == true,
        manualSend = config.manualSend == true, compactChoices = config.compactChoices ~= false }
    self.players, self.run, self.serial = players, {}, serial
    self.presentationGate, self.presentationFrom = false, nil
    for _ = 1, count do
        local entry = table.remove(pool, self.random(#pool))
        local choices = { entry[2], entry[3], entry[4], entry[5] }
        for i = 4, 2, -1 do
            local j = self.random(i)
            choices[i], choices[j] = choices[j], choices[i]
        end
        local correct
        for i, choice in ipairs(choices) do if choice == entry[2] then correct = i end end
        self.run[#self.run + 1] = { text = entry[1], choices = choices, correct = correct, id = entry.id }
    end
    self.index, self.round, self.attempt = 1, 1, 1
    self.recorded = false
    self.pendingRecords = nil
    self.nextQuestionAt = nil
    self.emptyQuestions, self.idlePause = 0, nil
    self.readyDeadline = nil
    self.answers, self.deadline, self.reason, self.resumePhase = {}, nil, nil, nil
    self.queue, self.cursor, self.pending = {}, 1, nil
    self.rulesConfirmed = false
    self.rulesText = Game.RulesText(config)
    if self.config.readyCheck then self:ReadyCheck()
    else self:Enqueue(self.rulesText .. " Answer 1-4."); self:Question() end
    return true
end

-- Opening line: game length plus a short category summary, so chat players
-- know what they're in for without a second line.
function Game.RulesText(config)
    local names, total = {}, #Game.CATEGORIES
    for _, category in ipairs(Game.CATEGORIES) do
        if type(config.categories) == "table" and config.categories[category[1]] then names[#names + 1] = category[2] end
    end
    local topics = #names == total and "all categories" or #names > 3 and (#names .. " categories")
        or table.concat(names, ", ")
    return (config.rounds == 1 and "1 round" or (config.rounds .. " rounds")) .. " x " .. config.perRound
        .. (config.perRound == 1 and " question" or " questions") .. (topics ~= "" and (", " .. topics) or "") .. "."
end

function Game:ReadyCheck()
    self.phase, self.afterQueue, self.readyDeadline = "ready_announcing", "ready", nil
    self:Enqueue(self.rulesText .. " Starts in " .. self.config.readySeconds .. "s. Type ready; answer 1-4.")
end

function Game:ReadyPlayers()
    local rows = {}
    for _, player in pairs(self.players) do if player.ready then rows[#rows + 1] = player end end
    table.sort(rows, function(a, b) return a.key < b.key end)
    return rows
end

function Game:AddReadyPlayers(roster)
    if self.phase ~= "ready" and self.phase ~= "ready_announcing"
        and not (self.phase == "paused" and (self.resumePhase == "readyRestart"
            or self.resumePhase == "ready_announcing" or self.resumePhase == "ready")) then return nil end
    local added = 0
    for _, person in ipairs(roster) do
        if person.key and person.name and not self.players[person.key] then
            self.players[person.key] = { key = person.key, name = person.name, guid = person.guid,
                total = 0, round = 0, answered = 0, streak = 0, bestStreak = 0 }
            added = added + 1
        end
    end
    return added
end

function Game:SetAutomatic(enabled)
    if not self:Active() then return false end
    self.config.autoMode = enabled == true
    self.nextQuestionAt = self.phase == "between" and self.config.autoMode
        and (self.clock() + self.config.questionGap) or nil
    return true
end

function Game:FindPlayer(key, guid)
    local player = self.players[key]
    if player then
        if player.guid and guid and player.guid ~= guid then return nil end
        return player
    end
    if guid then
        for _, candidate in pairs(self.players) do
            if candidate.guid == guid then return candidate end
        end
    end
end

function Game:Question()
    local item = self.run[self.index]
    self.answers, self.deadline, self.phase, self.afterQueue = {}, nil, "announcing", "accepting"
    local q = (self.index - 1) % self.config.perRound + 1
    self.questionCursor = #self.queue + 1
    self:Enqueue("Round " .. self.round .. ", question " .. q .. " (" .. self.config.seconds .. "s)"
        .. (self.attempt > 1 and " (restarted)" or "") .. ": " .. item.text)
    -- Compact games post every choice on one line; every shipped question
    -- fits, but anything that would split falls back to one line each.
    local parts = {}
    for i, text in ipairs(item.choices) do parts[i] = i .. ") " .. text end
    local line = table.concat(parts, "   ")
    if self.config.compactChoices and #Game.Messages(line, "[Loreforge #" .. self.serial .. "] ") == 1 then
        self:Enqueue(line)
    else
        for _, text in ipairs(parts) do self:Enqueue(text) end
    end
end

function Game:NextMessage()
    if self.phase == "paused" or self.pending then return nil end
    return self.queue[self.cursor]
end

function Game:Sent()
    local line = self:NextMessage()
    if line then self.pending = { text = line, sentAt = self.clock() } end
end

function Game:Echo(text)
    if self.phase == "paused" or not self.pending or text ~= self.pending.text then return false end
    self.pending, self.cursor = nil, self.cursor + 1
    if self.cursor > #self.queue then
        self.presentationFrom = self.phase
        self.queue, self.cursor, self.phase = {}, 1, self.afterQueue
        if self.phase == "ready" or self.phase == "accepting" then self.rulesConfirmed = true end
        if self.phase == "accepting" and self.presentationGate and self.presentationFrom ~= "opening" then
            self.phase = "presenting"
        elseif self.phase == "accepting" then self.deadline = self.clock() + self.config.seconds end
        self.presentationFrom = nil
        if self.phase == "ready" then self.readyDeadline = self.clock() + self.config.readySeconds end
        if self.phase == "between" and self.config.autoMode then
            self.nextQuestionAt = self.clock() + self.config.questionGap
            if self.idlePause then
                self.idlePause = nil
                self:Pause("No replies for " .. self.emptyQuestions .. " questions. Resume when players are ready.")
            end
        end
        if self.phase == "finished" then self:RecordResults() end
    end
    return true
end

function Game:ReleasePresentation()
    if self.phase ~= "presenting" then return false end
    self.phase, self.afterQueue = "opening", "accepting"
    self:Enqueue("Answers open. Answer 1-4.")
    return true
end

function Game:Answer(key, text, guid)
    if self.phase == "ready" or self.phase == "ready_announcing" then
        local player = self:FindPlayer(key, guid)
        if not player or player.ready
            or (self.readyDeadline and self.clock() >= self.readyDeadline) then return false end
        local reply = text:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("[!.]+$", "")
        if reply ~= "ready" and reply ~= "rdy" and reply ~= "i'm ready" and reply ~= "im ready" and reply ~= "i am ready" then return false end
        player.ready = true
        return true
    end
    if self.phase ~= "accepting" then return false end
    if self.clock() >= self.deadline then self:Close(); return false end
    local player = self:FindPlayer(key, guid)
    if not player then return false end
    key = player.key
    if self.answers[key] then return false end
    local answer = text:match("^%s*([1-4])%s*$")
    if not answer then return false end
    self.answers[key] = tonumber(answer)
    player.entered = true
    return true
end

function Game:Standings(roundOnly)
    local rows = {}
    for _, player in pairs(self.players) do if player.entered then rows[#rows + 1] = player end end
    table.sort(rows, function(a, b)
        local av, bv = roundOnly and a.round or a.total, roundOnly and b.round or b.total
        if av ~= bv then return av > bv end
        return a.key < b.key
    end)
    return rows
end

function Game:Results(roundOnly)
    local rows = self:Standings(roundOnly)
    local best = rows[1] and (roundOnly and rows[1].round or rows[1].total) or 0
    local winners, standings = {}, {}
    for _, player in ipairs(rows) do
        local score = roundOnly and player.round or player.total
        if score == best then winners[#winners + 1] = player.name end
        standings[#standings + 1] = player.name .. " " .. score
    end
    local label = roundOnly and ("Round " .. self.round) or "Final"
    if best == 0 then
        self:Enqueue(label .. ": no correct answers this time.")
    else
        self:Enqueue(label .. (#winners == 1 and " winner: " or " joint winners: ") .. table.concat(winners, ", ") .. " (" .. best .. ").")
    end
    self:Enqueue(label .. " scores: " .. table.concat(standings, "; "))
end

function Game:Close()
    if self.phase ~= "accepting" then return false end
    local item, correct, answered = self.run[self.index], 0, 0
    for key, player in pairs(self.players) do
        local answer = self.answers[key]
        if answer then answered = answered + 1; player.answered = player.answered + 1 end
        if answer == item.correct then
            player.total, player.round, correct = player.total + 1, player.round + 1, correct + 1
            player.streak = player.streak + 1
            player.bestStreak = math.max(player.bestStreak, player.streak)
        else
            player.streak = 0
        end
    end
    self.phase, self.afterQueue, self.deadline = "revealing", "between", nil
    self:Enqueue("Answer: " .. item.correct .. ") " .. item.choices[item.correct] .. ". " .. correct
        .. " correct from " .. answered .. " replies.")
    local correctPlayers = {}
    for _, player in ipairs(self:Standings(false)) do
        if self.answers[player.key] == item.correct then
            local record = self.records[player.key]
            local previousBest = type(record) == "table" and tonumber(record.bestStreak) or 0
            previousBest = previousBest or 0
            local newBest = not player.announcedBest and player.streak >= 2 and player.streak > previousBest
            if newBest then player.announcedBest = true end
            correctPlayers[#correctPlayers + 1] = player.name .. " (" .. player.total
                .. (player.total == 1 and " point" or " points")
                .. (player.streak >= 2 and (", streak " .. player.streak) or "")
                .. (newBest and ", new personal best!" or "") .. ")"
        end
    end
    if #correctPlayers > 0 then self:Enqueue("Correct: " .. table.concat(correctPlayers, "; ") .. ".") end
    self.emptyQuestions = answered == 0 and self.emptyQuestions + 1 or 0
    if self.config.autoMode and self.config.idleLimit > 0 and self.emptyQuestions >= self.config.idleLimit
        and self.index < #self.run then
        self.idlePause = true
        self:Enqueue("No replies for " .. self.emptyQuestions .. " questions; automatic play will pause after these results.")
    end
    -- A one-round game's round result would repeat the final result.
    if self.index % self.config.perRound == 0 and self.config.rounds > 1 then self:Results(true) end
    if self.onEvent then self.onEvent("reveal") end
    if self.index == #self.run then
        self:Results(false)
        self:PrepareRecords()
        self.afterQueue = "finished"
    end
    return true
end

function Game:PrepareRecords()
    local records = {}
    for key, value in pairs(self.records) do
        if type(key) == "string" and type(value) == "table" then
            records[key] = {}
            for field, content in pairs(value) do records[key][field] = content end
        end
    end
    local standings = self:Standings(false)
    local best = standings[1] and standings[1].total or 0
    for place, player in ipairs(standings) do
        local record = records[player.key]
        if type(record) ~= "table" then record = {}; records[player.key] = record end
        local function previous(key)
            local value = record[key]
            return type(value) == "number" and value >= 0 and value < 1000000000 and value or 0
        end
        record.name = player.name
        record.games = previous("games") + 1
        record.correct = previous("correct") + player.total
        record.answered = previous("answered") + player.answered
        record.wins = previous("wins") + ((best > 0 and player.total == best) and 1 or 0)
        record.bestStreak = math.max(previous("bestStreak"), player.bestStreak)
        record.lastGame = self.serial
        -- Only the top three are announced; big channels don't need a line
        -- per player, and the full table stays in the addon.
        if self.config.replayRecords and place <= 3 then
            self:Enqueue(player.name .. ": " .. player.total .. "/" .. #self.run .. " correct, "
                .. player.answered .. " answered, best streak " .. player.bestStreak .. ". Records: "
                .. record.games .. " games, " .. record.wins .. " wins, " .. record.correct
                .. " correct, best streak " .. record.bestStreak .. ".")
        end
    end
    -- Bound saved history, retaining this game's players and the newest records.
    local keys = {}
    for key, record in pairs(records) do
        if type(record) ~= "table" then records[key] = nil
        else keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        local av, bv = tonumber(records[a].lastGame) or 0, tonumber(records[b].lastGame) or 0
        if av == bv then return a < b end
        return av > bv
    end)
    for i = 1001, #keys do records[keys[i]] = nil end
    self.pendingRecords = records
end

function Game:RecordResults()
    if self.recorded or self.phase ~= "finished" or not self.pendingRecords then return end
    self.recorded = true
    for key in pairs(self.records) do self.records[key] = nil end
    for key, value in pairs(self.pendingRecords) do self.records[key] = value end
    self.pendingRecords = nil
    if self.onEvent then self.onEvent("recorded") end
end

function Game:Next()
    if self.phase == "ready" then
        self.readyDeadline = nil
        self:Question()
        return true
    end
    if self.phase ~= "between" then return false end
    self.nextQuestionAt = nil
    self.index, self.attempt = self.index + 1, 1
    local round = math.floor((self.index - 1) / self.config.perRound) + 1
    if round ~= self.round then
        self.round = round
        for _, player in pairs(self.players) do player.round = 0 end
    end
    self:Question()
    return true
end

function Game:Tick()
    if self.phase == "ready" and self.clock() >= self.readyDeadline then self:Next() end
    if self.phase == "accepting" and self.clock() >= self.deadline then self:Close() end
    if self.phase == "between" and self.config.autoMode and self.nextQuestionAt
        and self.clock() >= self.nextQuestionAt then self:Next() end
end

function Game:Pause(reason, preservePending)
    if not self:Active() or self.phase == "paused" then return end
    self.resumePhase, self.reason = self.phase, reason
    if preservePending and self.pending then
        self.phase, self.deadline, self.readyDeadline, self.nextQuestionAt = "paused", nil, nil, nil
        return
    end
    if self.phase == "ready" or self.phase == "ready_announcing" then
        self.resumePhase = "readyRestart"
        self.queue, self.cursor = {}, 1
    elseif self.phase == "accepting" or self.phase == "announcing" or self.phase == "presenting" or self.phase == "opening" then
        self.resumePhase = "question"
        self.queue, self.cursor, self.answers = {}, 1, {}
        self.attempt = self.attempt + 1
    end
    self.phase, self.pending, self.deadline, self.nextQuestionAt = "paused", nil, nil, nil
    self.readyDeadline = nil
end

function Game:Resume()
    if self.phase ~= "paused" then return false end
    self.reason = nil
    self.emptyQuestions = 0
    if not self.rulesConfirmed and self.resumePhase == "question" then
        self:Enqueue(self.rulesText .. " Answer 1-4.")
    end
    if self.resumePhase == "question" then self:Question()
    elseif self.resumePhase == "readyRestart" then self:ReadyCheck()
    else self.phase = self.resumePhase end
    if self.phase == "between" and self.config.autoMode then
        self.nextQuestionAt = self.clock() + self.config.questionGap
    end
    return true
end

function Game:Retry()
    if self.pending and self.clock() - self.pending.sentAt >= 8 then self.pending = nil; return true end
    return false
end

function Game:ConfirmVisible()
    if self.pending and self.clock() - self.pending.sentAt >= 8 then
        if self.phase == "paused" then self.phase, self.reason = self.resumePhase, nil end
        return self:Echo(self.pending.text)
    end
    return false
end

function Game:Stop()
    self.phase, self.queue, self.pending, self.deadline = "stopped", {}, nil, nil
    self.pendingRecords = nil
    self.nextQuestionAt = nil
    self.readyDeadline = nil
    self.reason = "Game stopped. Start a new game when you're ready."
    if self.onEvent then self.onEvent("stopped") end
end
