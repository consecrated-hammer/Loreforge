local function eq(a,b,why) assert(a==b,why..': '..tostring(a)..' ~= '..tostring(b)) end
local H=assert(loadfile('tests/party-harness.lua'))()
local h,c=H.create(1),H.create(2)
local P,Q,g=h.ns.Party,c.ns.Party,h.ns.game
local function joined()
    assert(P.OpenLobby())
    H.untilTrue(function()return Q.client and Q.client.model.state=='invitation' end,20,'invite')
    Q.Join();H.untilTrue(function()return Q.client.joined end,20,'join')
end
joined()
local originalSend=P.bus.Send
local droppedOpen=0
P.bus.Send=function(message,...)
    if message.kind=='open' then droppedOpen=droppedOpen+1;return 'deliberately-dropped-open' end
    return originalSend(message,...)
end
h.ns.db.rounds,h.ns.db.perRound,h.ns.db.readyCheck=1,1,false
assert(g:Start(h.ns.db,'retail',H.members,1));P.HostStarted()
c.drop=true
H.untilTrue(function()return g.phase=='presenting' end,15,'presentation gate',true)
local gated=H.now()
eq(g.deadline,nil,'not open during presentation')
H.step(5,true)
eq(g.phase,'presenting','missing presented ACK waits')
H.untilTrue(function()return g.phase=='accepting' end,20,'bounded fallback opens without one client',true)
assert(H.now()-gated>=12,'gate timeout cannot open early')
local deadline=g.deadline
P.Receive({v=1,kind='presented',id=P.host.id,to='host-realm',index=g.index,attempt=g.attempt,revision=1},'guest-realm',H.members[2])
eq(g.deadline,deadline,'late or duplicate ACK cannot extend deadline')
c.drop=false
H.untilTrue(function()return c.last.state=='accepting' end,15,'periodic clock recovers a lost open message',true)
eq(droppedOpen,1,'open packet was actually omitted')
P.bus.Send=originalSend
assert(Q.Answer(g.run[1].correct))
H.untilTrue(function()return c.last.locked~=nil end,10,'reliable answer after loss',true)
g:Close()
-- Stop during final chat output must not create a completed history record.
local id=P.host.id
g:Stop();H.step(3)
assert(not h.ns.db.matches.retail.byId[id],'no completed history before final announcements')
assert(not c.ns.db.matches.retail.byId[id],'aborted game not synced as complete')
-- Explicit decline, consent and competing hosts.
Q.Leave();assert(Q.client==nil)
P.host=nil
joined()
local firstId=Q.client.id
Q.Receive({v=1,kind='invite',to='*',id='chat-realm:new',config=P.host.config},'chat-realm',H.members[3])
eq(Q.client.id,firstId,'competing host cannot replace joined match')
Q.Receive({v=1,kind='joined',to='guest-realm',id=firstId,seq=999,state='accepting'},'host-realm',H.members[1])
eq(Q.client.id,firstId,'malformed joined payload harmless')
-- Pause while presenting voids the old attempt; resume creates a fresh question.
assert(g:Start(h.ns.db,'retail',H.members,2));P.HostStarted()
H.untilTrue(function()return g.phase=='presenting' end,20,'second presentation',true)
local attempt=g.attempt
g:Pause('test pause')
eq(g.attempt,attempt+1,'pause invalidates presentation attempt')
H.step(2)
P.Receive({v=1,kind='answer',id=P.host.id,to='host-realm',index=1,attempt=attempt,choice=1},'guest-realm',H.members[2])
eq(next(g.answers),nil,'stale UI answer rejected')
assert(g:Resume())
H.untilTrue(function()return c.last.state=='accepting' and c.last.attempt==g.attempt end,30,'resumed attempt opens',true)
-- Native restrictions cancel queued work and disable clicks, then allow resync.
c.combat=true;H.step(1)
eq(c.last.state,'disconnected','combat visibly suspends player view')
local count=c.sent
assert(not Q.Answer(1),'restricted client cannot submit')
H.step(1)
eq(c.sent,count,'no queued native sends in combat')
c.combat=false;Q.RequestSync()
H.untilTrue(function()return c.last.state~='disconnected' end,30,'resync after restrictions',true)
-- Activity restrictions and chat lockdown still block dungeon traffic outside combat.
h.instance,c.instance=true,true
for _, flag in ipairs({'restricted','lockdown'}) do
    c[flag]=true; H.step(1)
    eq(c.last.state,'disconnected',flag .. ' visibly suspends player view')
    local sent=c.sent
    assert(not Q.Answer(1),flag .. ' prevents answer clicks')
    H.step(1);eq(c.sent,sent,flag .. ' blocks native traffic')
    c[flag]=false;Q.RequestSync()
    H.untilTrue(function()return c.last.state~='disconnected' end,30,flag .. ' recovery inside dungeon',true)
end
-- A previously joined character can restore the match after leaving/rejoining the Party.
local guest=table.remove(H.members,2)
g:Pause('roster changed')
H.step(2)
assert(P.host.joined['guest-realm']==nil,'departed member removed from active recipients')
table.insert(H.members,2,guest)
Q.RequestSync();H.step(6)
assert(P.host.joined['guest-realm'],'original consenting member can restore the active session')
assert(g:Resume())
H.untilTrue(function()return c.last.state=='accepting' end,30,'restored participant can play',true)
-- Fragment allocation is bounded per sender as well as globally; conflicts discard.
local bus=Q.bus
bus.Cancel()
local before=bus.incomingBytes
for i=1,20 do
    local frame=table.concat({'1','flood-'..i,1,2,161,'00000000',string.rep('x',160)},'|')
    bus.Receive(nil,frame,'PARTY','Host-Realm')
