local _, ns = ...
local P = { declined = {}, logs = {} }
ns.Party = P
local MAX_HISTORY = 20
local function declined(id)
    P.declinedOrder=P.declinedOrder or {}
    if not P.declined[id] then P.declinedOrder[#P.declinedOrder+1]=id end
    P.declined[id]=true
    while #P.declinedOrder>32 do P.declined[table.remove(P.declinedOrder,1)]=nil end
end
local function now() return GetTime() end
local function stamp() return GetServerTime and GetServerTime() or time and time() or math.floor(now()) end
local function clean(s) return tostring(s or ""):gsub("|", ""):gsub("[%z\001-\031]", " ") end
local function integer(n, low, high) return type(n) == "number" and n == math.floor(n) and n >= low and n <= high end
local function me() return ns.Person("player") end
local rosterAt,rosterCache
local function roster()
    if rosterAt==now() then return rosterCache end
    local rows, err, localOnly = ns.Roster("PARTY", true)
    local out = {}
    if not err and not localOnly then for _, row in ipairs(rows) do out[row.key] = row end end
    rosterAt,rosterCache=now(),out
    return out
end
local function context()
    if ns.era ~= "retail" or ns.Transport.Blocked() or not me() then return false end
    if IsInInstance then
        local inside, kind = IsInInstance()
        if inside and kind ~= "party" then return false end
    end
    local r, count = roster(), 0
    for _ in pairs(r) do count = count + 1 end
    return count > 1 and r[me().key]~=nil
end
P.Available = function() return context() and P.bus and P.bus.transport.available == true end
local function log(text)
    P.logs[#P.logs + 1] = text
    if #P.logs > 100 then table.remove(P.logs, 1) end
end
local function render(model)
    P.model = model
    if P.viewHistory and ns.Player and ns.Player.RefreshRestore then ns.Player.RefreshRestore() end
    if ns.Player and ns.Player.Render and not P.viewHistory then
        local ok, err = pcall(ns.Player.Render, model)
        if not ok then
            local changed = P.renderError ~= tostring(err)
            P.renderError = tostring(err)
            if changed then
                log("Player window failed: " .. P.renderError)
                ns.HammerCore.Print("The Party window could not open. Use /lf debug to copy the error; you can still answer in Party chat.")
            end
            return false
        end
        P.renderError = nil
    end
    return ns.Player ~= nil
end
local function history()
    ns.db.matches = type(ns.db.matches) == "table" and ns.db.matches or {}
    local h = ns.db.matches[ns.era]
    if type(h) ~= "table" or type(h.order) ~= "table" or type(h.byId) ~= "table" then
        h = {order = {}, byId = {}}; ns.db.matches[ns.era] = h
    end
    return h
end
local function config(source)
    local cats = {}
    for _, cat in ipairs(ns.Game.CATEGORIES) do if source.categories and source.categories[cat[1]] then cats[#cats + 1] = cat[2] end end
    return {rounds = source.rounds, perRound = source.perRound, seconds = source.seconds,
        difficulty = source.difficulty or "mixed", categories = table.concat(cats, ", "), readyCheck = source.readyCheck ~= false, readySeconds = source.readySeconds or 30}
end
local function validConfig(c)
    return type(c) == "table" and integer(c.rounds, 1, 20) and integer(c.perRound, 1, 50)
        and integer(c.seconds, 5, 120) and type(c.categories) == "string" and #c.categories <= 512
        and (c.difficulty == "mixed" or c.difficulty == "easy" or c.difficulty == "hard") and type(c.readyCheck) == "boolean"
        and (c.readySeconds == nil or integer(c.readySeconds, 5, 60))
end
local function validRows(rows)
    if type(rows) ~= "table" or #rows > 5 then return false end
    local keys = {}
    for _, row in ipairs(rows) do
        if type(row) ~= "table" or type(row.key) ~= "string" or #row.key > 120 or keys[row.key]
            or type(row.name) ~= "string" or #row.name > 120 then return false end
        keys[row.key] = true
        for _, field in ipairs({"total", "round", "streak", "bestStreak", "answered", "rank"}) do
            if not integer(row[field], 0, 1000) then return false end
        end
        row.name = clean(row.name)
    end
    return true
end
local function rows(g)
    local out = {}
    if not g or not g.config then
        for key, person in pairs(roster()) do
            out[#out + 1] = {key = key, name = clean(person.name), total = 0, round = 0, streak = 0, bestStreak = 0, answered = 0, rank = 0, ready = false}
        end
    else
        for _, player in ipairs(g:Standings(false)) do
            out[#out + 1] = {key = player.key, name = clean(player.name), total = player.total, round = player.round,
                streak = player.streak, bestStreak = player.bestStreak, answered = player.answered, rank = 0, ready = player.ready == true}
        end
        if #out == 0 and g.phase ~= "finished" and g.phase ~= "revealing" and g.phase ~= "between" then
            for key, player in pairs(g.players) do
                out[#out + 1] = {key = key, name = clean(player.name), total = 0, round = 0, streak = 0, bestStreak = 0, answered = 0, rank = 0, ready = player.ready == true}
            end
        end
    end
    table.sort(out, function(a, b) if a.total ~= b.total then return a.total > b.total end; return a.key < b.key end)
    local rank, previous = 0, nil
    for i, row in ipairs(out) do
        if row.total ~= previous then rank = i; previous = row.total end
        row.rank, row.winner = rank, row.total > 0 and rank == 1
        row.inAddon = P.host and P.host.joined[row.key] ~= nil or false
    end
    return out
end
local function targets()
    local out = {}
    if P.host then for key in pairs(P.host.joined) do if roster()[key] then out[key] = true end end end
    return out
end
local function send(kind, id, to, body, priority, replace)
    body = body or {}; body.wireCodec = ns.WireCodec.Available() and 2 or nil; body.v, body.kind, body.id, body.to = 1, kind, id, to
    local expected = to == "*" and targets() or {[to] = true}
    if kind == "invite" then expected = {} end
    if kind=="result" then
        for packet,item in pairs(P.bus.outgoing) do
            if item.appKind==kind and item.appId==id and (item.appTo==to or item.appTo=="*" or to=="*") then return packet end
        end
    end
    local packet,why=P.bus.Send(body, expected, priority, replace)
    if packet and P.bus.outgoing[packet] then
        local item=P.bus.outgoing[packet]
        item.appKind,item.appId,item.appTo=kind,id,to
    end
    return packet,why
end
local phases = {preparing=true,lobby=true, ready=true, announcing=true, presenting=true, accepting=true, revealing=true, between=true, paused=true, finished=true, stopped=true}
local function supportsEarly(h)
    if not h or not next(h.joined) then return false end
    for key in pairs(h.joined) do if not (h.early and h.early[key]) then return false end end
    return true
end
local function earlyQuestions(h)
    local mode=h and h.questionMode
    return mode and mode.index==ns.game.index and mode.attempt==ns.game.attempt and mode.early
end
local function snapshot()
    local h, g = P.host, ns.game
    local state = h.started and g.phase or "lobby"
    if state == "ready_announcing" then state = "ready" elseif state == "opening" then state = "presenting" end
    if state == "announcing" and h.preparation and earlyQuestions(h) and not g.questionVisible then state="preparing" end
    local m = {state = state, host = clean(me().name), config = h.config, index = g.index or 0, round = g.round or 0,
        attempt = g.attempt or 0, totalQuestions = h.config.rounds * h.config.perRound, rows = rows(h.started and g or nil),
        status = state == "lobby" and "The host is setting up the game." or g.reason or "", remaining = math.floor(math.max(0, (g.deadline or g.readyDeadline or now()) - now()) * 1000)}
    -- Between questions, players see a countdown with auto-advance, or that
    -- the host starts the next one. Older clients ignore both fields.
    if state == "between" and g.config then
        m.hostPaced = not g.config.autoMode
        if g.config.autoMode and g.nextQuestionAt then m.nextIn = math.floor(math.max(0, g.nextQuestionAt - now()) * 1000) end
    end
    if state == "preparing" or (state == "announcing" and g.questionVisible) or state == "presenting" or state == "accepting" or state == "revealing" or state == "between" or state == "finished" then
        local item = g.run and g.run[g.index]
        if item then
            m.question, m.choices = clean(item.text), {}
            for i = 1, 4 do m.choices[i] = clean(item.choices[i]) end
            if state == "revealing" or state == "between" or state == "finished" then
                m.correct, m.correctText = item.correct, clean(item.choices[item.correct])
                m.counts = {0,0,0,0}
                for _, answer in pairs(g.answers) do m.counts[answer] = m.counts[answer] + 1 end
            end
        end
    end
    if state=="preparing" then m.firstLine=h.preparation.firstLine end
    if state=="lobby" then m.index,m.round,m.attempt=0,0,0 end
    return m
end
local function broadcast(kind, to)
    local h = P.host
    if not h then return end
    local revision = h.gate and not h.gate.preloaded and ns.game.phase == "presenting" and h.gate.revision
    if not revision then h.seq = h.seq + 1; revision = h.seq end
    local m = snapshot(); m.seq = revision
    local prep=h.preparation
    if prep and prep.index==ns.game.index and prep.attempt==ns.game.attempt then m.preparationRevision=prep.revision or revision end
    send(kind or "snapshot", h.id, to or "*", m, 2, "snapshot:" .. (to or "*"))
    return h.seq
end
local function showPrepared(c, index, attempt, revision)
    local m=c and c.model
    if not m or m.index~=index or m.attempt~=attempt or m.preparationRevision~=revision or not m.question
        or (m.state~="preparing" and m.state~="announcing") then return false end
    m.state="announcing"
    c.shownRevision=revision
    if render(m) then send("presented",c.id,c.hostKey,{index=index,attempt=attempt,revision=revision},1) end
    return true
end
function P.Chat(text, sender, channel)
    local c=P.client
    if not c or not c.joined or channel~="PARTY" or ns.Identity(sender)~=c.hostKey or not context() then return end
    if c.model.state=="preparing" and text==c.model.firstLine then
        showPrepared(c,c.model.index,c.model.attempt,c.model.preparationRevision)
    end
end
-- Prime the question while it is hidden on both screens. Only the first
-- public chat echo may reveal it; answer/scoring gates remain independent.
function P.PrepareQuestion()
    local h,g=P.host,ns.game
    if not h or not h.started or g.phase~="announcing" then return end
    if not h.questionMode or h.questionMode.index~=g.index or h.questionMode.attempt~=g.attempt then
        h.questionMode={index=g.index,attempt=g.attempt,early=supportsEarly(h)}
    end
    if not earlyQuestions(h) then return end
    local prep=h.preparation
    if not prep or prep.index~=g.index or prep.attempt~=g.attempt then
        prep={index=g.index,attempt=g.attempt,pending=targets(),shown={},deadline=now()+12,firstLine=g.queue[g.questionCursor]}
        h.preparation=prep
        prep.revision=broadcast()
    end
end
-- This callback is read-only: getters and secure button refreshes cannot
-- transmit data or reset the preparation deadline.
function P.CanPostQuestion()
    local h,g=P.host,ns.game
    if not h or not h.started or g.phase~="announcing" or not earlyQuestions(h) then return true end
    if g.cursor~=g.questionCursor or g.questionVisible then return true end
    local prep=h.preparation
    if not prep or prep.index~=g.index or prep.attempt~=g.attempt then return false end
    if now()>=prep.deadline then return true end
    for key in pairs(prep.pending) do if h.joined[key] and roster()[key] then return false end end
    return true
end
local function apply(m)
    local c = P.client
    if not c or not phases[m.state] or not validConfig(m.config) or not validRows(m.rows)
        or not integer(m.seq, 1, 1000000000) or m.seq < (c.seq or 0) or (m.seq == (c.seq or 0) and not (
            ((m.state=="presenting" or m.state=="preparing") and (c.model.state==m.state or c.model.state=="disconnected"))
            or (m.state=="announcing" and c.model.state=="preparing")))
        or not integer(m.index, 0, 1000) or not integer(m.attempt, 0, 10000)
        or not integer(m.round, 0, 20) or not integer(m.remaining, 0, 120000) then return end
    if (m.state == "preparing" or m.state == "presenting" or m.state == "accepting" or m.state == "revealing" or m.state == "between") and not m.question then return end
    if m.preparationRevision~=nil and not integer(m.preparationRevision,1,1000000000) then return end
    if m.state=="preparing" and (not m.preparationRevision or type(m.firstLine)~="string" or #m.firstLine>240) then return end
    if m.question then
        if type(m.question) ~= "string" or #m.question > 4096 or type(m.choices) ~= "table" or #m.choices ~= 4 then return end
        for i = 1, 4 do if type(m.choices[i]) ~= "string" or #m.choices[i] > 2048 then return end; m.choices[i] = clean(m.choices[i]) end
        m.question = clean(m.question)
    end
    if m.correct and (not integer(m.correct, 1, 4) or (m.state ~= "revealing" and m.state ~= "between" and m.state ~= "finished")) then return end
    if c.model and c.model.index == m.index and c.model.attempt == m.attempt then
        m.selected, m.locked, m.pending, m.answerStatus = c.model.selected, c.model.locked, c.model.pending, c.model.answerStatus
    end
    if type(m.status)~="string" or #m.status>512 then return end
    if m.nextIn~=nil and not integer(m.nextIn,0,120000) then return end
    if m.hostPaced~=nil and type(m.hostPaced)~="boolean" then return end
    m.status=clean(m.status);m.config.categories=clean(m.config.categories)
    if m.correctText~=nil then
        if type(m.correctText)~="string" or #m.correctText>2048 or not m.correct then return end
        m.correctText=clean(m.correctText)
    end
    if m.counts~=nil then
        if type(m.counts)~="table" or #m.counts~=4 or not m.correct then return end
        for i=1,4 do if not integer(m.counts[i],0,5) then return end end
    end
    c.seq, c.lastSeen = m.seq, now()
    if m.state=="stopped" and type(ns.db.pendingMatches)=="table" then ns.db.pendingMatches[c.id]=nil end
    m.id, m.host, m.me, m.joined = c.id, c.hostName, me().key, true
    m.deadline = now() + m.remaining / 1000
    m.nextAt = m.nextIn and (now() + m.nextIn / 1000) or nil
    m.resultsPending = m.state=="finished" and not history().byId[c.id] or false
    for _, row in ipairs(m.rows) do if row.key == m.me then m.ready = row.ready == true end end
    if m.state=="ready" and not m.ready and c.model.state=="ready" and c.model.index==m.index and c.model.attempt==m.attempt then
        m.readyPending,m.readyStatus=c.model.readyPending,c.model.readyStatus
    else c.readyAt=nil end
    if c.pendingShow and ((m.preparationRevision and c.pendingShow.revision<m.preparationRevision) or m.state=="finished" or m.state=="stopped") then c.pendingShow=nil end
    c.model = m
    if render(m) and m.question then
        if m.state=="preparing" then
            send("prepared",c.id,c.hostKey,{index=m.index,attempt=m.attempt,revision=m.preparationRevision},1)
            local show=c.pendingShow
            if (show and show.index==m.index and show.attempt==m.attempt and show.revision==m.preparationRevision) or c.shownRevision==m.preparationRevision then
                c.pendingShow=nil;showPrepared(c,m.index,m.attempt,m.preparationRevision)
            end
        elseif m.state=="presenting" or (m.state=="announcing" and m.preparationRevision) then
            send("presented", c.id, c.hostKey, {index = m.index, attempt = m.attempt, revision = m.preparationRevision or m.seq}, 1)
        end
    end
    return true
end
local function store(result, allowed)
    if type(result) ~= "table" or result.version ~= 1 or type(result.id) ~= "string" or #result.id > 180
        or type(result.host) ~= "string" or #result.host > 120 or not validConfig(result.config)
        or not validRows(result.rows) or not integer(result.totalQuestions,1,1000)
        or result.totalQuestions~=result.config.rounds*result.config.perRound or not integer(result.date, 0, 1000000000000)
        or type(result.rounds) ~= "table" or #result.rounds > 20 then return false end
    for _, round in ipairs(result.rounds) do
        if type(round) ~= "table" or not integer(round.round, 1, 20) or type(round.rows) ~= "table" or #round.rows > 5 then return false end
        for _, row in ipairs(round.rows) do
            if type(row) ~= "table" or type(row.key) ~= "string" or #row.key > 120 then return false end
            for _, field in ipairs({"round","total","rank","streak","bestStreak","answered"}) do if not integer(row[field],0,1000) then return false end end
        end
    end
    local text = ns.Codec.Encode(result)
    if not text then return false end
    local db = history()
    local old = db.byId[result.id]
    if old then
        if old.text ~= text then log("Conflicting completed match ignored"); return false end
        return true
    end
    db.byId[result.id] = {text = text, allowed = allowed or {}}
    db.order[#db.order + 1] = result.id
    while #db.order > MAX_HISTORY do db.byId[table.remove(db.order, 1)] = nil end
    return true
end
function P.GameEvent(event)
    local h, g = P.host, ns.game
    if not h or not h.started or h.serial ~= g.serial then return end
    if event == "question_queued" then P.PrepareQuestion();return end
    if event == "question_shown" then
        local prep=h.preparation
        if prep and prep.index==g.index and prep.attempt==g.attempt and earlyQuestions(h) then
            send("show",h.id,"*",{index=g.index,attempt=g.attempt,revision=prep.revision},1,"show")
        end
        return
    end
    if event == "reveal" and g.index % g.config.perRound == 0 then
        local roundRows = rows(g)
        table.sort(roundRows,function(a,b) if a.round~=b.round then return a.round>b.round end;return a.key<b.key end)
        local best,rank=nil,0
        local compact={}
        for i,row in ipairs(roundRows) do
            if row.round~=best then rank=i;best=row.round end
            compact[i]={key=row.key,round=row.round,total=row.total,rank=rank,streak=row.streak,bestStreak=row.bestStreak,answered=row.answered}
        end
        h.rounds[#h.rounds + 1] = {round = g.round, rows = compact}
    elseif event == "recorded" then
        local result = {version = 1, id = h.id, host = clean(me().name), date = stamp(), config = h.config, rows = rows(g), rounds = h.rounds,
            totalQuestions = #g.run}
        local allowed={}
        for key in pairs(h.allowed) do allowed[key]=true end
        if store(result, allowed) then
            h.result = result
            h.stored = {}
            send("result", h.id, "*", {result = result}, 3, "result")
        end
    end
    h.dirty = true
end
function P.OpenLobby()
    if not P.Available() or ns.db.channel ~= "PARTY" or ns.game:Active() then
        ns.HammerCore.Print("Party lobbies need a Retail home Party without combat or activity restrictions."); return false
    end
    if P.client and P.client.model.state ~= "finished" and P.client.model.state ~= "stopped" then
        ns.HammerCore.Print("Leave the Party game you joined before hosting."); return false
    end
    if not P.host or P.host.started then
        ns.db.partySerial = (tonumber(ns.db.partySerial) or 0) + 1
        P.host = {id = me().key .. ":" .. stamp() .. ":" .. ns.db.partySerial .. ":" .. math.random(0, 0xffffff),
            config = config(ns.db), joined = {}, allowed = {}, seq = 0, rounds = {}, locks = {}, expires=now()+600}
    end
    P.host.config, P.host.lastInvite = config(ns.db), now()
    send("invite", P.host.id, "*", {config = P.host.config}, 2, "invite")
    ns.HammerCore.Print("Party invited. Start the game when everyone has joined; others can still answer in chat.")
    ns.RefreshHost()
    return true
end
function P.KeepLobbyOpen()
    local h=P.host
    if h and not h.started then h.expires,h.warned=now()+600,nil end
end
function P.CloseLobby()
    local h=P.host
    if not h or h.started then return end
    P.bus.Cancel()
    send("ended",h.id,"*",{reason="The host closed the lobby."},1)
    P.host=nil
    ns.RefreshHost()
end
function P.HostStarted()
    local h = P.host
    if not h or h.started or ns.game.config.channel ~= "PARTY" then
        if h then send("ended",h.id,"*",{reason="The host started a different game."},1) end
        P.host = nil; return
    end
    h.started, h.config, h.dirty, h.serial = true, config(ns.db), true, ns.game.serial
    ns.game.presentationGate = next(h.joined) ~= nil
    P.PrepareQuestion()
    if ns.game.phase == "ready" or ns.game.phase == "ready_announcing" then
        h.lastInvite = now()
        send("invite", h.id, "*", {config=h.config}, 2, "invite")
    end
end
function P.Join()
    local c = P.client
    if not c or c.model.state ~= "invitation" or not context() then return end
    c.model.state, c.model.status, c.joinAt, c.joinRetries = "joining", "Waiting for the host to confirm your place.", now(), 0
    send("join", c.id, c.hostKey, {earlyQuestions=true}, 1)
    render(c.model)
end
function P.Decline()
    local c = P.client
    if c then
        declined(c.id)
    end
    P.client = nil
    ns.db.lastParty = nil
    if ns.Player then ns.Player.Hide() end
end
function P.Leave()
    local c = P.client
    if c then
        send("leave", c.id, c.hostKey, {}, 1)
        if type(ns.db.pendingMatches)=="table" then ns.db.pendingMatches[c.id]=nil end
    end
    P.Decline(); ns.db.lastParty = nil
end
function P.Ready()
    local c = P.client
    if not c or not c.joined or c.model.state~="ready" or c.model.ready or c.model.readyPending or not context()
        or ((c.model.remaining or 0)>0 and now()>=c.model.deadline) then return false end
    c.model.readyPending,c.model.readyStatus,c.readyAt=true,nil,now()
    render(c.model)
    local packet,why=send("ready",c.id,c.hostKey,{},1,"ready")
    if not packet then
        c.model.readyPending,c.model.readyStatus=false,"Could not send ready. Try again or type ready in Party chat."
        log("Ready was not queued: "..tostring(why));render(c.model)
    end
    return packet~=nil
end
function P.Answer(choice)
    local c = P.client
    if not c or not c.joined or not integer(choice, 1, 4) or c.model.state ~= "accepting" or c.model.selected or now() >= c.model.deadline or not context() then return false end
    c.model.selected = choice
    return P.RetryAnswer()
end
function P.RetryAnswer()
    local c = P.client
    if not c or not c.joined or not c.model.selected or c.model.locked or c.model.state ~= "accepting" or now() >= c.model.deadline or not context() then return false end
    c.model.pending, c.model.answerStatus, c.answerAt = true, "Sending...", now()
    render(c.model)
    local packet,why=send("answer", c.id, c.hostKey, {index = c.model.index, attempt = c.model.attempt, choice = c.model.selected}, 1)
    if not packet then
        c.model.pending,c.model.answerStatus=false,"Could not send your answer. Retry or use Party chat."
        log("Answer was not queued: "..tostring(why));render(c.model)
    end
    return packet~=nil
end
function P.RequestSync()
    P.viewHistory = false
    local c = P.client
    if c and c.joined then c.syncAt = now(); send("sync", c.id, c.hostKey, {earlyQuestions=true}, 1); render(c.model) end
end
-- Decoded saved Party games, newest first, for the History tab.
function P.SavedResults()
    local db, list = history(), {}
    for i = #db.order, 1, -1 do
        local entry = db.byId[db.order[i]]
        local result = entry and ns.Codec.Decode(entry.text)
        if result then list[#list + 1] = result end
    end
    return list
end
function P.ShowHistory()
    -- The main window's History tab when it can open; the player window's
    -- own list in combat.
    if ns.OpenHost and not (InCombatLockdown and InCombatLockdown()) then
        if ns.Player then ns.Player.Hide() end
        ns.OpenHost("history")
        return
    end
    if not me() then ns.HammerCore.Print("Player identity is unavailable. Try history again later.");return end
    local db, list = history(), {}
    for i = #db.order, 1, -1 do
        local entry = db.byId[db.order[i]]
        local result = entry and ns.Codec.Decode(entry.text)
        if result then
            local row
            for _, player in ipairs(result.rows) do if player.key == me().key then row = player end end
            list[#list + 1] = {id=result.id, host=result.host, date=result.date, rank=row and row.rank or 0, score=row and row.total or 0, totalQuestions=result.totalQuestions}
        end
    end
    P.viewHistory = true
    if ns.Player then ns.Player.Render({state="history",history=list,status="Finished games saved on this client.",activeMatch=P.client and P.client.joined and P.client.model.state~="finished" and P.client.model.state~="stopped" or false}); ns.Player.Show() end
end
function P.OpenHistory(id)
    if not me() then ns.HammerCore.Print("Player identity is unavailable. Try history again later.");return end
    local entry = history().byId[id]
    local result = entry and ns.Codec.Decode(entry.text)
    if not result then return end
    P.viewHistory = true
    if ns.Player then ns.Player.Render({id=id,state="finished",host=result.host,config=result.config,rows=result.rows,me=me().key,
        status=type(result.date)=="number" and date and ("Played "..date("%d %b %H:%M",result.date)) or "",totalQuestions=result.totalQuestions,rounds=result.rounds,
        activeMatch=P.client and P.client.joined and P.client.model.state~="finished" and P.client.model.state~="stopped" or false}); ns.Player.Show() end
end
local function lockFor(key, choice, reason)
    local h, g = P.host, ns.game
    local token=g.index..":"..g.attempt
    if h.lockToken~=token then h.lockToken,h.locks=token,{} end
    local packet=send("lock", h.id, key, {index=g.index, attempt=g.attempt, choice=choice or 0, reason=reason or ""}, 1)
    if packet then h.locks[key]=choice or 0 end
end
function P.Receive(m, sender, person)
    local mine=me()
    person=roster()[sender]
    if not mine or not person then return end
    if type(m) ~= "table" or m.v ~= 1 or type(m.kind) ~= "string" or type(m.id) ~= "string" or #m.id > 180
        or (m.to ~= "*" and m.to ~= mine.key) then return end
    local h, c, g = P.host, P.client, ns.game
    local pending=type(ns.db.pendingMatches)=="table" and ns.db.pendingMatches[m.id]
    if m.kind=="result" and type(pending)=="table" and pending.hostKey==sender then
        if type(m.result)=="table" and m.result.id==m.id and store(m.result) then
            send("stored",m.id,sender,{},1)
            ns.db.pendingMatches[m.id]=nil
            if c and c.id==m.id then
                c.model.state,c.model.rows,c.model.resultsPending="finished",m.result.rows,false
                c.model.rounds=m.result.rounds
                c.model.status="Game complete. Results saved."
                render(c.model)
            end
        end
        return
    end
    if m.kind == "invite" then
        P.invitesReceived = (P.invitesReceived or 0) + 1
        if ns.db.partyInvites == false or not validConfig(m.config) or P.declined[m.id] or (h and (not h.started or g:Active()))
            or (c and c.id ~= m.id and c.model.state ~= "finished" and c.model.state ~= "stopped" and c.model.state ~= "disconnected"
                and not (not c.joined and c.model.state=="invitation" and c.hostKey==sender)) then
            P.inviteStatus = ns.db.partyInvites == false and "Invitations disabled"
                or not validConfig(m.config) and "Invalid invitation settings"
                or P.declined[m.id] and "Already declined" or "Another lobby or match is active"
            return
        end
        if m.id:sub(1,#sender+1) ~= sender..":" then return end
        if c and c.id == m.id and c.hostKey==sender then P.bus.SetPeer(sender,m.id,m.wireCodec==2);c.lastSeen=now();if P.renderError then render(c.model) end;return end
        if c and not c.joined and c.hostKey==sender and c.id~=m.id then declined(c.id) end
        if h and h.started and not g:Active() then P.host=nil end
        P.bus.SetPeer(sender,m.id,m.wireCodec==2)
        P.client = {id=m.id,hostKey=sender,hostName=clean(person.name),seq=0,lastSeen=now(),model={id=m.id,state="invitation",host=clean(person.name),config=m.config,status="Join this Party quiz?"}}
        P.viewHistory=false
        P.client.model.config.categories=clean(P.client.model.config.categories)
        P.inviteStatus = "Invitation received"
        ns.HammerCore.Print(clean(person.name) .. " invited you to a quiz. Use /lf to join or decline.")
        render(P.client.model)
        return
    end
    if h and m.id == h.id then
        local previous=h.allowed[sender]
        local returning=previous and (not previous.guid or not person.guid or previous.guid==person.guid)
        local function negotiate()
            P.bus.SetPeer(sender,m.id,m.wireCodec==2)
            h.early=h.early or {}
            if (h.joined[sender] or returning) and earlyQuestions(h) and m.earlyQuestions~=true and g:Active() then
                g:Pause("A player changed versions. Resume to prepare the question again.")
            end
            h.early[sender]=m.earlyQuestions==true
        end
        if m.kind=="sync" and returning then
            negotiate();h.joined[sender]=person
            local prep=h.preparation
            if earlyQuestions(h) and prep and not g.questionVisible then prep.pending[sender]=true end
        end
        if m.kind == "join" then
            local canJoin = returning or not h.started or g.phase == "ready" or g.phase == "ready_announcing"
            if canJoin then
                negotiate()
                h.joined[sender],h.allowed[sender] = person,person
                broadcast("joined", sender); h.dirty = true
            else send("ended", h.id, sender, {reason="Joining has closed. You can still answer in Party chat."}, 1) end
        elseif h.joined[sender] then
            if m.kind == "leave" then
                h.joined[sender],h.allowed[sender] = nil,nil
                if h.early then h.early[sender]=nil end
                if h.preparation then h.preparation.pending[sender],h.preparation.shown[sender]=nil,nil end
                h.dirty = true
            elseif m.kind == "ready" then g:Answer(sender,"ready",person.guid); h.dirty = true
            elseif m.kind=="prepared" and h.preparation and m.index==h.preparation.index and m.attempt==h.preparation.attempt and m.revision==h.preparation.revision then h.preparation.pending[sender]=nil
            elseif m.kind=="presented" and h.preparation and m.index==h.preparation.index and m.attempt==h.preparation.attempt and m.revision==h.preparation.revision then
                h.preparation.shown[sender]=true
                if h.gate and h.gate.revision==m.revision then h.gate.pending[sender]=nil end
            elseif m.kind == "presented" and h.gate and m.index == h.gate.index and m.attempt == h.gate.attempt and m.revision == h.gate.revision then h.gate.pending[sender] = nil
            elseif m.kind == "answer" and integer(m.choice,1,4) and m.index == g.index and m.attempt == g.attempt then
                local player = g:FindPlayer(sender,person.guid)
                local existing = player and g.answers[player.key]
                if existing then lockFor(sender,existing)
                elseif g:Answer(sender,tostring(m.choice),person.guid) then lockFor(sender,m.choice)
                else lockFor(sender,nil,"Answer not accepted. Use Party chat if the question is still open.") end
            elseif m.kind == "sync" then
                if h.result then send("result",h.id,sender,{result=h.result},3) else broadcast("snapshot",sender) end
            elseif m.kind == "stored" and h.result then h.stored[sender] = true end
        end
    elseif m.kind == "sync" then
        local entry = history().byId[m.id]
        if entry and type(entry.allowed)=="table" and entry.allowed[sender] then
            P.bus.SetPeer(sender,m.id,m.wireCodec==2)
            local result = ns.Codec.Decode(entry.text)
            if result then send("result",m.id,sender,{result=result},3) end
        end
    end
    c = P.client
    if not c or sender ~= c.hostKey or m.id ~= c.id then return end
    P.bus.SetPeer(sender,m.id,m.wireCodec==2)
    c.lastSeen = now()
    if type(ns.db.lastParty)=="table" and ns.db.lastParty.id==c.id then ns.db.lastParty.date=stamp() end
    if m.kind=="show" and c.joined and integer(m.index,1,1000) and integer(m.attempt,0,10000)
        and integer(m.revision,1,1000000000) and m.revision>=(c.model.preparationRevision or 0) then
        if not showPrepared(c,m.index,m.attempt,m.revision) then
            if not c.pendingShow or m.revision>=c.pendingShow.revision then
                c.pendingShow={index=m.index,attempt=m.attempt,revision=m.revision}
            end
        end
    elseif m.kind == "joined" and c.model.state == "joining" then
        if apply(m) then
            c.joined = true
            ns.db.lastParty = {id=c.id,hostKey=c.hostKey,hostName=c.hostName,date=stamp()}
            ns.db.pendingMatches=type(ns.db.pendingMatches)=="table" and ns.db.pendingMatches or {}
            ns.db.pendingMatches[c.id]={hostKey=c.hostKey,hostName=c.hostName,date=stamp()}
            local pendingIds={}
            for id,entry in pairs(ns.db.pendingMatches) do pendingIds[#pendingIds+1]={id=id,date=type(entry)=="table" and tonumber(entry.date) or 0} end
            table.sort(pendingIds,function(a,b)return (a.date or 0)>(b.date or 0)end)
            for i=21,#pendingIds do ns.db.pendingMatches[pendingIds[i].id]=nil end
        end
        if c.joined and c.waitingSnapshot then
            local pending=c.waitingSnapshot;c.waitingSnapshot=nil
            if pending.seq>c.seq then apply(pending) end
        end
    elseif m.kind == "snapshot" and not c.joined and c.model.state=="joining" then
        if integer(m.seq,1,1000000000) and (not c.waitingSnapshot or m.seq>c.waitingSnapshot.seq) then c.waitingSnapshot=m end
    elseif m.kind == "snapshot" and c.joined then apply(m)
    elseif m.kind == "open" and c.joined and m.index==c.model.index and m.attempt==c.model.attempt
        and integer(m.seq,1,1000000000) and m.seq>c.seq and integer(m.remaining,0,120000) then
        if c.model.question then
            c.seq,c.model.state,c.model.deadline=m.seq,"accepting",now()+m.remaining/1000
            c.model.correct,c.model.correctText=nil,nil
            render(c.model)
        else P.RequestSync() end
    elseif m.kind == "clock" and c.joined and m.index == c.model.index and m.attempt == c.model.attempt
        and integer(m.remaining,0,120000) and integer(m.seq,1,1000000000) and m.seq>=c.seq then
        local deadline=now()+m.remaining/1000
        if m.state=="accepting" and c.model.question and (c.model.state=="presenting" or c.model.state=="announcing" or c.model.state=="preparing") then
            c.seq,c.model.state,c.model.deadline=m.seq,"accepting",deadline
            render(c.model)
        elseif c.model.state=="accepting" then c.model.deadline=math.min(c.model.deadline,deadline) end
        c.model.answeredCount = integer(m.count,0,5) and m.count or 0
    elseif m.kind == "lock" and c.joined and m.index == c.model.index and m.attempt == c.model.attempt and integer(m.choice,0,4) then
        c.model.pending = false
        if m.choice > 0 then c.model.locked,c.model.selected,c.model.answerStatus=m.choice,m.choice,"Locked"
        else c.model.answerStatus="Answer not confirmed; use Party chat." end
        render(c.model)
    elseif m.kind == "fallback" and c.joined then c.model.status="Question delivery was delayed. Use Party chat if the buttons are unavailable."; render(c.model)
    elseif m.kind == "ended" then
        if type(ns.db.pendingMatches)=="table" then ns.db.pendingMatches[c.id]=nil end
        c.model.state,c.model.status="stopped",clean(m.reason):sub(1,300);render(c.model)
    elseif m.kind == "result" and c.joined then
        local result = m.result
        if type(result)=="table" and result.id==c.id and store(result) then
            send("stored",c.id,c.hostKey,{},1)
            c.model.state,c.model.rows,c.model.resultsPending="finished",result.rows,false
            c.model.rounds=result.rounds
            c.model.status="Game complete. Results saved."
            render(c.model)
        end
    end
end
function P.Tick()
    if not P.bus then return end
    local available = context()
    if not available then
        ns.game.presentationGate=false
        if P.wasAvailable then
            P.bus.Cancel()
            if P.host and ns.game:Active() and next(P.host.joined) then ns.game:Pause("Party UI paused; end combat or restricted activity, check your Party and resume.") end
            if P.client and P.client.joined then P.client.model.state,P.client.model.status="disconnected","Party UI unavailable. Use Party chat when it is safe.";render(P.client.model) end
        end
        P.wasAvailable = false
        return
    end
    P.wasAvailable = true
    P.bus.Tick()
    if now()-(P.catchupAt or 0)>10 and type(ns.db.pendingMatches)=="table" then
        P.catchupAt=now()
        local ids={}
        for id,entry in pairs(ns.db.pendingMatches) do
            if type(id)=="string" and #id<=180 and type(entry)=="table" and type(entry.hostKey)=="string" and roster()[entry.hostKey]
                and not history().byId[id] and (not P.client or P.client.id~=id or P.client.model.state=="finished"
                    or P.client.model.state=="disconnected" or P.client.model.state=="joining") then ids[#ids+1]=id end
        end
        table.sort(ids)
        if #ids>0 then
            P.catchupIndex=(P.catchupIndex or 0)%#ids+1
            local id=ids[P.catchupIndex]
            send("sync",id,ns.db.pendingMatches[id].hostKey,{},1,"catchup:"..id)
        end
    end
    local h,c,g = P.host,P.client,ns.game
    if h and h.started and h.serial ~= g.serial then P.host=nil;h=nil end
    if h and not h.started and ns.db.channel~="PARTY" then
        P.bus.Cancel()
        send("ended",h.id,"*",{reason="The host moved the game to another channel."},1)
        P.host=nil;h=nil
    end
    if h and not h.started and not h.warned and h.expires-now()<=60 then
        h.warned=true
        ns.HammerCore.Print("The Party lobby closes in a minute. Start the game or keep the lobby open.")
    end
    if h and not h.started and now()>=h.expires then
        send("ended",h.id,"*",{reason="The lobby closed. The host can open another one."},1)
        P.host=nil;h=nil
        ns.HammerCore.Print("The Party lobby closed after 10 minutes without a start.")
        ns.RefreshHost()
    end
    if h then
        if next(h.joined) and not h.result and g.phase~="stopped" and now()-(h.heartbeatAt or 0)>5 then
            h.heartbeatAt=now()
            send("ping",h.id,"*",{},1,"ping")
        end
        for key in pairs(h.joined) do if not roster()[key] then h.joined[key]=nil;h.dirty=true end end
        if not h.started then
            local current = config(ns.db)
            if ns.Codec.Encode(current) ~= ns.Codec.Encode(h.config) then h.config=current;h.dirty=true end
            if now()-(h.lastInvite or 0)>15 then h.lastInvite=now();send("invite",h.id,"*",{config=h.config},2,"invite") end
        else
            if (g.phase=="ready" or g.phase=="ready_announcing") and now()-(h.lastInvite or 0)>15 then
                h.lastInvite=now();send("invite",h.id,"*",{config=h.config},2,"invite")
            end
            g.presentationGate = next(h.joined) ~= nil
            if g.phase=="announcing" then
                P.PrepareQuestion()
                local prep=h.preparation
                if prep then
                    for key in pairs(prep.pending) do if not h.joined[key] or not roster()[key] then prep.pending[key]=nil end end
                    if next(prep.pending) and now()>=prep.deadline and not prep.warned then
                        prep.warned=true
                        ns.HammerCore.Print("Some addon players could not prepare the question. Continuing with Party chat fallback.")
                    end
                end
            end
            if g.phase == "presenting" and (not h.gate or h.gate.index~=g.index or h.gate.attempt~=g.attempt) then
                h.gate={index=g.index,attempt=g.attempt,pending=targets(),deadline=now()+12}
                local prep=h.preparation
                if earlyQuestions(h) and prep and prep.index==g.index and prep.attempt==g.attempt then
                    h.gate.revision,h.gate.preloaded=prep.revision,true
                    for key in pairs(h.gate.pending) do
                        if prep.shown[key] then h.gate.pending[key]=nil
                        elseif prep.pending[key] then
                            -- Re-send a missing payload, not every successful preload.
                            broadcast("snapshot",key)
                        else
                            send("show",h.id,key,{index=g.index,attempt=g.attempt,revision=prep.revision},1,"show:"..key)
                        end
                    end
                else h.gate.revision=broadcast() end
                h.lastPhase="presenting"
            end
            if h.gate and g.phase=="presenting" then
                for key in pairs(h.gate.pending) do if not h.joined[key] then h.gate.pending[key]=nil end end
                if not next(h.gate.pending) or now()>=h.gate.deadline then
                    if next(h.gate.pending) then
                        ns.HammerCore.Print("Some addon players missed the question. They can answer in Party chat.")
                        for key in pairs(h.gate.pending) do send("fallback",h.id,key,{},1) end
                    end
                    h.openToken={index=h.gate.index,attempt=h.gate.attempt}
                    h.gate=nil;g:ReleasePresentation()
                end
            elseif g.phase~="presenting" then h.gate=nil end
            if g.phase=="accepting" then
                if h.openToken and h.openToken.index==g.index and h.openToken.attempt==g.attempt then
                    h.seq=h.seq+1
                    send("open",h.id,"*",{seq=h.seq,index=g.index,attempt=g.attempt,remaining=math.floor(math.max(0,g.deadline-now())*1000)},1,"open")
                    h.openToken=nil
                end
                local count=0
                for _ in pairs(g.answers) do count=count+1 end
                if now()-(h.clockAt or 0)>2 or count~=h.lastCount then
                    h.clockAt,h.lastCount=now(),count
                    send("clock",h.id,"*",{index=g.index,attempt=g.attempt,remaining=math.floor(math.max(0,g.deadline-now())*1000),count=count,seq=h.seq,state="accepting"},1,"clock")
                end
                for key, person in pairs(h.joined) do
                    local player=g:FindPlayer(key,person.guid); local answer=player and g.answers[player.key]
                    local token=g.index..":"..g.attempt
                    if h.lockToken~=token then h.lockToken,h.locks=token,{} end
                    if answer and h.locks[key]~=answer then lockFor(key,answer) end
                end
            end
        end
        local signature=(h.started and g.phase or "lobby")..":"..tostring(g.index)..":"..tostring(g.attempt)..":"..#g:ReadyPlayers()
        if h.dirty or signature~=h.signature then
            -- The initial presentation snapshot owns the exact ACK revision.
            -- Keep changes pending until a normal snapshot can carry them.
            if g.phase~="presenting" and g.phase~="opening" and g.phase~="accepting"
                and not (g.phase=="announcing" and h.preparation and earlyQuestions(h)) then
                h.dirty,h.signature=false,signature
                broadcast()
            end
            if not h.started then ns.RefreshHost() end
        end
    end
    if c and c.joined then
        if not roster()[c.hostKey] and c.model.state~="finished" then
            c.model.state,c.model.status="disconnected","The host left your Party."
        end
        if c.model.state=="ready" and c.model.readyPending and now()-(c.readyAt or now())>5 then
            c.model.readyPending,c.model.readyStatus=false,"Ready not confirmed. Try again or type ready in Party chat."
            render(c.model)
        end
        if c.model.pending and now()-(c.answerAt or now())>5 then c.model.pending=false;c.model.answerStatus="Answer not confirmed; retry or use Party chat.";render(c.model) end
        if now()-c.lastSeen>30 and c.model.state~="finished" and c.model.state~="stopped" then
            c.model.state,c.model.status="disconnected","The host is unavailable. Use Party chat.";render(c.model)
        end
        if (not c.syncAt or now()-c.syncAt>10) and (c.model.state=="disconnected" or c.model.state=="joining" or c.model.resultsPending) then P.RequestSync() end
        if not P.viewHistory and ns.Player and now()-(P.lastDraw or 0)>=1 then
            P.lastDraw=now();render(c.model)
        end
    elseif c and c.model.state=="invitation" and now()-c.lastSeen>45 then
        c.model.state,c.model.status="stopped","This invitation expired. Wait for a new lobby."
        render(c.model)
    elseif c and c.model.state=="joining" and now()-(c.joinAt or now())>5 then
        if (c.joinRetries or 0)<2 then c.joinAt,c.joinRetries=now(),(c.joinRetries or 0)+1;send("join",c.id,c.hostKey,{earlyQuestions=true},1)
        else c.model.state,c.model.status="disconnected","Join was not confirmed. You can use Party chat.";render(c.model) end
    end
end
-- Runtime diagnostics stay on the client; no raw packet or answer content.
function P.Report()
    local t = P.bus and P.bus.transport
    local count = 0
    for _ in pairs(roster()) do count = count + 1 end
    local shown = ns.Player and ns.Player.frame and ns.Player.frame:IsShown() or false
    local inside, kind = false, "none"
    if IsInInstance then inside, kind = IsInInstance() end
    local lines = {
        "Party player diagnostics",
        "Available: " .. tostring(P.Available() == true) .. "; roster=" .. count .. "; instance=" .. tostring(inside) .. "/" .. tostring(kind)
            .. "; blocked=" .. tostring(ns.Transport.Blocked()),
        "Transport: " .. tostring(t and t.available) .. "; ChatThrottleLib=" .. tostring(ChatThrottleLib and ChatThrottleLib.version)
            .. "; prefix=" .. tostring(t and t.PREFIX),
        "Remote Party prefix events: " .. (P.wireReceived or 0) .. "; accepted frames=" .. (t and t.decodes or 0)
            .. "; send attempts=" .. (t and t.attempts or 0),
        "Invite messages: " .. (P.invitesReceived or 0) .. "; enabled=" .. tostring(ns.db.partyInvites ~= false)
            .. "; last invite status=" .. (P.inviteStatus or "None received"),
        "Lobby: " .. (P.host and (P.host.started and "Started" or "Open") or "None")
            .. "; player=" .. (P.client and P.client.model.state or "None") .. "; window=" .. tostring(shown),
        "Player error: " .. (P.renderError or "None"),
        "Recent Party log:",
    }
    for i = math.max(1, #P.logs - 14), #P.logs do lines[#lines + 1] = P.logs[i] end
    return table.concat(lines, "\n")
end
function P.Initialise()
    history()
    P.bus=ns.PartyBus.New(P.Receive,roster,context,log,function(message,sender)
        if message.to~=me().key and message.to~="*" then return false,false end
        if message.to==me().key then return true,true end
        if message.kind=="invite" then return true,false end
        local offered=P.client
        if message.kind=="ended" and offered and offered.id==message.id and offered.hostKey==sender then return true,offered.joined==true end
        local pending=type(ns.db.pendingMatches)=="table" and ns.db.pendingMatches[message.id]
        if message.kind=="result" and type(pending)=="table" and pending.hostKey==sender then return true,true end
        local client=P.client
        local joined=client and (client.joined or client.model.state=="joining") and client.hostKey==sender and client.id==message.id
        return joined,joined
    end)
    ns.game.onEvent=P.GameEvent
    ns.game.firstLineReady=P.CanPostQuestion
    local frame=CreateFrame("Frame");P.frame=frame
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:SetScript("OnEvent",function(_,event,...)
        if event=="CHAT_MSG_ADDON" then
            local prefix, _, _, sender = ...
            local mine = me()
            if mine and not (issecretvalue and (issecretvalue(prefix) or issecretvalue(sender)))
                and prefix == P.bus.transport.PREFIX and ns.Identity(sender) ~= mine.key then
                P.wireReceived=(P.wireReceived or 0)+1
            end
            P.bus.transport.Receive(...)
        else rosterAt=nil end
    end)
    local elapsed=0
    frame:SetScript("OnUpdate",function(_,delta) elapsed=elapsed+delta;if elapsed>=0.1 then elapsed=0;P.Tick() end end)
    local last=ns.db.lastParty
    if type(last)=="table" and type(last.id)=="string" and type(last.hostKey)=="string" and integer(last.date,0,1000000000000)
        and stamp()-last.date<3600 and roster()[last.hostKey] then
        P.client={id=last.id,hostKey=last.hostKey,hostName=clean(last.hostName),joined=true,seq=0,lastSeen=now(),syncAt=now(),
            model={id=last.id,state="joining",host=clean(last.hostName),status="Reconnecting to your Party game.",joined=true}}
        P.RequestSync()
    end
end
ns.HammerCore.Commands:Add({name="play",section="Trivia",help="Return to the Party game you joined",run=function() if P.client then P.viewHistory=false;render(P.client.model);if ns.Player then ns.Player.Show() end else ns.HammerCore.Print("You haven't joined a Party game.") end end})
ns.HammerCore.Commands:Add({name="history",section="Trivia",help="View your game history",run=function() P.ShowHistory() end})
ns.HammerCore.Commands:Add({name="leave",section="Trivia",help="Leave the Party game you joined",run=P.Leave})
