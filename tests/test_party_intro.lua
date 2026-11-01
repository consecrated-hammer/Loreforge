local function eq(a,b,why) assert(a==b,why..": "..tostring(a).." ~= "..tostring(b)) end
local H=assert(loadfile('tests/party-harness.lua'))()
local create,step,untilTrue,members=H.create,H.step,H.untilTrue,H.members
local h,c=create(1),create(2)
local P,Q,g=h.ns.Party,c.ns.Party,h.ns.game
assert(P.OpenLobby())
untilTrue(function()return Q.client~=nil end,20,'invitation delivered')
Q.Join()
untilTrue(function()return Q.client.joined end,20,'host confirms join')
local config={}
for key,value in pairs(h.ns.db) do config[key]=value end
config.rounds,config.perRound,config.readyCheck,config.roundIntro=2,1,false,true
assert(g:Start(config,'retail',members,1));P.HostStarted()
eq(g.phase,'round_intro','the host holds the intro')
untilTrue(function()return c.last.roundIntro==true end,20,'the intro reaches the player',true)
eq(c.last.state,'paused','older clients see a pause')
eq(c.last.question,nil,'the intro carries no question')
eq(c.last.correct,nil,'or answer')
assert(type(c.last.art)=='string','the intro names its art')
untilTrue(function()return c.last.state=='accepting' or c.last.state=='presenting' or c.last.state=='preparing' or c.last.state=='announcing' end,60,'the question follows',true)
assert(not c.last.roundIntro,'the intro ends')
io.write('loreforge Party intro tests passed\n')
