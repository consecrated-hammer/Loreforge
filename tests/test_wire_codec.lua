local H=assert(loadfile('tests/party-harness.lua'))()
local h,c=H.create(1),H.create(2)
local W,C=h.ns.WireCodec,h.ns.Codec
local lib=h.e.LibStub('LibSerialize')
local calls,original=0,lib.Deserialize
lib.Deserialize=function(...) calls=calls+1;return original(...) end
local function rejected(s)
    local before=calls
    assert(not W.Decode(s),'unsafe payload accepted')
    assert(calls==before,'unsafe payload reached upstream')
end
local function roundtrip(v)
    local text=assert(W.Encode(v),'encode')
    local decoded=assert(W.Decode(text),'decode')
    assert(C.Encode(v)==C.Encode(decoded),'roundtrip fidelity')
    return text
end
roundtrip({n=-1000000000000,z=0,p=1000000000000,b=false,t=true,s='\0|\255',a={'repeat','repeat','repeat'}})
for _,n in ipairs({0,127,128,4095,4096,65535,65536,16777215,16777216,4294967295,4294967296}) do roundtrip({n=n,neg=-n}) end
local v={};local p=v
for _=1,7 do p.child={};p=p.child end
p.leaf='depth8';roundtrip(v)
p.extra={x=true};assert(not W.Encode(v));rejected(lib:Serialize(v))
local a={};for i=1,128 do a[i]=i end;roundtrip(a)
a[129]=true;rejected(lib:Serialize(a));assert(not W.Encode(a))
rejected(lib:Serialize({s=string.rep('s',4097)}))
rejected(lib:Serialize({n=1.5}));rejected(lib:Serialize({n=1/0}))
rejected(lib:Serialize({n=1000000000001}));rejected(lib:Serialize({[0]='bad'}))
rejected(lib:Serialize({[1001]='bad'}));rejected(lib:Serialize({[false]='bad'}))
rejected(lib:Serialize({[{}]='bad'}))
local cyclic={};cyclic.self=cyclic;rejected(lib:Serialize(cyclic))
local shared={a={x=1}};shared.b=shared.a;assert(not W.Encode(shared));rejected(lib:Serialize(shared))
local text=roundtrip({a='a long repeated string',b='a long repeated string'})
for i=0,#text-1 do rejected(text:sub(1,i)) end
rejected(text..'\0');rejected(lib:Serialize({},{}));rejected(lib:Serialize('scalar'))
rejected(string.char(1,26,18,16,255,255,255)) -- nested enormous declared map
rejected(string.char(1,26,18,16,1)) -- container at depth9 before reading descendants
rejected(string.char(1,26,208,1)) -- unknown backward string reference
rejected(string.char(1,26,2,208,0)) -- invalid string ref as a value
-- A two-entry map repeats the same key. Upstream would overwrite it.
rejected(string.char(1,38,18)..'k'..string.char(3,18)..'k'..string.char(5))
-- One array entry and one map entry collide at key 1.
rejected(string.char(1,14,3,3,5))
-- Compact string references must not bypass the 32 KiB expanded legacy budget.
local expanded={};for i=1,9 do expanded[i]=string.rep('a',4096) end
rejected(lib:Serialize(expanded))
-- Malformed compact encodings and lengths must fail before upstream runs.
for _,raw in ipairs({
    string.char(1,26,112,255), -- string length exceeds remaining input
    string.char(1,26,128,255,255,255), -- huge string
    string.char(1,26,152,255,255,255), -- huge map
    string.char(1,26,176,255,255,255), -- huge array
    string.char(1,26,200,255,255,255,255,255,255), -- huge mixed
    string.char(1,26,232,1), -- table reference
    string.char(1,26,0), -- nil map key
    string.char(1,26,18)..'x'..string.char(0), -- nil map value
}) do rejected(raw) end
-- Deterministic malformed-input sweep. Preflight acceptance must agree with
-- upstream decoding and the canonical policy, including arbitrary binary bytes.
math.randomseed(123)
for _=1,3000 do
    local bytes={string.char(1)}
    for _=1,math.random(1,40) do bytes[#bytes+1]=string.char(math.random(0,255)) end
    local raw=table.concat(bytes)
    if W.Check(raw) then assert(W.Decode(raw) and C.Encode(W.Decode(raw))) else rejected(raw) end
end
local many={}
for i=1,64 do many[i]={};for j=1,64 do many[i][j]=true end end
rejected(lib:Serialize(many)) -- implicit array keys count toward 8192 nodes
-- Runtime version selection is shared via LibStub: uninspected minors fall back.
h.e.LibStub.minors.LibSerialize=8;assert(not W.Available());assert(not W.Encode({x=1}));assert(not W.Decode(text))
h.e.LibStub.minors.LibSerialize=7
local P,Q=h.ns.Party,c.ns.Party
assert(P.OpenLobby());H.untilTrue(function()return Q.client end,20,'invite')
local session=P.host.id
local function version(bus,id) return assert(bus.outgoing[id]).version end
local id=P.bus.Send({id=session,kind='snapshot'},{['guest-realm']=true})
assert(version(P.bus,id)=='1','unknown peer legacy')
Q.Join();H.untilTrue(function()return Q.client.joined end,20,'join')
assert(P.bus.peers['guest-realm'].supported and Q.bus.peers['host-realm'].supported,'bidirectional negotiation')
id=P.bus.Send({id=session,kind='snapshot'},{['guest-realm']=true},1,'test')
assert(version(P.bus,id)=='2','new peers binary')
local old=id
P.bus.SetPeer('guest-realm',session,false)
assert(not P.bus.outgoing[old],'downgrade cancels old packet')
local fallback
for packet,item in pairs(P.bus.outgoing) do if item.replace=='test' then fallback=packet end end
assert(fallback and fallback~=old and version(P.bus,fallback)=='1','downgrade new legacy packet')
P.bus.SetPeer('guest-realm',session,true)
id=P.bus.Send({id=session,kind='snapshot'},{['guest-realm']=true,['chat-realm']=true});assert(version(P.bus,id)=='1','mixed recipients')
id=P.bus.Send({id=session,kind='snapshot'},{});assert(version(P.bus,id)=='1','empty recipients')
for _,kind in ipairs({'invite','join','sync'}) do
 id=P.bus.Send({id=session,kind=kind},{['guest-realm']=true},1,kind);assert(version(P.bus,id)=='1','bootstrap legacy')
end
-- Fallback preserves scheduling/lifetime and only affects unacknowledged peers.
P.bus.outgoing={}
local ids={}
for _,kind in ipairs({'show','open','snapshot'}) do
    ids[#ids+1]=assert(P.bus.Send({id=session,kind=kind},{['guest-realm']=true},1,kind))
end
local before={}
for _,packet in ipairs(ids) do
    local item=P.bus.outgoing[packet]
    before[item.replace]={created=item.created,order=item.order}
end
P.bus.SetPeer('guest-realm',session,false)
for _,item in pairs(P.bus.outgoing) do
    assert(item.version=='1' and item.created==before[item.replace].created and item.order==before[item.replace].order,'fallback order and age')
end
P.bus.outgoing={};P.bus.SetPeer('guest-realm',session,true)
id=assert(P.bus.Send({id=session,kind='snapshot'},{['guest-realm']=true},1))
P.bus.outgoing[id].targets['guest-realm']=nil
P.bus.SetPeer('guest-realm',session,false)
assert(P.bus.outgoing[id],'acknowledged peer does not cancel another transfer')
-- Spoofed invitation IDs cannot create capability entries or alter the match.
local previous=Q.client
Q.Receive({v=1,kind='invite',id=session,to='*',config=P.host.config,wireCodec=2},'chat-realm',H.members[3])
assert(Q.client==previous and not Q.bus.peers['chat-realm'],'invite identity checked before learning support')
-- Same message ID cannot combine frame grammars, even with identical metadata.
local B=Q.bus
local payload=string.rep('x',200)
local sum=C.Sum(payload)
local function frame(ver,i) return table.concat({ver,'mixed',i,2,200,sum,payload:sub((i-1)*160+1,i*160)},'|') end
B.Receive(nil,frame('1',1),'PARTY','Host-Realm');assert(B.assemblies['host-realm|mixed'])
B.Receive(nil,frame('2',2),'PARTY','Host-Realm');assert(not B.assemblies['host-realm|mixed'])
print('loreforge bounded LibSerialize and negotiation tests passed')
