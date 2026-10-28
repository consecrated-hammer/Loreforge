local function eq(a,b,why) assert(a==b,why..": "..tostring(a).." ~= "..tostring(b)) end
local H=assert(loadfile('tests/party-harness.lua'))()
local create,step,untilTrue,clients,members=H.create,H.step,H.untilTrue,H.clients,H.members
local h,c=create(1),create(2)
local P,Q,g=h.ns.Party,c.ns.Party,h.ns.game
assert(P.OpenLobby())
untilTrue(function()return Q.client~=nil end,20,'invitation delivered')
eq(c.last.state,'invitation','explicit invitation')
Q.Join()
untilTrue(function()return Q.client.joined end,20,'host confirms join')
eq(c.last.state,'lobby','joined lobby')
step(35)
eq(c.last.state,'lobby','idle host lobby heartbeats prevent false disconnect')
assert(g:Start(h.ns.db,'retail',members,1));P.HostStarted()
untilTrue(function()return c.last.state=='ready' end,20,'ready view',true)
Q.Ready()
untilTrue(function()return g.players['guest-realm'].ready end,10,'ready through shared engine',true)
untilTrue(function()return g.phase=='presenting' end,20,'final chat echo enters presentation gate',true)
eq(g.deadline,nil,'no answer deadline before delivery')
assert(not g:Answer('chat-realm','1','C'),'chat cannot answer before open')
untilTrue(function()return c.last.state=='accepting' end,30,'question delivered and opens',true)
eq(c.last.correct,nil,'correct answer not sent before reveal')
local correct=g.run[g.index].correct
assert(Q.Answer(correct));assert(not Q.Answer(correct%4+1),'click cannot change first attempt')
untilTrue(function()return c.last.locked~=nil end,10,'host confirms click',true)
eq(g.answers['guest-realm'],correct,'shared Game.Answer owns click')
assert(g:Answer('chat-realm',tostring(correct),'C'),'chat-only answer uses same engine')
g:Close()
untilTrue(function()return c.last.state=='between' or c.last.state=='revealing' end,20,'reveal delivered',true)
eq(c.last.correct,correct,'reveal includes correct answer')
eq(g.players['guest-realm'].streak,1,'first streak')
untilTrue(function()return g.phase=='between' end,20,'round chat completes',true)
assert(g:Next())
untilTrue(function()return c.last.state=='accepting' and c.last.index==2 end,30,'next question',true)
correct=g.run[g.index].correct
-- Chat wins the race. The click receipt must return the authoritative chat choice.
assert(g:Answer('guest-realm',tostring(correct),'G'))
Q.Answer(correct%4+1)
untilTrue(function()return c.last.locked~=nil end,10,'chat winner acknowledged',true)
eq(c.last.locked,correct,'click retry cannot replace chat answer')
assert(g:Answer('chat-realm',tostring(correct),'C'))
g:Close()
untilTrue(function()return g.recorded and c.last.state=='finished' and c.last.resultsPending==false end,90,'finalized shared results',true)
eq(g.players['guest-realm'].total,2,'score correct')
eq(g.players['guest-realm'].streak,2,'streak carried')
local id=P.host.id
local hostEntry=h.ns.db.matches.retail.byId[id]
local guestEntry=c.ns.db.matches.retail.byId[id]
assert(hostEntry and guestEntry,'saved on both clients')
eq(hostEntry.text,guestEntry.text,'canonical result identical')
local result=h.ns.Codec.Decode(hostEntry.text)
eq(#result.rounds,2,'round summaries retained')
eq(result.rows[1].rank,result.rows[2].rank,'shared winners preserve tied rank')
local count=#c.ns.db.matches.retail.order
Q.Receive({v=1,kind='result',id=id,to='guest-realm',result=result},'host-realm',members[1])
eq(#c.ns.db.matches.retail.order,count,'duplicate result not rescored or duplicated')
result.rows[1].total=99
Q.Receive({v=1,kind='result',id=id,to='guest-realm',result=result},'host-realm',members[1])
eq(guestEntry.text,hostEntry.text,'conflicting result rejected')
local old=c.last
Q.Receive({v=1,kind='snapshot',id=id,to='guest-realm',seq=999,state='accepting'},'chat-realm',members[3])
eq(c.last,old,'other roster member cannot impersonate selected host')
-- Reload catch-up is restricted to previously joined recipients.
clients[2]=nil
local reloaded=create(2,c.ns.db)
untilTrue(function()return reloaded.last and reloaded.last.state=='finished' end,90,'participant reload catches finalized result')
eq(reloaded.ns.db.matches.retail.byId[id].text,hostEntry.text,'reload keeps result immutable')
-- Decoder and parser bounds, malformed lengths, duplicate keys and executable data.
assert(not h.ns.Codec.Decode('return os.execute("bad")'))
assert(not h.ns.Codec.Decode('m2:s1:an1:s1:an2:'))
assert(not h.ns.Codec.Decode('s99999999999999:x'))
local encoded=assert(h.ns.Codec.Encode({a='UTF-8: Ünïcödé',b={1,2,3},flag=true}))
eq(h.ns.Codec.Encode(h.ns.Codec.Decode(encoded)),encoded,'canonical codec round trip')
-- A delayed final for a previously joined match is accepted while a newer lobby is active.
local delayed=h.ns.Codec.Decode(hostEntry.text)
delayed.id='host-realm:delayed-final'
c.ns.db.pendingMatches[delayed.id]={hostKey='host-realm',date=1800000000}
reloaded.ns.db.pendingMatches[delayed.id]={hostKey='host-realm',date=1800000000}
assert(P.OpenLobby())
untilTrue(function()return reloaded.ns.Party.client and reloaded.ns.Party.client.id==P.host.id end,20,'new lobby arrives')
local currentId=reloaded.ns.Party.client.id
assert(P.bus.Send({v=1,kind='result',id=delayed.id,to='*',result=delayed},{['guest-realm']=true},3))
untilTrue(function()return reloaded.ns.db.matches.retail.byId[delayed.id]~=nil end,60,'delayed final stored across sessions')
eq(reloaded.ns.Party.client.id,currentId,'old completed result cannot replace current invitation')
-- The largest allowed party/round structure still fits the bounded codec.
local large={version=1,id=string.rep('i',180),host=string.rep('h',120),date=1800000000,
 config={rounds=20,perRound=50,seconds=120,categories=string.rep('c',512),difficulty='mixed',readyCheck=true},rows={},rounds={},totalQuestions=1000}
for i=1,5 do
 large.rows[i]={key=string.rep('k',115)..i,name=string.rep('n',120),total=1000,round=50,streak=1000,bestStreak=1000,answered=1000,rank=1,winner=true,ready=true,inAddon=true}
end
for round=1,20 do
 large.rounds[round]={round=round,rows={}}
 for i=1,5 do large.rounds[round].rows[i]={key=large.rows[i].key,round=50,total=1000,streak=1000,bestStreak=1000,answered=1000,rank=1} end
end
local largeText=assert(h.ns.Codec.Encode(large),'maximum completed result fits codec')
assert(h.ns.Codec.Decode(largeText),'maximum completed result decodes within complexity bound')

-- Idle addon clients do not acknowledge somebody else's targeted traffic.
local idle=create(3)
local before=idle.sent
assert(P.bus.Send({v=1,kind='ping',id=P.host.id,to='guest-realm'},{['guest-realm']=true},1))
step(4)
eq(idle.sent,before,'targeted messages generate no irrelevant receipts')
-- Repeated catch-up requests coalesce a pending final instead of restarting it.
local function packetCount()local n=0;for _ in pairs(P.bus.outgoing)do n=n+1 end;return n end
P.Receive({v=1,kind='sync',id=id,to='host-realm'},'guest-realm',members[2])
local countAfter=packetCount()
P.Receive({v=1,kind='sync',id=id,to='host-realm'},'guest-realm',members[2])
eq(packetCount(),countAfter,'duplicate catch-up request reuses pending result transfer')
P.OpenLobby()
untilTrue(function()return idle.last and idle.last.state=='invitation' end,20,'idle client offered lobby')
P.CloseLobby()
untilTrue(function()return idle.last and idle.last.state=='stopped' end,20,'cancel reaches invitee before joining')
io.write('loreforge Party integration tests passed\n')
