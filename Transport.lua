local _, ns = ...
-- Probe-only adapter. See docs/transport.md for the wire format and vendor pin.
local T = { generation = 0, incoming = {}, attempts = 0, decodes = 0 }
ns.Transport = T
T.PREFIX = "LoreforgeP2"
local MAX_TEXT, MAX_WIRE, MAX_COMPRESSED, MAX_ATTEMPTS = 240, 255, 200, 24
local CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true }
local function readable(v) return not (issecretvalue and issecretvalue(v)) end
local function blocked()
    if InCombatLockdown and InCombatLockdown() then return true end
    if ns.Restricted() then return true end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, value = pcall(C_ChatInfo.InChatMessagingLockdown)
        if not ok or not readable(value) or value then return true end
    end
    return false
end
T.Blocked = blocked

function T.Initialise(receive, active, log, accept, failed)
    T.receive, T.active, T.log, T.accept = receive, active, log, accept
    T.failed = failed
    local ctl = ChatThrottleLib
    -- Enqueue's message schema is private to CTL v32. Fail closed on upgrades.
    T.available = ctl and ctl.version == 32 and type(ctl.Enqueue) == "function"
        and ctl.Prio and ctl.Prio.NORMAL and type(ctl.MSG_OVERHEAD) == "number"
    T.deflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    T.available = not not (T.available and T.deflate)
    if not T.available then return "unavailable (transport library version)" end
    local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
    local ok, result = pcall(register, T.PREFIX)
    local values = Enum and Enum.RegisterAddonMessagePrefixResult
    local success, duplicate = values and values.Success or 0, values and values.DuplicatePrefix or 1
    T.available = ok and readable(result) and (result == true or result == success or result == duplicate)
    return ok and tostring(result) or ("error " .. tostring(result))
end

function T.Cancel()
    T.generation = T.generation + 1
    T.incoming = {}
    -- A queued CTL packet keeps its old generation. Its dispatch guard discards
    -- it without touching the shared library's queues or another addon's traffic.
end
function T.Begin()
    T.Cancel()
    T.attempts, T.decodes = 0, 0
end
function T.Ready()
    return T.available and ChatThrottleLib and ChatThrottleLib.version == 32 and not T.pending
end

function T.Pack(text)
    if type(text) ~= "string" or #text > MAX_TEXT then return nil, "payload too large" end
    local d = T.deflate
    if not d then return nil, "codec unavailable" end
    local raw = "2R" .. d:EncodeForWoWAddonChannel(text)
    local compressed = d:CompressDeflate(text)
    local wire = #compressed <= MAX_COMPRESSED and ("2D" .. d:EncodeForWoWAddonChannel(compressed))
    if not wire or #wire >= #raw then wire = raw end
    if #wire > MAX_WIRE then return nil, "encoded payload too large" end
    return wire
end

function T.Unpack(wire)
    if type(wire) ~= "string" or #wire > MAX_WIRE or #wire < 2 then return nil end
    local mode = wire:sub(1, 2)
    if mode ~= "2R" and mode ~= "2D" then return nil end
    local data = T.deflate:DecodeForWoWAddonChannel(wire:sub(3))
    if not data then return nil end
    if mode == "2D" then
        if #data > MAX_COMPRESSED then return nil end
        -- Upstream has no inflate output limit. The 200-byte compressed-input
        -- cap bounds temporary expansion; MAX_TEXT is an acceptance limit only.
        local remaining
        data, remaining = T.deflate:DecompressDeflate(data)
        if not data or remaining ~= 0 then return nil end
    end
    if #data > MAX_TEXT then return nil end
    return data
end

function T.Send(text, channel)
    if not T.Ready() then return false, "transport busy or unavailable" end
    if not CHANNELS[channel] then return false, "unsupported channel" end
    if not T.active() or blocked() then return false, "inactive or restricted" end
    if T.attempts >= MAX_ATTEMPTS then return false, "wire budget reached" end
    local wire, why = T.Pack(text)
    if not wire then return false, why end
    local ctl, generation, deadline = ChatThrottleLib, T.generation, GetTime() + 45
    local item = {}
    T.pending = item
    local failure = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.GeneralError or 9
    local msg = { T.PREFIX, wire, channel, n = 3, nSize = #wire + ctl.MSG_OVERHEAD }
    msg.f = function(prefix, payload, distribution)
        if ChatThrottleLib.version ~= 32 or generation ~= T.generation or not T.active() or GetTime() >= deadline
            or blocked() or T.attempts >= MAX_ATTEMPTS then
            item.cancelled = true
            return failure
        end
        T.attempts = T.attempts + 1
        T.log(string.format("WIRE attempt=%d channel=%s bytes=%d", T.attempts, distribution, #payload))
        return C_ChatInfo.SendAddonMessage(prefix, payload, distribution)
    end
    msg.callbackFn = function(_, sent, result)
        if T.pending == item then T.pending = nil end
        T.log(string.format("CTL sent=%s result=%s cancelled=%s", tostring(sent), tostring(result), tostring(item.cancelled or false)))
        if generation == T.generation and not item.cancelled and not sent and T.failed then T.failed(result) end
    end
    -- Enqueue explicitly so every wire attempt, including throttle retries,
    -- passes our guard. SendAddonMessage's immediate path cannot do that.
    local ok, err = pcall(ctl.Enqueue, ctl, "NORMAL", T.PREFIX, msg)
    if not ok then
        T.Cancel()
        T.pending, T.available = nil, false
        T.log("Transport enqueue failed: " .. tostring(err))
        return false, "throttle queue error; transport disabled until reload"
    end
    return true, "queued"
end

function T.Receive(prefix, wire, channel, sender)
    if not readable(prefix) or not readable(wire) or not readable(channel) or not readable(sender) then return end
    if prefix ~= T.PREFIX or not T.available or not T.active() or blocked()
        or type(channel) ~= "string" or not CHANNELS[channel] or type(sender) ~= "string" or #sender > 120
        or type(wire) ~= "string" or #wire > MAX_WIRE or T.decodes >= MAX_ATTEMPTS then return end
    if T.accept and not T.accept(sender, channel) then return end
    T.decodes = T.decodes + 1
    T.incoming[#T.incoming + 1] = { wire, channel, sender }
end

function T.Tick()
    if blocked() then
        if #T.incoming > 0 or T.pending then T.Cancel() end
        return
    end
    if not T.active() then T.incoming = {}; return end
    local item = table.remove(T.incoming, 1)
    if not item then return end
    local ok, text = pcall(T.Unpack, item[1])
    if ok and text then T.receive(T.PREFIX, text, item[2], item[3])
    else T.log("DROP invalid transport frame") end
end
