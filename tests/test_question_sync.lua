local function eq(a,b,why) assert(a==b,why..': '..tostring(a)..' ~= '..tostring(b)) end
-- Actual Party and CTL frame callbacks at high and low FPS, in either order.
for _,fps in ipairs({100,5}) do
 for _,ctlFirst in ipairs({false,true}) do
    local H=assert(loadfile('tests/party-harness.lua'))()
    local h,c=H.create(1),H.create(2)
    local P,Q,g=h.ns.Party,c.ns.Party,h.ns.game
    local function wait(fn,seconds,chat)
        for _=1,seconds*fps do if fn() then return end;H.stepFrames(1/fps,fps,chat,ctlFirst) end
        assert(fn(),'frame-driven question sync timed out')
    end
    assert(P.OpenLobby());wait(function()return Q.client end,30)
    Q.Join();wait(function()return Q.client.joined end,30)
    h.ns.db.readyCheck,h.ns.db.rounds,h.ns.db.perRound=false,1,1
    local shownAt,hostAt
    local render=c.ns.Player.Render
    c.ns.Player.Render=function(m)
        render(m)
        if m.state=='announcing' and m.question and not shownAt then shownAt=H.now() end
    end
    local echo=g.Echo
    g.Echo=function(self,text)
        local first=self.phase=='announcing' and self.cursor==self.questionCursor
        local accepted=echo(self,text)
        if first and accepted then hostAt=H.now() end
        return accepted
    end
    -- Lose the addon SHOW signal: the public chat event must reveal the cache.
    local send=P.bus.Send
    P.bus.Send=function(message,...)
        if message.kind=='show' then return 'intentionally-lost-show' end
        return send(message,...)
    end
    assert(g:Start(h.ns.db,'retail',H.members,1));P.HostStarted()
    P.host.dirty=true;H.stepFrames(1/fps,fps,false,ctlFirst)
    assert(P.host.dirty,'gated snapshots keep state changes pending')
    assert(not g.questionVisible,'host cannot see question before first chat echo')
    wait(function()return hostAt end,30,true)
    assert(P.host.preparation and not next(P.host.preparation.pending),'preparation confirmed before chat')
    eq(shownAt,hostAt,'host and player reveal on the same simulated chat event')
    eq(c.last.state,'announcing','client can read during chat posting')
    eq(g.deadline,nil,'reading does not start the answer clock')
    assert(not Q.Answer(1),'early reading cannot submit an answer')
    wait(function()return c.last.state=='accepting' end,30,true)
    assert(g.deadline and g.phase=='accepting','only authoritative opening enables answers')
    local phase=g.phase
    for _,flag in ipairs({true,false}) do
        P.Receive({v=1,kind='join',id=P.host.id,to='host-realm',earlyQuestions=flag},'chat-realm')
    end
    eq(g.phase,phase,'rejected capability negotiation cannot pause the active game')
    eq(P.host.early['chat-realm'],nil,'rejected join cannot store feature flags')
    local answer=g.run[g.index].correct
    assert(Q.Answer(answer));wait(function()return c.last.locked==answer end,15,true)
 end
end
-- A lost preparation receipt cannot hold the first line forever, and repeated
-- sync requests cannot reset the bounded fallback or preparation identity.
do
    local H=assert(loadfile('tests/party-harness.lua'))()
    local h,c=H.create(1),H.create(2)
    local P,Q,g=h.ns.Party,c.ns.Party,h.ns.game
    assert(P.OpenLobby());H.untilTrue(function()return Q.client end,20,'timeout invite')
    Q.Join();H.untilTrue(function()return Q.client.joined end,20,'timeout join')
    local send=Q.bus.Send
    Q.bus.Send=function(m,...) if m.kind=='prepared' then return 'lost-prepared' end;return send(m,...) end
    h.ns.db.readyCheck=false
    assert(g:Start(h.ns.db,'retail',H.members,1));P.HostStarted()
    local rules=g:NextMessage();g:Sent();g:Echo(rules)
    eq(g:NextMessage(),nil,'initial first-line hold')
    local prep=P.host.preparation
    local revision,deadline=prep.revision,prep.deadline
    P.Receive({v=1,kind='sync',id=P.host.id,to='host-realm',earlyQuestions=true},'guest-realm')
    eq(prep.revision,revision,'resync preserves preparation identity')
    eq(prep.deadline,deadline,'resync cannot extend first-line hold')
    P.Receive({v=1,kind='prepared',id=P.host.id,to='host-realm',index=1,attempt=0,revision=revision},'guest-realm')
    assert(prep.pending['guest-realm'],'stale preparation ACK cannot release the hold')
    H.stepFrames(deadline-H.now()-0.02,100,false)
    eq(g:NextMessage(),nil,'missing ACK still holds before twelve seconds')
    assert(not g.questionVisible,'timeout waiting cannot reveal host question')
    H.stepFrames(0.04,100,false)
    assert(g:NextMessage(),'bounded fallback releases the first public line')
    H.stepFrames(0.1,100,false) -- read-only getters leave notices to the next protocol tick
    assert(prep.warned,'fallback is explicitly reported')
    eq(g.deadline,nil,'fallback does not enable answers')
end
-- Preparing is optional for older peers; their normal post-chat flow remains.
do
    local H=assert(loadfile('tests/party-harness.lua'))()
    local h,c=H.create(1),H.create(2)
    local P,Q,g=h.ns.Party,c.ns.Party,h.ns.game
    assert(P.OpenLobby());H.untilTrue(function()return Q.client end,20,'legacy invite')
    local send=Q.bus.Send
    Q.bus.Send=function(m,...)
        if m.kind=='join' then m.earlyQuestions=nil end
        if m.kind=='presented' then assert(c.last.state=='presenting','legacy announcing needs no presentation receipt') end
        return send(m,...)
    end
    Q.Join();H.untilTrue(function()return Q.client.joined end,20,'legacy join')
    h.ns.db.readyCheck=false
    assert(g:Start(h.ns.db,'retail',H.members,1));P.HostStarted()
    H.untilTrue(function()return c.last.state=='accepting' end,30,'legacy post-chat path',true)
    eq(P.host.preparation,nil,'no hidden preparation sent to incompatible peer')
    P.Receive({v=1,kind='leave',id=P.host.id,to='host-realm'},'guest-realm')
    eq(P.host.early['guest-realm'],nil,'explicit leave clears participant capability')
    local phase=g.phase
    P.Receive({v=1,kind='join',id=P.host.id,to='host-realm',earlyQuestions=true},'guest-realm')
    P.Receive({v=1,kind='sync',id=P.host.id,to='host-realm'},'guest-realm')
    eq(g.phase,phase,'a departed participant cannot pause via capability negotiation')
end
io.write('loreforge shared question reveal tests passed\n')
