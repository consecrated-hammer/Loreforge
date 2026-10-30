local function eq(a,b,why) assert(a==b,why..': '..tostring(a)..' ~= '..tostring(b)) end
local H=assert(loadfile('tests/party-harness.lua'))()
local h,c=H.create(1),H.create(2)
local P,Q,g=h.ns.Party,c.ns.Party,h.ns.game
h.instance,c.instance=true,true
h.ns.db.readySeconds,h.ns.db.rounds,h.ns.db.perRound=30,1,1
-- Lose the first invitation: the countdown must offer another chance to join.
h.drop=true
assert(P.OpenLobby())
H.step(5)
eq(Q.client,nil,'initial dropped invitation creates no player state')
assert(g:Start(h.ns.db,'retail',H.members,1));P.HostStarted()
h.drop=false
H.untilTrue(function()return g.phase=='ready' end,5,'countdown begins after chat notice',true)
local deadline=g.readyDeadline
eq(math.floor(deadline-H.now()+0.5),30,'host starts with thirty seconds')
H.untilTrue(function()return Q.client and Q.client.model.state=='invitation' end,5,'invitation repeated immediately when countdown starts',true)
assert(g.phase=='ready','late invitation arrives before first question')
Q.Join()
H.untilTrue(function()return Q.client.joined end,10,'player can join during countdown',true)
eq(c.last.state,'ready','joined player sees countdown state')
eq(c.last.config.readySeconds,30,'player receives configured countdown duration')
assert(c.last.deadline>H.now(),'player has remaining start time')
eq(g.readyDeadline,deadline,'joining cannot restart or extend host countdown')
H.untilTrue(function()return c.last.state=='accepting' end,50,'dungeon player proceeds to clickable question',true)
local answer=g.run[g.index].correct
assert(Q.Answer(answer))
H.untilTrue(function()return c.last.locked==answer end,10,'dungeon answer is confirmed by host',true)
io.write('loreforge start countdown and delayed invitation tests passed\n')
