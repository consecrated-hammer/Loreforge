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
    if IsInInstance then local inside = IsInInstance(); if inside then return false end end
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
        local ok = pcall(ns.Player.Render, model)
        if not ok then log("Player window failed; use Party chat."); return false end
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
        difficulty = source.difficulty or "mixed", categories = table.concat(cats, ", "), readyCheck = source.readyCheck ~= false}
end
local function validConfig(c)
    return type(c) == "table" and integer(c.rounds, 1, 20) and integer(c.perRound, 1, 50)
        and integer(c.seconds, 5, 120) and type(c.categories) == "string" and #c.categories <= 512
        and (c.difficulty == "mixed" or c.difficulty == "easy" or c.difficulty == "hard") and type(c.readyCheck) == "boolean"
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
    body = body or {}; body.v, body.kind, body.id, body.to = 1, kind, id, to
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
local phases = {lobby=true, ready=true, announcing=true, presenting=true, accepting=true, revealing=true, between=true, paused=true, finished=true, stopped=true}
local function snapshot()
    local h, g = P.host, ns.game
    local state = h.started and g.phase or "lobby"
    if state == "ready_announcing" then state = "ready" elseif state == "opening" then state = "presenting" end
    local m = {state = state, host = clean(me().name), config = h.config, index = g.index or 0, round = g.round or 0,
        attempt = g.attempt or 0, totalQuestions = h.config.rounds * h.config.perRound, rows = rows(h.started and g or nil),
        status = state == "lobby" and "The host is setting up the match." or g.reason or "", remaining = math.floor(math.max(0, (g.deadline or g.readyDeadline or now()) - now()) * 1000)}
    if state == "presenting" or state == "accepting" or state == "revealing" or state == "between" or state == "finished" then
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
    if state=="lobby" then m.index,m.round,m.attempt=0,0,0 end
    return m
end
local function broadcast(kind, to)
    local h = P.host
    if not h then return end
    local revision = h.gate and ns.game.phase == "presenting" and h.gate.revision
    if not revision then h.seq = h.seq + 1; revision = h.seq end
    local m = snapshot(); m.seq = revision
    send(kind or "snapshot", h.id, to or "*", m, 2, "snapshot:" .. (to or "*"))
    return h.seq
end
local function apply(m)
    local c = P.client
    if not c or not phases[m.state] or not validConfig(m.config) or not validRows(m.rows)
        or not integer(m.seq, 1, 1000000000) or m.seq < (c.seq or 0) or (m.seq == (c.seq or 0) and (m.state ~= "presenting"
            or (c.model.state ~= "presenting" and c.model.state ~= "disconnected")))
        or not integer(m.index, 0, 1000) or not integer(m.attempt, 0, 10000)
        or not integer(m.round, 0, 20) or not integer(m.remaining, 0, 120000) then return end
    if (m.state == "presenting" or m.state == "accepting" or m.state == "revealing" or m.state == "between") and not m.question then return end
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
    m.resultsPending = m.state=="finished" and not history().byId[c.id] or false
    for _, row in ipairs(m.rows) do if row.key == m.me then m.ready = row.ready == true end end
    c.model = m
    if render(m) and m.state == "presenting" and m.question then
        send("presented", c.id, c.hostKey, {index = m.index, attempt = m.attempt, revision = m.seq}, 1)
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
        ns.HammerCore.Print("Addon joining is available in a Retail Party outside instances and combat."); return false
    end
    if P.client and P.client.model.state ~= "finished" and P.client.model.state ~= "stopped" then
        ns.HammerCore.Print("Leave the joined match before hosting."); return false
    end
    if not P.host or P.host.started then
        ns.db.partySerial = (tonumber(ns.db.partySerial) or 0) + 1
        P.host = {id = me().key .. ":" .. stamp() .. ":" .. ns.db.partySerial .. ":" .. math.random(0, 0xffffff),
            config = config(ns.db), joined = {}, allowed = {}, seq = 0, rounds = {}, locks = {}, expires=now()+600}
    end
    P.host.config, P.host.lastInvite = config(ns.db), now()
    send("invite", P.host.id, "*", {config = P.host.config}, 2, "invite")
    ns.HammerCore.Print("Party invited. Start the match when everyone has joined; others can still answer in chat.")
    ns.RefreshHost()
    return true
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
        if h then send("ended",h.id,"*",{reason="The host changed or started another match."},1) end
        P.host = nil; return
    end
    h.started, h.config, h.dirty, h.serial = true, config(ns.db), true, ns.game.serial
    ns.game.presentationGate = next(h.joined) ~= nil
