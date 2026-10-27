local _, ns = ...
local HC = ns.HammerCore
-- Development-only addon-message probe for docs/player-ui-design-review.md.
-- It proves delivery only when a different, consenting client acknowledges a
-- nonce; the host's own echo is logged but never counts as a pass.
local Probe = { peers = {}, queue = {}, seen = {} }
ns.Probe = Probe
local PREFIX, VERSION = "LoreforgeP", 1
local CHANNELS = { party = "PARTY", raid = "RAID", instance = "INSTANCE_CHAT", guild = "GUILD" }
local LISTEN_SECONDS, RUN_SECONDS, GAP, MAX_SENDS, MAX_LOG, MAX_RUNS, CHUNK = 600, 45, 1, 24, 300, 10, 180
-- A listener answers any group member, so bound what one window will hold:
-- distinct probe sessions, chunks per question and queued replies.
local MAX_SESSIONS, MAX_CHUNKS = 8, 16
-- Accented, multi-byte text over one message long forces UTF-8-safe chunking.
Probe.SAMPLE = "Loreforge probe: Which Quel'Thalas city did Anasterian rule from — Silvermoon, Quel'Danas, "
    .. "Tranquillien or Fairbreeze? Ünïcödé check: Ŕuneblade, Æthelred, Žul'Aman, Dalaran Crater, Aszhära."
    .. " Second sentence so the payload crosses two or more addon messages without splitting a character."
local function readable(v) return not (issecretvalue and issecretvalue(v)) end
local function now() return GetTime() end

function Probe.Checksum(text)
    local a, b = 1, 0
    for i = 1, #text do a = (a + text:byte(i)) % 65521; b = (b + a) % 65521 end
    return string.format("%08x", b * 65536 + a)