end
local n=0;for _ in pairs(bus.assemblies)do n=n+1 end
eq(n,2,'one sender cannot fill all assembly slots')
assert(bus.incomingBytes-before<=320,'fragment bytes bounded')
bus.Receive(nil,table.concat({'1','flood-1',1,2,161,'00000000',string.rep('y',160)},'|'),'PARTY','Host-Realm')
n=0;for _ in pairs(bus.assemblies)do n=n+1 end
eq(n,1,'conflicting duplicate invalidates assembly')
bus.Receive(nil,'1|bad|1|999|99999|00000000|x','PARTY','Host-Realm')
H.step(91)
eq(next(bus.assemblies),nil,'unfinished assemblies expire')
-- Urgent short packets retain capacity alongside two bulk assemblies.
bus.Cancel()
for i=1,2 do bus.Receive(nil,table.concat({'1','bulk-'..i,1,5,641,'00000000',string.rep('x',160)},'|'),'PARTY','Host-Realm') end
bus.Receive(nil,table.concat({'1','urgent',1,2,161,'00000000',string.rep('y',160)},'|'),'PARTY','Host-Realm')
n=0;for _ in pairs(bus.assemblies)do n=n+1 end
eq(n,3,'bulk assemblies cannot block a short answer receipt')
-- A queued frame does not count as delivered; failed native sends retain its index.
P.bus.Cancel()
local failedPacket=assert(P.bus.Send({v=1,kind='ping',id=P.host.id,to='guest-realm'},{['guest-realm']=true},0))
local failedItem=P.bus.outgoing[failedPacket]
h.sendResult=5
P.bus.Tick()
eq(failedItem.at,1,'enqueue does not advance a frame')
H.untilTrue(function()return P.bus.outgoing[failedPacket]==nil end,15,'bounded native frame retries')
eq(failedItem.at,1,'rejected native sends cannot advance a frame')
h.sendResult=nil
-- Recovery cannot expose a historical record to a non-participant.
local result={version=1,id='host-realm:old',host='Host-Realm',date=1800000000,config=P.host.config,rows={},rounds={},totalQuestions=1}
h.ns.db.matches.retail.byId[result.id]={text=assert(h.ns.Codec.Encode(result)),allowed={['guest-realm']=true}}
local packets=0;for _ in pairs(P.bus.outgoing)do packets=packets+1 end
P.Receive({v=1,kind='sync',id=result.id,to='host-realm'},'chat-realm',H.members[3])
local after=0;for _ in pairs(P.bus.outgoing)do after=after+1 end
eq(after,packets,'history catch-up requires previous consent')
-- Click feedback is local; readiness/answer confirmation remains host-owned.
do
    local R=assert(loadfile('tests/party-harness.lua'))()
    local host,client=R.create(1),R.create(2)
    local A,B,game=host.ns.Party,client.ns.Party,host.ns.game
    host.ns.db.readySeconds=30
    assert(A.OpenLobby());R.untilTrue(function()return B.client end,20,'feedback invite')
    B.Join();R.untilTrue(function()return B.client.joined end,20,'feedback join')
    assert(game:Start(host.ns.db,'retail',R.members,1));A.HostStarted()
    R.untilTrue(function()return client.last.state=='ready' end,20,'feedback ready state',true)
    local send=B.bus.Send
    B.bus.Send=function(m,...) if m.kind=='ready' then return 'lost-ready-request' end;return send(m,...) end
    assert(B.Ready())
    assert(client.last.readyPending,'ready click renders before any host reply')
    assert(not game.players['guest-realm'].ready,'local pending is not host confirmation')
    assert(not B.Ready(),'pending readiness cannot be submitted twice')
    A.host.dirty=true;R.step(2)
    assert(client.last.readyPending,'unconfirmed snapshots preserve pending feedback')
    R.step(4)
    assert(not client.last.readyPending and client.last.readyStatus,'lost readiness offers retry')
    B.bus.Send=function(m,...) if m.kind=='ready' then return nil,'queue full' end;return send(m,...) end
    assert(not B.Ready(),'queue failure is reported immediately')
    assert(not client.last.readyPending and client.last.readyStatus:find('Could not send',1,true),'queue failure is not left pending')
    B.bus.Send=send;assert(B.Ready())
    R.untilTrue(function()return client.last.ready==true end,15,'host confirms readiness',true)
    assert(not client.last.readyPending,'host confirmation clears pending feedback')
    R.untilTrue(function()return client.last.state=='accepting' end,50,'feedback question',true)
    B.bus.Send=function(m,...) if m.kind=='answer' then return nil,'queue full' end;return send(m,...) end
    assert(not B.Answer(2),'answer queue failure is immediate')
    assert(client.last.selected==2 and not client.last.pending,'failed send keeps chosen answer with retry feedback')
    assert(not B.Answer(3),'failed send cannot change the original chosen answer')
    B.bus.Send=send;assert(B.RetryAnswer())
    assert(client.last.pending and not client.last.locked,'answer retry immediately shows sending')
    R.untilTrue(function()return client.last.locked==2 end,15,'host confirms retried answer',true)
end
io.write('loreforge Party failure/recovery tests passed\n')
