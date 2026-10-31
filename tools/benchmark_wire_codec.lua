-- Run from the checkout with Lua 5.1. Uses actual integration-game messages,
-- 160-byte framing and the production compressor/channel encoder.
local rawLoad=loadfile
local H=assert(rawLoad('tests/party-harness.lua'))()
local samples,create,codec,wire,transport={},H.create
H.create=function(...)
    local c=create(...)
    codec,wire,transport=c.ns.Codec,c.ns.WireCodec,c.ns.Party.bus.transport
    local send=c.ns.Party.bus.Send
    c.ns.Party.bus.Send=function(message,...)
        local text=codec.Encode(message)
        if text and (not samples[message.kind] or #text>#samples[message.kind]) then samples[message.kind]=text end
        return send(message,...)
    end
    return c
end
loadfile=function(path,...)
    if path=='tests/party-harness.lua' then return function()return H end end
    return rawLoad(path,...)
end
assert(rawLoad('tests/test_party.lua'))()
loadfile=rawLoad
-- The supported maximum: five players and twenty rounds, with long names.
local maximum={version=1,id=string.rep('i',180),host=string.rep('h',120),date=1800000000,
 config={rounds=20,perRound=50,seconds=120,categories=string.rep('c',512),difficulty='mixed',readyCheck=true},rows={},rounds={},totalQuestions=1000}
for i=1,5 do
 maximum.rows[i]={key=string.rep('k',115)..i,name=string.rep('n',120),total=1000,round=50,streak=1000,bestStreak=1000,answered=1000,rank=1,winner=true,ready=true,inAddon=true}
end
for r=1,20 do
 maximum.rounds[r]={round=r,rows={}}
 for i=1,5 do maximum.rounds[r].rows[i]={key=maximum.rows[i].key,round=50,total=1000,streak=1000,bestStreak=1000,answered=1000,rank=1} end
end
samples.maximum_result=assert(codec.Encode({v=1,kind='result',id=maximum.id,to='guest-realm',wireCodec=2,result=maximum}))
local function cost(text,version)
    local total,bytes=math.ceil(#text/160),0
    for i=1,total do
        local frame=table.concat({version,'0123456789abcd-1',i,total,#text,codec.Sum(text),text:sub((i-1)*160+1,i*160)},'|')
        bytes=bytes+#assert(transport.Pack(frame))
    end
    return total,bytes
end
local keys={};for k in pairs(samples) do keys[#keys+1]=k end;table.sort(keys)
print('message,legacy_bytes,binary_bytes,legacy_frames,binary_frames,legacy_wire,binary_wire,legacy_ms,binary_ms')
for _,kind in ipairs(keys) do
    local value=codec.Decode(samples[kind])
    local binary=assert(wire.Encode(value),kind)
    assert(codec.Encode(wire.Decode(binary))==samples[kind],'roundtrip '..kind)
    local lf,lw=cost(samples[kind],'1');local bf,bw=cost(binary,'2')
    local function timing(encode,decode)
        local start=os.clock()
        for _=1,100 do assert(decode(assert(encode(value)))) end
        return (os.clock()-start)*10
    end
    print(string.format('%s,%d,%d,%d,%d,%d,%d,%.3f,%.3f',kind,#samples[kind],#binary,lf,bf,lw,bw,timing(codec.Encode,codec.Decode),timing(wire.Encode,wire.Decode)))
end