end
-- Split at byte limits without cutting a UTF-8 continuation sequence.
function Probe.Chunks(text, size)
    local chunks, start = {}, 1
    while start <= #text do
        local stop = math.min(#text, start + size - 1)
        while stop < #text and stop > start do
            local nextByte = text:byte(stop + 1)
            if nextByte < 128 or nextByte >= 192 then break end
            stop = stop - 1
        end
        chunks[#chunks + 1] = text:sub(start, stop)
        start = stop + 1
    end
    return chunks
end

local function log(text)
    local db = ns.db.probe
    local line = string.format("[%s +%.2f] %s", date and date("%H:%M:%S") or "", now() - (Probe.started or now()), text)
    db.log[#db.log + 1] = line
    while #db.log > MAX_LOG do table.remove(db.log, 1) end
    if Probe.verbose then HC.Print(line) end
end
local function context()
    local home, instance = LE_PARTY_CATEGORY_HOME or 1, LE_PARTY_CATEGORY_INSTANCE or 2
    local inInstance, kind = false, "none"
    if IsInInstance then inInstance, kind = IsInInstance() end
    local lockdown = "n/a"
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, value = pcall(C_ChatInfo.InChatMessagingLockdown)
        lockdown = ok and readable(value) and tostring(value) or "unreadable"
    end
    return string.format("client=%s build=%s home=%s instanceGroup=%s raid=%s instance=%s/%s combat=%s restricted=%s msgLockdown=%s",
        tostring(ns.era), tostring(select(2, GetBuildInfo())), tostring(IsInGroup and IsInGroup(home) or false),
        tostring(IsInGroup and IsInGroup(instance) or false), tostring(IsInRaid and IsInRaid() or false),
        tostring(inInstance), tostring(kind), tostring(InCombatLockdown and InCombatLockdown() or false),
        tostring(ns.Restricted()), lockdown)
end
local function resultName(result)
    local names = Enum and Enum.SendAddonMessageResult
    if type(names) == "table" then
        for name, value in pairs(names) do if value == result then return name end end
    end
    return tostring(result)
end
local function rawSend(text, channel)
    if Probe.sends >= MAX_SENDS then log("HELD send budget reached: " .. text:sub(1, 12)); return end
    Probe.sends = Probe.sends + 1
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    local ok, result = pcall(send, PREFIX, text, channel)
    log(string.format("SEND %s %s bytes=%d result=%s%s", channel, text:sub(1, 12), #text,
        ok and resultName(result) or ("error " .. tostring(result)), ns.Restricted() and " (restricted)" or ""))
end
local function queue(text, channel)
    if #Probe.queue >= MAX_SENDS then log("HELD queue full: " .. text:sub(1, 12)); return end
    Probe.queue[#Probe.queue + 1] = { text = text, channel = channel }
end
local function resolve(sender, channel)
    local key = ns.Identity(sender)
    if not key then return nil, "unreadable" end
    local roster = ns.Roster(channel, true)
    for _, p in ipairs(roster or {}) do if p.key == key then return key, "roster" end end
    return key, "unmatched"
end

function Probe.Initialise()
    ns.db.probe = type(ns.db.probe) == "table" and ns.db.probe or {}
    local db = ns.db.probe
    db.log, db.runs = type(db.log) == "table" and db.log or {}, type(db.runs) == "table" and db.runs or {}
    local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
    local ok, result = pcall(register, PREFIX)
    Probe.registered = ok and tostring(result) or ("error " .. tostring(result))
    Probe.sends = 0
    local frame = CreateFrame("Frame")
    Probe.frame = frame
    for _, event in ipairs({ "CHAT_MSG_ADDON", "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE" }) do pcall(frame.RegisterEvent, frame, event) end
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then Probe.Receive(...)
        elseif Probe.Busy() then log("EVENT " .. event .. " " .. context()) end
    end)
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.1 then return end
        elapsed = 0
        Probe.Tick()
    end)
end
function Probe.Busy() return Probe.run ~= nil or (Probe.listenUntil or 0) > now() end

function Probe.Listen()
    Probe.listenUntil, Probe.sends, Probe.started = now() + LISTEN_SECONDS, 0, now()
    Probe.seen, Probe.sessions = {}, 0
    log("LISTEN armed for " .. LISTEN_SECONDS .. "s, prefix " .. PREFIX .. " registered=" .. Probe.registered .. " " .. context())
    HC.Print("Probe listening for 10 minutes. This client will answer one probe from the Game Master.")
end
function Probe.Start(word)
    local channel = CHANNELS[(word or ""):lower()]
    if not channel then HC.Print("Choose party, raid, instance or guild."); return end
    if Probe.run then HC.Print("A probe is already running."); return end
    if InCombatLockdown and InCombatLockdown() then HC.Print("Leave combat before probing."); return end
    local nonce = string.format("%06x", math.random(0, 0xffffff))
    Probe.run = { nonce = nonce, channel = channel, deadline = now() + RUN_SECONDS, chunks = Probe.Chunks(Probe.SAMPLE, CHUNK) }
    Probe.peers, Probe.queue, Probe.sends, Probe.started = {}, {}, 0, now()
    log(string.format("START %s nonce=%s prefix registered=%s chunks=%d bytes=%d sum=%s %s", channel, nonce,
        Probe.registered, #Probe.run.chunks, #Probe.SAMPLE, Probe.Checksum(Probe.SAMPLE), context()))
    queue(table.concat({ VERSION, "H", nonce, ns.era, tostring(HC.GetMetadata("Version")) }, ":"), channel)
    for i, chunk in ipairs(Probe.run.chunks) do
        queue(table.concat({ VERSION, "Q", nonce, i, #Probe.run.chunks, #Probe.SAMPLE, Probe.Checksum(Probe.SAMPLE), chunk }, ":"), channel)
    end
    HC.Print("Probe started on " .. channel .. ". Results in about " .. RUN_SECONDS .. " seconds; then /lf probe report.")
end
function Probe.Stop()
    if Probe.run then Probe.Finish("stopped") end
    Probe.listenUntil, Probe.queue = nil, {}
    HC.Print("Probe stopped.")
end

function Probe.Tick()
    local item = Probe.queue[1]
    if item and now() >= (Probe.nextSend or 0) then
        table.remove(Probe.queue, 1)
        Probe.nextSend = now() + GAP
        rawSend(item.text, item.channel)
    end
    if Probe.run and now() >= Probe.run.deadline then Probe.Finish("complete") end
end

function Probe.Receive(prefix, text, channel, sender)
    if prefix ~= PREFIX or not readable(text) or not readable(sender) or type(text) ~= "string" then return end
    local version, kind, nonce, rest = text:match("^(%d+):(%u):(%x+):?(.*)$")
    if not kind then log("DROP malformed from " .. tostring(sender)); return end
    local key, match = resolve(sender, channel)
    local mine = ns.Person("player")
    local me = mine and mine.key
    local own = key and me and key == me
    if own then log(string.format("SELF-ECHO %s %s via %s (not proof)", kind, nonce, channel)); return end
    if tonumber(version) ~= VERSION then log("DROP version " .. version .. " from " .. sender); return end
    local run = Probe.run
    if run and nonce == run.nonce then
        -- Host side: peers answer the Game Master's nonce.
        local peer = Probe.peers[key] or { name = sender, match = match, channel = channel }
        Probe.peers[key] = peer
        local at = now() - Probe.started
        if kind == "R" then peer.hello, peer.client = at, rest
        elseif kind == "V" then
            local ok = rest:match("^(%d)")
            peer.verify, peer.intact = at, ok == "1"
        elseif kind == "A" then
            peer.answer, peer.choice = at, rest
            queue(table.concat({ VERSION, "L", nonce, rest, sender }, ":"), run.channel)
        elseif kind == "C" then peer.confirm = at end
        log(string.format("RECV %s from %s (%s, %s) via %s", kind, sender, match, tostring(key), channel))
        return
    end
    if (Probe.listenUntil or 0) <= now() then return end
    -- Listener side: answer each nonce once, on the channel it arrived on.
    local state = Probe.seen[nonce]
    if not state then
        if (Probe.sessions or 0) >= MAX_SESSIONS then log("DROP session limit for nonce " .. nonce); return end
        Probe.sessions = (Probe.sessions or 0) + 1
        state = { chunks = {}, host = key }
        Probe.seen[nonce] = state
    end
    log(string.format("RECV %s %s from %s (%s) via %s bytes=%d", kind, nonce, sender, match, channel, #text))
    if state.host ~= key then log("DROP different host for nonce " .. nonce); return end
    if kind == "H" and not state.replied then
        state.replied = true
        queue(table.concat({ VERSION, "R", nonce, ns.era, tostring(HC.GetMetadata("Version")) }, ":"), channel)
    elseif kind == "Q" then
        local index, total, length, sum, payload = rest:match("^(%d+):(%d+):(%d+):(%x+):(.*)$")
        if not index then log("DROP malformed chunk"); return end
        index, total, length = tonumber(index), tonumber(total), tonumber(length)
        -- Check the frame before storing it or looping over its total.
        if total < 1 or total > MAX_CHUNKS or index < 1 or index > total or length > MAX_CHUNKS * CHUNK
            or (state.total and state.total ~= total) then
            log("DROP chunk out of range"); return
        end
        state.chunks[index], state.total, state.length, state.sum = payload, total, length, sum
        for i = 1, state.total do if not state.chunks[i] then return end end
        if state.verified then return end
        local whole = table.concat(state.chunks)
        local intact = #whole == state.length and Probe.Checksum(whole) == state.sum
        state.verified = true
        log(string.format("QUESTION assembled bytes=%d sum=%s intact=%s", #whole, Probe.Checksum(whole), tostring(intact)))
        HC.Print("Probe question received" .. (intact and "" or " (damaged)") .. ": " .. whole:sub(1, 60) .. "...")
        queue(table.concat({ VERSION, "V", nonce, intact and 1 or 0, #whole, Probe.Checksum(whole) }, ":"), channel)
        queue(table.concat({ VERSION, "A", nonce, 2 }, ":"), channel)
        state.answered = now()
    elseif kind == "L" then
        local choice, target = rest:match("^(%d):(.*)$")
        local targetKey = ns.Identity(target)
        if targetKey == me and not state.locked then
            state.locked = true
            log(string.format("LOCKED choice=%s round trip=%.2fs", tostring(choice), now() - (state.answered or now())))
            HC.Print("Probe answer locked by the Game Master. Probe passed on this client.")
            queue(table.concat({ VERSION, "C", nonce, choice }, ":"), channel)
        end
    end
end

function Probe.Finish(reason)
    local run = Probe.run
    Probe.run = nil
    local lines = { string.format("Probe %s on %s, nonce %s, %d sends", reason, run.channel, run.nonce, Probe.sends) }
    local passed, count = 0, 0
    for _, peer in pairs(Probe.peers) do
        count = count + 1
        local function at(v) return v and string.format("%.1fs", v) or "missing" end
        local full = peer.hello and peer.intact and peer.answer and peer.confirm
        if full then passed = passed + 1 end
        lines[#lines + 1] = string.format("%s [%s, %s]: hello %s, question %s%s, answer %s, lock confirmed %s -> %s",
            peer.name, peer.match, tostring(peer.client), at(peer.hello), at(peer.verify),
            peer.verify and (peer.intact and " intact" or " DAMAGED") or "", at(peer.answer), at(peer.confirm),
            full and "PASS" or "INCOMPLETE")
    end
    if count == 0 then lines[#lines + 1] = "No other client replied. Was a listener armed with /lf probe listen?" end
    local summary = table.concat(lines, "\n")
    local runs = ns.db.probe.runs
    runs[#runs + 1] = summary
    while #runs > MAX_RUNS do table.remove(runs, 1) end
    log("FINISH " .. reason .. " peers=" .. count .. " passed=" .. passed .. " " .. context())
    HC.Print(string.format("Probe %s: %d of %d replying clients passed. /lf probe report for details.", reason, passed, count))
    return summary
end

function Probe.Report()
    local db = ns.db.probe
    local text = "Loreforge transport probe\n" .. context() .. "\nPrefix registered: " .. tostring(Probe.registered)
        .. "\n\n== Runs ==\n" .. (#db.runs > 0 and table.concat(db.runs, "\n\n") or "None on this client")
        .. "\n\n== Log ==\n" .. table.concat(db.log, "\n")
    HC.Copy:Show("Loreforge probe", text)
    return text
end

HC.Commands:Add({ name = "probe", args = "<party|raid|instance|guild|listen|report|stop>", section = "Trivia", hidden = true,
    help = "Development transport probe",
    run = function(args)
        local word = (args or ""):lower():match("^%s*(%S*)")
        if word == "listen" then Probe.Listen()
        elseif word == "report" then Probe.Report()
        elseif word == "stop" then Probe.Stop()
        elseif word == "verbose" then Probe.verbose = not Probe.verbose; HC.Print("Probe log echo " .. (Probe.verbose and "on." or "off."))
        else Probe.Start(word) end
    end })
