local function eq(a, b, why) assert(a == b, why .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local clock = 100
local clients = {}
local function client(toc)
    local c = { active = true, combat = false, sent = {}, received = {}, logs = {}, failures = {} }
    local e = setmetatable({}, {__index = _G})
    e._G, e.LibStub, e.ChatThrottleLib = e, false, false
    e.GetTime = function() return clock end
    e.GetFramerate = function() return 60 end
    e.InCombatLockdown = function() return c.combat end
    e.issecretvalue = function(v) return v == c.secret end
    e.Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, GeneralError = 9 } }
    e.hooksecurefunc = function() end
    e.securecallfunction = function(fn, ...) return fn(...) end
    e.geterrorhandler = function() return function(err) error(err) end end
    local nativeXpcall = xpcall
    e.xpcall = function(fn, handler, ...)
        local args, n = {...}, select("#", ...)
        return nativeXpcall(function() return fn(unpack(args, 1, n)) end, handler)
    end
    e.table = setmetatable({ wipe = function(t) for k in pairs(t) do t[k] = nil end end }, {__index = table})
    e.CreateFrame = function()
        return { Show = function() end, Hide = function() end, SetScript = function() end, RegisterEvent = function() end }
    end
    e.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(prefix) c.prefix = prefix; return true end,
        InChatMessagingLockdown = function() return c.lockdown or false end,
        SendAddonMessage = function(prefix, wire, channel)
            c.sent[#c.sent + 1] = { prefix, wire, channel }
            if c.sendResult then return c.sendResult end
            if c.throttle then return 3 end
            if c.peer then c.peer.T.Receive(prefix, wire, channel, "Remote-Realm") end
            return 0
        end,
    }
    local ns = { Restricted = function() return c.restricted end }
    -- Exercise the dependency order from each actual TOC.
    for file in assert(io.open(toc)):read("*a"):gmatch("([^\r\n]+)") do
        file = file:gsub("\\", "/")
        if file:match("^Libs/.*%.lua$") or file == "Transport.lua" then
            setfenv(assert(loadfile(file)), e)("Loreforge", ns)
        end
    end
    c.T, c.e = ns.Transport, e
    c.T.Initialise(function(_, text, channel, sender)
        c.received[#c.received + 1] = { text, channel, sender }
    end, function() return c.active end, function(line) c.logs[#c.logs + 1] = line end, nil,
        function(result) c.failures[#c.failures + 1] = result end)
    c.T.Begin()
    clients[#clients + 1] = c
    return c
end
local function advance(seconds)
    for _ = 1, seconds * 10 do
        clock = clock + 0.1
        for _, c in ipairs(clients) do
            c.T.Tick()
            c.e.ChatThrottleLib.OnUpdate(c.e.ChatThrottleLib.Frame, 0.1)
        end
    end
end
local a, b = client("Loreforge.toc"), client("Loreforge_Camelot.toc")
a.peer, b.peer = b, a
assert(a.e.LibStub ~= b.e.LibStub, "independent client libraries")
eq(a.prefix, "LoreforgeP2", "new wire prefix")
local sample = "Quel'Thalas: Ünïcödé / Ŕuneblade / Žul'Aman " .. string.rep("question ", 12)
local wire = assert(a.T.Pack(sample))
eq(wire:sub(1, 2), "2D", "compress useful payloads")
eq(b.T.Unpack(wire), sample, "real libraries preserve UTF-8")
assert(a.T.Send(sample, "PARTY"))
assert(not a.T.Send("overlap", "PARTY"), "one in-flight packet")
advance(10)
eq(b.received[1][1], sample, "independent remote decode")
assert(b.T.Send("answer:2", "PARTY"))
advance(3)
eq(a.received[1][1], "answer:2", "bidirectional reply")
a.T.Begin()
a.sendResult = 5
assert(a.T.Send("native failure", "PARTY"))
advance(3)
eq(a.failures[1], 5, "asynchronous native send rejection reaches caller")
a.sendResult = nil

-- Reject malformed/oversized/old wire data, trailing compressed bytes and bombs.
assert(not b.T.Unpack("1:H:abc"), "old raw protocol rejected")
assert(not b.T.Unpack(string.rep("x", 256)), "wire cap")
assert(not b.T.Pack(string.rep("x", 241)), "sender plaintext cap")
local d = a.T.deflate
assert(not b.T.Unpack("2D" .. d:EncodeForWoWAddonChannel(d:CompressDeflate(string.rep("x", 10000)))), "expansion rejected")
assert(not b.T.Unpack("2D" .. d:EncodeForWoWAddonChannel(d:CompressDeflate("hello") .. "junk")), "trailing compressed bytes rejected")
assert(not b.T.Unpack("2D" .. d:EncodeForWoWAddonChannel(string.rep("x", 201))), "compressed input cap")
assert(not b.T.Unpack("2R\000"), "invalid channel encoding")
for _, text in ipairs({ string.rep("x", 240), string.rep("\000", 240), string.rep("\001", 240) }) do
    local packed = assert(a.T.Pack(text))
    eq(b.T.Unpack(packed), text, "boundary payload round trip")
end
b.T.Begin()
for _ = 1, 100 do b.T.Receive(b.prefix, "2Rhello", "PARTY", "Remote-Realm") end
eq(#b.T.incoming, 24, "receive/decode budget bounds queue")
b.T.Tick()
eq(#b.T.incoming, 23, "one decode per tick")
b.T.Cancel()
b.active = false
b.T.Receive(b.prefix, wire, "PARTY", "Remote-Realm")
eq(#b.T.incoming, 0, "unarmed client silent")
b.active = true

-- Stop, finish, combat, lockdown and superseded generations cannot leak queued sends.
for _, reason in ipairs({ "stop", "expiry", "combat", "lockdown", "generation" }) do
    a.T.Begin()
    local before = #a.sent
    assert(a.T.Send("cancel:" .. reason, "PARTY"))
    if reason == "stop" then a.T.Cancel()
    elseif reason == "expiry" then a.active = false
    elseif reason == "combat" then a.combat = true
    elseif reason == "lockdown" then a.lockdown = true
    else a.T.Begin() end
    advance(3)
    eq(#a.sent, before, reason .. " blocks actual wire dispatch")
    a.active, a.combat, a.lockdown = true, false, false
end

-- CTL retries must pass the same generation and 24-wire-attempt budget.
a.T.Begin()
a.throttle = true
assert(a.T.Send("retry", "PARTY"))
local before = #a.sent
advance(30)
eq(#a.sent - before, 24, "throttled retries bounded at actual API boundary")
eq(a.T.pending, nil, "budget exhaustion drains packet")
a.T.Begin()
assert(a.T.Send("stale retry", "PARTY"))
advance(1)
a.T.Cancel()
before = #a.sent
advance(3)
eq(#a.sent, before, "stopped retry suppressed")
a.throttle = false

-- A newer shared CTL disables only this adapter; another addon's queue is kept.
local ctl = a.e.ChatThrottleLib
local other = 0
ctl:Enqueue("NORMAL", "OtherAddon", { n = 0, nSize = 60, f = function() other = other + 1; return 0 end })
a.T.Cancel()
advance(3)
eq(other, 1, "unrelated addon traffic preserved")
ctl.version = 33
a.T.Initialise(function() end, function() return true end, function() end)
eq(a.T.available, false, "unknown CTL schema fails closed")
assert(not a.T.Send("unsupported", "PARTY"), "unsupported transport cannot send")
ctl.version = 32
for _, test in ipairs({ {false, false}, {true, true}, {0, true}, {1, true}, {2, false}, {3, false} }) do
    a.e.C_ChatInfo.RegisterAddonMessagePrefix = function() return test[1] end
    a.T.Initialise(function() end, function() return true end, function() end)
    eq(a.T.available, test[2], "boolean/enum prefix registration result " .. tostring(test[1]))
end
a.e.C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
a.T.Initialise(function() end, function() return true end, function() end)
local enqueue = ctl.Enqueue
ctl.Enqueue = function() error("queue unavailable") end
assert(not a.T.Send("queue failure", "PARTY"), "enqueue error returned to caller")
eq(a.T.pending, nil, "enqueue failure clears pending state")
eq(a.T.available, false, "enqueue failure disables transport safely")
ctl.Enqueue = enqueue
io.write("loreforge real-library transport tests passed\n")
