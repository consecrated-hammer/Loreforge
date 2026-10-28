package.path = "./tests/hammercore/?.lua;" .. package.path
local wow = require("wow")
local function eq(a, b, why) assert(a == b, why .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
for _, toc in ipairs({ "Loreforge.toc", "Loreforge_Camelot.toc" }) do
    wow.Install({ Loreforge = { Version = "0.1.0" } })
    LoreforgeDB = nil
    local time = 100
    GetTime = function() return time end
    GetBuildInfo = function() return "version", "build", "date", toc:find("Camelot") and 16001 or 120105 end
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
    GetNormalizedRealmName = function() return "Realm" end
    UnitFullName = function(unit) return unit == "player" and "Host" or unit == "party1" and "Guest" or nil, "Realm" end
    GetUnitName = function(unit) return (UnitFullName(unit)) end
    UnitName = UnitFullName
    UnitGUID = function(unit) return unit == "player" and "hostGUID" or "guestGUID" end
    IsInRaid = function() return false end
    GetNumSubgroupMembers = function() return 1 end
    RegisterStateDriver, UnregisterStateDriver = function() end, function() end
    assert(loadfile('tests/transport-libs.lua'))()()
    local ns = wow.LoadHammerCore("Libs/HammerCore", "Loreforge")
    local addon, prefixes = {}, {}
    C_ChatInfo.RegisterAddonMessagePrefix = function(prefix) prefixes[prefix] = true; return 0 end
    C_ChatInfo.SendAddonMessage = function(prefix, text, channel)
        addon[#addon + 1] = { prefix = prefix, text = text, channel = channel }; return 0
    end
    for file in assert(io.open(toc)):read("*a"):gmatch("([^\r\n]+)") do
        if file:match("^[%w]+%.lua$") then assert(loadfile(file))("Loreforge", ns) end
    end
    local loader
    for _, f in ipairs(wow.frames) do if f.scripts.OnEvent then loader = f end end
    loader.scripts.OnEvent(loader, "ADDON_LOADED", "Loreforge")
    IsInGroup = function(category) return category ~= 2 end
    local P = ns.Probe
    eq(prefixes.LoreforgeP2, true, "prefix registered at load")

    -- UTF-8-safe chunking and integrity.
    local chunks = P.Chunks(P.SAMPLE, 180)
    assert(#chunks >= 2, "sample spans several messages")
    eq(table.concat(chunks), P.SAMPLE, "chunks reassemble")
    for _, chunk in ipairs(chunks) do
        assert(#chunk <= 180, "chunk within limit")
        local first = chunk:byte(1)
        assert(first < 128 or first >= 192, "no chunk starts mid-character")
    end
    for size = 2, 40 do eq(table.concat(P.Chunks(P.SAMPLE, size)), P.SAMPLE, "small chunk size " .. size) end
    assert(P.Checksum("abc") ~= P.Checksum("abd"), "checksum notices a change")

    local function drain(seconds)
        for _ = 1, seconds * 10 do time = time + 0.1; P.Tick(); ChatThrottleLib.OnUpdate(ChatThrottleLib.Frame, 0.1) end
    end
    local function recv(text, sender) P.Receive("LoreforgeP2", text, "PARTY", sender) end
    local function sent(kind)
        local found = {}
        for _, m in ipairs(addon) do
            local text = ns.Transport.Unpack(m.text)
            if text and text:match("^1:" .. kind .. ":") then
                found[#found + 1] = { text = text, prefix = m.prefix, channel = m.channel }
            end
        end
        return found
    end

    -- Host side: a consenting peer completes every leg; self echoes never count.
    P.Start("party")
    local nonce = P.run.nonce
    drain(10)
    eq(#sent("H"), 1, "hello sent")
    eq(#sent("Q"), #chunks, "every chunk sent")
    eq(addon[1].prefix, "LoreforgeP2", "probe prefix")
    eq(addon[1].channel, "PARTY", "chosen distribution")
    for _, m in ipairs(addon) do
        P.frame.scripts.OnEvent(P.frame, "CHAT_MSG_ADDON", m.prefix, m.text, "PARTY", "Host")
    end
    eq(ns.Transport.decodes, 0, "self echoes do not spend decode budget")
    for _, m in ipairs(addon) do recv(ns.Transport.Unpack(m.text), "Host") end
    eq(next(P.peers), nil, "self echo is not a peer")
    recv("1:R:" .. nonce .. ":retail:0.1.0", "Guest")
    recv("1:V:" .. nonce .. ":1:" .. #P.SAMPLE .. ":" .. P.Checksum(P.SAMPLE), "Guest")
    recv("1:A:" .. nonce .. ":2", "Guest")
    drain(1)
    eq(sent("L")[1].text, "1:L:" .. nonce .. ":2:Guest", "host acknowledges the actual sender")
    recv("1:C:" .. nonce .. ":2", "Guest")
    local peer = P.peers["guest-realm"]
    eq(peer.match, "roster", "sender resolved through the group roster")
    local summary = P.Finish("complete")
    assert(summary:find("Guest %[roster"), "summary names the peer")
    assert(summary:find("PASS"), "complete round trip passes")
    assert(table.concat(ns.db.probe.log, "\n"):find("SELF%-ECHO"), "self echo logged")
    assert(P.Report():find("== Runs =="), "copyable report")
    assert(P.Report():find("ChatThrottleLib 32"), "report identifies loaded throttle library")
    assert(P.Report():find("LibDeflate 1.0.2%-release"), "report identifies loaded codec")
    assert(P.Report():find("prefix LoreforgeP2"), "report identifies wire protocol")

    -- No listener: an honest empty result.
    P.Start("raid")
    drain(50)
    assert(ns.db.probe.runs[#ns.db.probe.runs]:find("No other client replied"), "empty run explained")
    eq(P.run, nil, "run ends at its deadline")

    -- Listener side: unarmed clients stay silent; armed ones answer once.
    addon = {}
    recv("1:H:abc123:retail:0.1.0", "Guest")
    drain(2)
    eq(#addon, 0, "no reply without consent")
    SlashCmdList.LOREFORGE("probe listen")
    recv("1:H:abc123:retail:0.1.0", "Guest")
    recv("1:H:abc123:retail:0.1.0", "Guest")
    for i, chunk in ipairs(chunks) do
        recv(table.concat({ 1, "Q", "abc123", i, #chunks, #P.SAMPLE, P.Checksum(P.SAMPLE), chunk }, ":"), "Guest")
    end
    recv("1:Q:abc123:1:1:5:00000000:hello", "Stranger")
    drain(5)
    eq(#sent("R"), 1, "one hello reply")
    eq(sent("V")[1].text, "1:V:abc123:1:" .. #P.SAMPLE .. ":" .. P.Checksum(P.SAMPLE), "intact question verified")
    eq(sent("A")[1].text, "1:A:abc123:2", "answer sent after the question")
    recv("1:L:abc123:2:Someone", "Guest")
    drain(2)
    eq(#sent("C"), 0, "another player's lock is ignored")
    recv("1:L:abc123:2:Host-Realm", "Guest")
    recv("1:L:abc123:2:Host-Realm", "Guest")
    drain(2)
    eq(#sent("C"), 1, "lock confirmed once")

    -- Damage is reported rather than silently accepted.
    addon = {}
    recv("1:H:def456:retail:0.1.0", "Guest")
    recv("1:Q:def456:1:2:10:" .. P.Checksum("helloworld") .. ":hello", "Guest")
    recv("1:Q:def456:2:2:10:" .. P.Checksum("helloworld") .. ":wurld", "Guest")
    drain(3)
    assert(sent("V")[1].text:match("^1:V:def456:0:"), "damaged question reported")
    recv("garbage", "Guest")
    recv("2:H:aaa111:x", "Guest")
    assert(table.concat(ns.db.probe.log, "\n"):find("DROP version"), "version mismatch dropped")

    -- Bounded traffic and refusals.
    addon = {}
    P.Stop()
    P.Start("nowhere")
    eq(P.run, nil, "unknown distribution refused")
    InCombatLockdown = function() return true end
    P.Start("party")
    eq(P.run, nil, "combat refuses a probe")
    InCombatLockdown = function() return false end
    P.Listen()
    for i = 1, 40 do recv(string.format("1:H:%06x:retail:0.1.0", i), "Guest") end
    drain(45)
    eq(#addon, 8, "listener sessions are capped per window")
    eq(#P.queue, 0, "capped sessions queue nothing further")
    P.Listen()
    addon = {}
    local started = os.clock()
    recv("1:H:fff000:retail:0.1.0", "Guest")
    recv("1:Q:fff000:1:100000000:5:00000000:hello", "Guest")
    recv("1:Q:fff000:3:2:5:00000000:hello", "Guest")
    recv("1:Q:fff000:1:2:999999:00000000:hello", "Guest")
    drain(3)
    eq(#sent("V"), 0, "out-of-range chunks never assemble")
    assert(os.clock() - started < 1, "an oversized chunk total does not stall the client")
    assert(table.concat(ns.db.probe.log, "\n"):find("DROP chunk out of range"), "oversized chunk logged")
    local pending = #P.queue
    recv("1:Q:fff000:1:2:181:00000000:" .. string.rep("x", 181), "Guest")
    eq(#P.queue, pending, "oversized individual chunk dropped")
    for _ = 1, 400 do P.Receive("LoreforgeP2", "junk", "PARTY", "Guest") end
    eq(#ns.db.probe.log, 300, "log is bounded")
    P.Stop()
    drain(2)
    C_ChatInfo.SendAddonMessage = function() return 5 end
    P.Start("party")
    drain(10)
    eq(P.run, nil, "asynchronous native rejection stops the probe")
    assert(table.concat(ns.db.probe.log, "\n"):find("CTL sent=false result=5"), "native failure retained in report")
end
io.write("loreforge probe tests passed\n")