end
function P.Join()
    local c = P.client
    if not c or c.model.state ~= "invitation" or not context() then return end
    c.model.state, c.model.status, c.joinAt, c.joinRetries = "joining", "Waiting for the host to confirm your place.", now(), 0
    send("join", c.id, c.hostKey, {}, 1)
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
    if c and c.joined and c.model.state == "ready" then send("ready", c.id, c.hostKey, {}, 1) end
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
    send("answer", c.id, c.hostKey, {index = c.model.index, attempt = c.model.attempt, choice = c.model.selected}, 1)
    render(c.model)
    return true
end
function P.RequestSync()
    P.viewHistory = false
    local c = P.client
    if c and c.joined then c.syncAt = now(); send("sync", c.id, c.hostKey, {}, 1); render(c.model) end
end
function P.ShowHistory()
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
    if ns.Player then ns.Player.Render({state="history",history=list,status="Completed matches stored on this client.",activeMatch=P.client and P.client.joined and P.client.model.state~="finished" and P.client.model.state~="stopped" or false}); ns.Player.Show() end
end
function P.OpenHistory(id)
    if not me() then ns.HammerCore.Print("Player identity is unavailable. Try history again later.");return end
    local entry = history().byId[id]
    local result = entry and ns.Codec.Decode(entry.text)
    if not result then return end
    P.viewHistory = true
    if ns.Player then ns.Player.Render({id=id,state="finished",host=result.host,config=result.config,rows=result.rows,me=me().key,
        status="Saved results from "..result.host,totalQuestions=result.totalQuestions,rounds=result.rounds,
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
                c.model.status="Match complete. Results saved on this client."
                render(c.model)
            end
        end
        return
    end
    if m.kind == "invite" then
        if ns.db.partyInvites == false or not validConfig(m.config) or P.declined[m.id] or (h and (not h.started or g:Active()))
            or (c and c.id ~= m.id and c.model.state ~= "finished" and c.model.state ~= "stopped" and c.model.state ~= "disconnected"
                and not (not c.joined and c.model.state=="invitation" and c.hostKey==sender)) then return end
        if c and c.id == m.id then c.lastSeen=now();return end
        if c and not c.joined and c.hostKey==sender and c.id~=m.id then declined(c.id) end
        if m.id:sub(1,#sender+1) ~= sender..":" then return end
        if h and h.started and not g:Active() then P.host=nil end
        P.client = {id=m.id,hostKey=sender,hostName=clean(person.name),seq=0,lastSeen=now(),model={id=m.id,state="invitation",host=clean(person.name),config=m.config,status="Join this Party trivia match?"}}
        P.viewHistory=false
        P.client.model.config.categories=clean(P.client.model.config.categories)
        render(P.client.model)
        return
    end
    if h and m.id == h.id then
        local previous=h.allowed[sender]
        local returning=previous and (not previous.guid or not person.guid or previous.guid==person.guid)
        if m.kind=="sync" and returning then h.joined[sender]=person end
        if m.kind == "join" then
            local canJoin = returning or not h.started or g.phase == "ready" or g.phase == "ready_announcing"
            if canJoin then
                h.joined[sender],h.allowed[sender] = person,person
                broadcast("joined", sender); h.dirty = true
            else send("ended", h.id, sender, {reason="Joining has closed. You can still answer in Party chat."}, 1) end
        elseif h.joined[sender] then
            if m.kind == "leave" then h.joined[sender],h.allowed[sender] = nil,nil; h.dirty = true
            elseif m.kind == "ready" then g:Answer(sender,"ready",person.guid); h.dirty = true
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
            local result = ns.Codec.Decode(entry.text)
            if result then send("result",m.id,sender,{result=result},3) end
        end
    end
    c = P.client
    if not c or sender ~= c.hostKey or m.id ~= c.id then return end
    c.lastSeen = now()
    if type(ns.db.lastParty)=="table" and ns.db.lastParty.id==c.id then ns.db.lastParty.date=stamp() end
    if m.kind == "joined" and c.model.state == "joining" then
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
        if m.state=="accepting" and c.model.question and c.model.state=="presenting" then
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
            c.model.status="Match complete. Results saved on this client."
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
            if P.host and ns.game:Active() and next(P.host.joined) then ns.game:Pause("Party UI paused; return to the open world and resume.") end
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
        send("ended",h.id,"*",{reason="The host changed the match channel."},1)
        P.host=nil;h=nil
    end
    if h and not h.started and now()>=h.expires then
        send("ended",h.id,"*",{reason="The lobby expired. The host can open another match."},1)
        P.host=nil;h=nil
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
            g.presentationGate = next(h.joined) ~= nil
            if g.phase == "presenting" and (not h.gate or h.gate.index~=g.index or h.gate.attempt~=g.attempt) then
                h.gate={index=g.index,attempt=g.attempt,pending=targets(),deadline=now()+12}
                h.gate.revision=broadcast()
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
            h.dirty,h.signature=false,signature
            -- The initial presentation snapshot owns the exact ACK revision.
            if g.phase~="presenting" and g.phase~="opening" and g.phase~="accepting" then broadcast() end
            if not h.started then ns.RefreshHost() end
        end
    end
    if c and c.joined then
        if not roster()[c.hostKey] and c.model.state~="finished" then
            c.model.state,c.model.status="disconnected","The host left your Party."
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
        if (c.joinRetries or 0)<2 then c.joinAt,c.joinRetries=now(),(c.joinRetries or 0)+1;send("join",c.id,c.hostKey,{},1)
        else c.model.state,c.model.status="disconnected","Join was not confirmed. You can use Party chat.";render(c.model) end
    end
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
    local frame=CreateFrame("Frame");P.frame=frame
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:SetScript("OnEvent",function(_,event,...)
        if event=="CHAT_MSG_ADDON" then P.bus.transport.Receive(...)
        else rosterAt=nil end
    end)
    local elapsed=0
    frame:SetScript("OnUpdate",function(_,delta) elapsed=elapsed+delta;if elapsed>=0.1 then elapsed=0;P.Tick() end end)
    local last=ns.db.lastParty
    if type(last)=="table" and type(last.id)=="string" and type(last.hostKey)=="string" and integer(last.date,0,1000000000000)
        and stamp()-last.date<3600 and roster()[last.hostKey] then
        P.client={id=last.id,hostKey=last.hostKey,hostName=clean(last.hostName),joined=true,seq=0,lastSeen=now(),syncAt=now(),
            model={id=last.id,state="joining",host=clean(last.hostName),status="Restoring your previous match.",joined=true}}
        P.RequestSync()
    end
end
ns.HammerCore.Commands:Add({name="play",section="Trivia",help="Return to your joined Party match",run=function() if P.client then P.viewHistory=false;render(P.client.model);if ns.Player then ns.Player.Show() end else ns.HammerCore.Print("No joined Party match.") end end})
ns.HammerCore.Commands:Add({name="history",section="Trivia",help="View saved match results",run=P.ShowHistory})
ns.HammerCore.Commands:Add({name="leave",section="Trivia",help="Leave the joined addon match",run=P.Leave})
