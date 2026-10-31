local function eq(a,b,why) assert(a==b,why..": "..tostring(a).." ~= "..tostring(b)) end
local clock=100
local clients={}
local members={{key="host-realm",name="Host-Realm",guid="H"},{key="guest-realm",name="Guest-Realm",guid="G"},{key="chat-realm",name="Chat-Realm",guid="C"}}
local function create(index,saved)
    local c={index=index,logs={},models={},sent=0,drop=false}
    local who=members[index]
    local e=setmetatable({}, {__index=_G});e._G=e;e.LibStub,e.ChatThrottleLib=false,false
    e.GetTime=function() return clock end
    e.GetServerTime=function() return 1800000000+math.floor(clock) end
    e.GetFramerate=function() return c.fps or 60 end
    e.IsInInstance=function() return c.instance or false, c.instance and "party" or "none" end
    e.InCombatLockdown=function() return c.combat end
    e.Enum={SendAddonMessageResult={Success=0,AddonMessageThrottle=3,GeneralError=9}}
    e.issecretvalue=function() return false end
    e.hooksecurefunc=function() end
    e.securecallfunction=function(fn,...) return fn(...) end
    e.geterrorhandler=function() return function(err) error(err) end end
    local nativeXpcall=xpcall
    e.xpcall=function(fn,handler,...)
        local args,n={...},select('#',...)
        return nativeXpcall(function() return fn(unpack(args,1,n)) end,handler)
    end
    e.table=setmetatable({wipe=function(t) for k in pairs(t) do t[k]=nil end end},{__index=table})
    e.CreateFrame=function() return {Show=function() end,Hide=function() end,RegisterEvent=function() end,SetScript=function(self,key,fn) self[key]=fn end} end
    e.C_ChatInfo={RegisterAddonMessagePrefix=function() return 0 end,InChatMessagingLockdown=function() return c.lockdown or false end,
        SendAddonMessage=function(prefix,text,channel)
            c.sent=c.sent+1
            if c.sendResult then return c.sendResult end
            if not c.drop then
                for _,other in ipairs(clients) do other.ns.Party.bus.transport.Receive(prefix,text,channel,who.name) end
            end
            return 0
        end}
    local ns={era="retail",db=saved or {rounds=2,perRound=1,seconds=20,readyCheck=true,readySeconds=5,channel="PARTY",categories={lore=true},difficulty="mixed",replayRecords=false},
        Restricted=function() return c.combat or c.restricted end,Identity=function(name) return name:lower() end,
        Person=function() return who end,Roster=function() return members end,RefreshHost=function() end,
        HammerCore={Print=function(s)c.logs[#c.logs+1]=s end,Commands={Add=function() end}},
        Player={Render=function(m) c.last=m;c.models[#c.models+1]=m end,Show=function()end,Hide=function()end}}
    c.ns=ns
    for _,file in ipairs({'Libs/LibStub/LibStub.lua','Libs/ChatThrottleLib/ChatThrottleLib.lua','Libs/LibDeflate/LibDeflate.lua','Libs/LibSerialize/LibSerialize.lua','Transport.lua','Codec.lua','WireCodec.lua','PartyBus.lua','Game.lua','Party.lua'}) do setfenv(assert(loadfile(file)),e)('Loreforge',ns) end
    local bank={{'Question one?','Right','Wrong','Other','No',id='1'},{'Question two?','Yes','No','Maybe','Never',id='2'}}
    ns.game=ns.Game.New(bank,e.GetTime,function(n)return n end,{})
    c.e=e
    clients[#clients+1]=c
    ns.Party.Initialise()
    return c
end
local function step(seconds,chat)
    for _=1,seconds*10 do
        clock=clock+0.1
        for _,c in ipairs(clients) do
            c.ns.Party.Tick()
            c.e.ChatThrottleLib.OnUpdate(c.e.ChatThrottleLib.Frame,0.1)
        end
        if chat then
            local g=clients[1].ns.game
            g:Tick()
            local line=g:NextMessage()
            if line and clients[1].ns.Party.CanPostQuestion() then
                g:Sent();g:Echo(line)
                for _,other in ipairs(clients) do other.ns.Party.Chat(line,members[1].name,"PARTY") end
            end
        end
    end
end
-- Drive the real addon frame handlers instead of bypassing their cadence.
local function stepFrames(seconds, fps, chat, ctlFirst)
    local delta = 1 / fps
    for _ = 1, math.floor(seconds * fps + 0.5) do
        clock = clock + delta
        for _, c in ipairs(clients) do
            c.fps = fps
            if ctlFirst then c.e.ChatThrottleLib.OnUpdate(c.e.ChatThrottleLib.Frame,delta) end
            c.ns.Party.frame.OnUpdate(c.ns.Party.frame,delta)
            if not ctlFirst then c.e.ChatThrottleLib.OnUpdate(c.e.ChatThrottleLib.Frame,delta) end
        end
        if chat then
            local g=clients[1].ns.game
            g:Tick()
            local line=g:NextMessage()
            if line and clients[1].ns.Party.CanPostQuestion() then
                g:Sent();g:Echo(line)
                for _,other in ipairs(clients) do other.ns.Party.Chat(line,members[1].name,"PARTY") end
            end
        end
    end
end
local function untilTrue(fn,seconds,why,chat)
    for _=1,seconds*10 do if fn() then return end;step(0.1,chat) end
    if not fn() then
        for _,c in ipairs(clients) do
            io.stderr:write('client ',c.index,' phase=',c.ns.game.phase,' view=',c.last and c.last.state or 'none','\n')
            for _,line in ipairs(c.ns.Party.logs) do io.stderr:write(line,'\n') end
        end
    end
    assert(fn(),why)
end

return {create=create,step=step,stepFrames=stepFrames,untilTrue=untilTrue,clients=clients,members=members,now=function() return clock end}
