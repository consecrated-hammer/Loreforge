local _, ns = ...
-- Network-only LibSerialize adapter. Saved history continues to use Codec.
local W = { MAX = ns.Codec.MAX }
ns.WireCodec = W
local function library()
    if not LibStub then return end
    local lib, minor = LibStub:GetLibrary("LibSerialize", true)
    -- Preflight below is deliberately tied to the inspected minor's wire grammar.
    if minor == 7 and type(lib.SerializeEx) == "function" and type(lib.Deserialize) == "function" then return lib end
end
function W.Available() return library() ~= nil end

-- Check before upstream can allocate containers or recurse. Only the integer,
-- boolean, string and tree subset used by Loreforge is accepted. Table refs
-- (including cycles), floats other than negative zero, and nil are excluded.
-- String refs remain useful.
local function preflight(text)
    assert(type(text)=="string" and #text<=W.MAX, "wire bytes")
    local pos, nodes, expanded, refs = 1, 0, 0, {}
    local function charge(n) expanded=expanded+n;assert(expanded<=W.MAX,"wire expansion") end
    local function uint(n)
        assert(pos+n-1<=#text,"wire truncated")
        local v=0
        for i=pos,pos+n-1 do v=v*256+text:byte(i) end
        pos=pos+n
        return v
    end
    assert(uint(1)==1,"wire version")
    local function scalar(v)
        local t=type(v)
        if t=="number" then
            assert(v==math.floor(v) and math.abs(v)<=1000000000000,"wire number")
            charge(2+#string.format("%.0f",v))
        elseif t=="string" then charge(2+#tostring(#v)+#v)
        else charge(1) end
        return v
    end
    local function key(v)
        assert(type(v)=="string" or (type(v)=="number" and v>=1 and v<=1000),"wire key")
    end
    local parse
    local function container(array,map,depth)
        assert(array+map<=128,"wire entries")
        charge(2+#tostring(array+map))
        local keys={}
        for i=1,array do
            nodes=nodes+1;assert(depth+1<=8 and nodes<=8192,"wire complexity")
            scalar(i);keys[i]=true;parse(depth+1)
        end
        for _=1,map do
            local k=parse(depth+1);key(k)
            assert(not keys[k],"wire duplicate");keys[k]=true
            parse(depth+1)
        end
        return keys -- Container marker, never a valid key.
    end
    local function literal(n)
        assert(n<=4096 and pos+n-1<=#text,"wire string")
        local s=text:sub(pos,pos+n-1);pos=pos+n
        if n>2 then refs[#refs+1]=s end
        return scalar(s)
    end
    parse=function(depth)
        nodes=nodes+1;assert(depth<=8 and nodes<=8192,"wire complexity")
        local tag=uint(1)
        if tag%2==1 then return scalar((tag-1)/2) end
        if tag%4==2 then
            local typ=math.floor(tag/4)%4
            local count=math.floor(tag/16)
            if typ==0 then return literal(count) end
            if typ==1 then return container(0,count,depth) end
            if typ==2 then return container(count,0,depth) end
            return container(count%4+1,math.floor(count/4)+1,depth)
        end
        if tag%8==4 then
            local packed=uint(1)*256+tag
            return scalar(tag%16==12 and -(packed-12)/16 or (packed-4)/16)
        end
        local typ=tag/8
        if typ>=1 and typ<=8 then
            local sizes={2,2,3,3,4,4,7,7}
            local n=uint(sizes[typ]);return scalar(typ%2==0 and -n or n)
        end
        if typ==10 then
            assert(uint(1)==4 and text:sub(pos,pos+3)=="-0.0","wire float")
            pos=pos+4;return scalar(tonumber("-0.0"))
        end
        if typ==12 then return scalar(true) elseif typ==13 then return scalar(false) end
        if typ>=14 and typ<=16 then return literal(uint(typ-13)) end
        if typ>=17 and typ<=19 then return container(0,uint(typ-16),depth) end
        if typ>=20 and typ<=22 then return container(uint(typ-19),0,depth) end
        if typ>=23 and typ<=25 then
            local array,map=uint(typ-22),uint(typ-22)
            return container(array,map,depth)
        end
        if typ>=26 and typ<=28 then
            local s=refs[uint(typ-25)];assert(s,"wire reference");return scalar(s)
        end
        error("wire unsupported type")
    end
    local root=parse(0)
    assert(type(root)=="table" and pos==#text+1,"wire root")
end
function W.Check(text) return pcall(preflight,text) end
function W.Encode(value, canonical)
    local lib=library()
    -- Canonical encoding also enforces the existing outbound/history policy.
    if not lib or not (canonical or ns.Codec.Encode(value)) then return nil end
    local ok,text=pcall(lib.SerializeEx,lib,{stable=true},value)
    if not ok or not W.Check(text) then return nil end
    return text
end
function W.Decode(text)
    local lib=library()
    if not lib or not W.Check(text) then return nil end
    local reader={}
    function reader:ReadBytes(i,j)
        assert(i>=1 and j>=i-1 and j<=#text,"wire read")
        return text:sub(i,j)
    end
    function reader:AtEnd(i) return i>#text end
    local called,ok,value,extra=pcall(lib.Deserialize,lib,reader)
    if not called or not ok or extra~=nil or type(value)~="table" or not ns.Codec.Encode(value) then return nil end
    return value
end
