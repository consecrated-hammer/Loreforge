-- WoW API additions needed by the real embedded transport libraries.
local nativeXpcall = xpcall
return function()
    LibStub, ChatThrottleLib = nil, nil
    Enum = Enum or {}
    table.wipe = wipe
    GetFramerate = function() return 60 end
    hooksecurefunc = function() end
    securecallfunction = function(fn, ...) return fn(...) end
    geterrorhandler = function() return function(err) error(err) end end
    -- WoW's xpcall forwards arguments; stock Lua 5.1's does not.
    xpcall = function(fn, handler, ...)
        local args, count = {...}, select("#", ...)
        return nativeXpcall(function() return fn(unpack(args, 1, count)) end, handler)
    end
    for _, file in ipairs({ "Libs/LibStub/LibStub.lua", "Libs/ChatThrottleLib/ChatThrottleLib.lua", "Libs/LibDeflate/LibDeflate.lua", "Libs/LibSerialize/LibSerialize.lua" }) do
        assert(loadfile(file))()
    end
end
