local _, ns = ...
-- Bounded reliable packets over Party broadcasts. Recipient filtering is not encryption.
local B = {}
ns.PartyBus = B
function B.New(deliver, roster, active, log, eligible)
    local bus = { outgoing = {}, assemblies = {}, seen = {}, cancelled = {}, controls = {}, serial = 0, incomingBytes = 0, peers = {} }
    local transport = ns.Transport.New({prefix = "LoreforgeM1", limit = 64, receiveLimit = 128, window = 10, queueLimit = 48})
    bus.transport = transport
    local boot = string.format("%08x%06x", math.floor(GetTime() * 1000) % 0x7fffffff, math.random(0, 0xffffff))
    local function members() return roster() or {} end
    local function accept(sender)
        local key = ns.Identity(sender)
        local me = ns.Person("player")
        return key and me and key ~= me.key and members()[key] ~= nil
    end
    local rate,rateStart={},GetTime()
    local function filter(sender)
        if not accept(sender) then return false end
        if GetTime()-rateStart>=10 then rate,rateStart={},GetTime() end
        local key=ns.Identity(sender)
        rate[key]=(rate[key] or 0)+1
        return rate[key]<=64
    end
    local function ack(id)
        if #bus.controls < 48 then bus.controls[#bus.controls + 1] = "!1|" .. id end
    end
    local function removeAssembly(key)
        local a = bus.assemblies[key]
        if a then bus.incomingBytes = bus.incomingBytes - a.bytes; bus.assemblies[key] = nil end
    end
    function bus.SetPeer(key, session, supported)
        local old=bus.peers[key]
        bus.peers[key]={session=session,supported=supported==true}
        if not supported or (old and old.session~=session) then
            local retry={}
            for id,item in pairs(bus.outgoing) do
                if item.version=="2" and item.targets[key] then
                    if #bus.controls<48 then bus.controls[#bus.controls+1]="!0|"..id end
                    bus.outgoing[id]=nil
                    retry[#retry+1]=item
                end
            end
            table.sort(retry,function(a,b) return a.order<b.order end)
            -- Requeue immutable payloads under new IDs, preserving order/lifetime.
            for _,item in ipairs(retry) do
                if next(item.targets) then
                    local message=ns.Codec.Decode(item.legacy)
                    local id,why
                    if message then id,why=bus.Send(message,item.targets,item.priority,item.replace,true) end
                    if id then
                        local fresh=bus.outgoing[id]
                        fresh.appKind,fresh.appId,fresh.appTo=item.appKind,item.appId,item.appTo
                        fresh.created,fresh.order,fresh.retry=item.created,item.order,item.retry
                    else log("Party legacy fallback failed: "..tostring(why or "invalid payload")) end
                end
            end
        end
    end
    function bus.Send(message, targets, priority, replace, legacyOnly)
        local binary=not legacyOnly and ns.WireCodec.Available() and next(targets or {})~=nil
            and message.kind~="invite" and message.kind~="join" and message.kind~="sync"
        for key in pairs(targets or {}) do
            local peer=bus.peers[key]
            if not peer or not peer.supported or peer.session~=message.id then binary=false end
        end
        local legacy=ns.Codec.Encode(message)
        if not legacy then return nil, "Message too large" end
        local text=binary and ns.WireCodec.Encode(message,legacy)
        local version=text and "2" or "1"
        text=text or legacy
        if replace then
            for id, item in pairs(bus.outgoing) do
                if item.replace == replace then
                    if (item.at>1 or item.queued) and #bus.controls<48 then bus.controls[#bus.controls+1]="!0|"..id end
                    bus.outgoing[id] = nil
                end
            end
        end
        local count = 0
        for _ in pairs(bus.outgoing) do count = count + 1 end
        if count >= 12 then return nil, "Party queue full" end
        bus.serial = bus.serial + 1
        local id = boot .. "-" .. bus.serial
        local item = { frames = {}, targets = {}, order=bus.serial, legacy=legacy, version=version, at = 1, retry = 0, created = GetTime(), priority = priority or 2, replace = replace }
        for key in pairs(targets or {}) do item.targets[key] = true end
        local total, sum = math.ceil(#text / 160), ns.Codec.Sum(text)
        for i = 1, total do
            item.frames[i] = table.concat({version, id, i, total, #text, sum, text:sub((i - 1) * 160 + 1, i * 160)}, "|")
        end
        bus.outgoing[id] = item
        return id
    end
    function bus.Receive(_, frame, channel, sender)
        if channel ~= "PARTY" or not accept(sender) then return end
        local senderKey = ns.Identity(sender)
        local abortId = frame:match("^!0|([%w%-]+)$")
        if abortId then
            local key=senderKey.."|"..abortId
            removeAssembly(key)
            bus.cancelled[key]=GetTime()
            return
        end
        local ackId = frame:match("^!1|([%w%-]+)$")
        if ackId then
            local item = bus.outgoing[ackId]
            if item and item.targets[senderKey] then item.targets[senderKey] = nil end
            return
        end
        local version, id, index, total, length, sum, payload = frame:match("^([12])|([%w%-]+)|(%d+)|(%d+)|(%d+)|(%x+)|(.*)$")
        if not id or #id > 40 or #index > 3 or #total > 3 or #length > 5 or #sum ~= 8 then return end
        index, total, length = tonumber(index), tonumber(total), tonumber(length)
        if total < 1 or total > 205 or index < 1 or index > total or length < 1 or length > ns.Codec.MAX
            or total ~= math.ceil(length / 160) or #payload ~= math.min(160, length - (index - 1) * 160) then return end
        local key = senderKey .. "|" .. id
        if bus.cancelled[key] then return end
        if bus.seen[key] then if bus.seen[key].ack then ack(id) end; return end
        local a = bus.assemblies[key]
        if not a then
            local n, owned = 0, 0
            local small=total<=4
            for assemblyKey in pairs(bus.assemblies) do
                n = n + 1
                if assemblyKey:sub(1,#senderKey+1)==senderKey.."|" and (bus.assemblies[assemblyKey].total<=4)==small then owned=owned+1 end
            end
            if owned >= 2 or n >= 16 or bus.incomingBytes + #payload > 65536 then return end
            a = {version=version, parts = {}, bytes = 0, total = total, length = length, sum = sum, created = GetTime()}
            bus.assemblies[key] = a
        end
        if a.version ~= version or a.total ~= total or a.length ~= length or a.sum ~= sum or (a.parts[index] and a.parts[index] ~= payload) then removeAssembly(key); return end
        if not a.parts[index] then
            if bus.incomingBytes + #payload > 65536 then removeAssembly(key); return end
            a.parts[index], a.bytes, bus.incomingBytes = payload, a.bytes + #payload, bus.incomingBytes + #payload
        end
        for i = 1, total do if not a.parts[i] then return end end
        local text = table.concat(a.parts)
        removeAssembly(key)
        if #text ~= length or ns.Codec.Sum(text) ~= sum then return end
        local message
        if version=="2" then message=ns.WireCodec.Decode(text) else message=ns.Codec.Decode(text) end
        if not message then return end
        local handle, receipt=true,true
        if eligible then handle,receipt=eligible(message,senderKey) end
        bus.seen[key] = {at=GetTime(),ack=receipt==true}
        if receipt then ack(id) end
        if handle then deliver(message, senderKey, members()[senderKey]) end
    end
    transport.Initialise(bus.Receive, active, log, filter, function(result) log("Party send failed: " .. tostring(result)) end)
    transport.Begin()
    function bus.Cancel()
        transport.Cancel()
        bus.outgoing, bus.controls, bus.assemblies, bus.seen, bus.cancelled, bus.incomingBytes = {}, {}, {}, {}, {}, 0
    end
    function bus.Tick()
        transport.Tick()
        local now, present = GetTime(), members()
        for key in pairs(bus.peers) do if not present[key] then bus.peers[key]=nil end end
        for key, a in pairs(bus.assemblies) do if now - a.created > 90 then removeAssembly(key) end end
        local cancelledCount=0
        for key,at in pairs(bus.cancelled) do
            cancelledCount=cancelledCount+1
            if now-at>90 or cancelledCount>128 then bus.cancelled[key]=nil end
        end
        local count = 0
        for key, seen in pairs(bus.seen) do
            count = count + 1
            if now - seen.at > 90 or count > 128 then bus.seen[key] = nil end
        end
        local selected,selectedId
        for id, item in pairs(bus.outgoing) do
            for key in pairs(item.targets) do if not present[key] then item.targets[key] = nil end end
            if now - item.created > 90 then bus.outgoing[id] = nil; log("Party transfer expired")
            elseif item.at > #item.frames then
                if not next(item.targets) then bus.outgoing[id] = nil
                elseif now - (item.sentAt or now) > 5 and item.retry < 2 then
                    item.at, item.retry = 1, item.retry + 1
                elseif item.retry >= 2 and now - (item.sentAt or now) > 5 then bus.outgoing[id] = nil; log("Party receipt missing") end
            elseif not selected or item.priority < selected.priority or (item.priority == selected.priority and (item.created < selected.created or (item.created==selected.created and item.order<selected.order))) then
                selected,selectedId = item,id
            end
        end
        if not active() or not transport.Ready() then return end
        if bus.controls[1] then
            if transport.Send(bus.controls[1], "PARTY") then table.remove(bus.controls, 1) end
        elseif selected then
            local queued=transport.Send(selected.frames[selected.at], "PARTY", function(sent)
                selected.queued=false
                if bus.outgoing[selectedId]~=selected then return end
                if sent then
                    selected.at,selected.sentAt,selected.failures=selected.at+1,GetTime(),0
                else
                    selected.failures=(selected.failures or 0)+1
                    if selected.failures>=3 then bus.outgoing[selectedId]=nil;log("Party frame could not be sent") end
                end
            end)
            if queued then selected.queued=true end
        end
    end
    return bus
end
