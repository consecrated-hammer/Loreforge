for _,legacyIndex in ipairs({1,2}) do
    local H=assert(loadfile('tests/party-harness.lua'))()
    local h,c=H.create(1),H.create(2)
    local old=legacyIndex==1 and h or c
    old.ns.WireCodec.Available=function()return false end
    -- Model the old parser: only frame 1 and receipts are recognized.
    local receive=old.ns.Party.bus.Receive
    old.ns.Party.bus.Receive=function(prefix,text,...)
        assert(not text:match('^2|'),'legacy recipient received binary')
        return receive(prefix,text,...)
    end
    local P,Q,g=h.ns.Party,c.ns.Party,h.ns.game
    assert(P.OpenLobby());H.untilTrue(function()return Q.client end,20,'legacy invite')
    Q.Join();H.untilTrue(function()return Q.client.joined end,20,'legacy joined')
    assert(g:Start(h.ns.db,'retail',H.members,1));P.HostStarted()
    H.untilTrue(function()return c.last.state=='ready' end,20,'legacy ready',true)
    Q.Ready()
    for index=1,2 do
        H.untilTrue(function()return c.last.state=='accepting' and c.last.index==index end,60,'legacy question',true)
        Q.Answer(g.run[g.index].correct)
        H.untilTrue(function()return c.last.locked end,20,'legacy answer',true)
        g:Close()
        if index==1 then H.untilTrue(function()return g.phase=='between' end,20,'legacy between',true);assert(g:Next()) end
    end
    H.untilTrue(function()return c.last.state=='finished' and not c.last.resultsPending end,90,'legacy saved result',true)
    local id=P.host.id
    local entry=c.ns.db.matches.retail.byId[id]
    assert(entry.text==h.ns.db.matches.retail.byId[id].text,'canonical history compatible')
    Q.OpenHistory(id);assert(c.last.state=='finished','old saved history opens')
end
print('loreforge legacy/new full-game compatibility tests passed')
