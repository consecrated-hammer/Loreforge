-- Loreforge-only additions to HammerCore's shared wow.lua stand-in, which
-- must stay byte-identical to HammerCore (tools/check.py). Animation groups
-- record Play and Stop, animations record their settings, and font strings
-- remember the font set on them.
return function(wow)
    local create = wow.CreateRegion
    wow.groups = {}
    wow.CreateRegion = function(parent, kind)
        local region = create(parent, kind)
        if kind == "AnimationGroup" then
            wow.groups[#wow.groups + 1] = region
            region.anims, region.playing, region.plays = {}, false, 0
            rawset(region, "Play", function(self) self.playing, self.plays = true, self.plays + 1 end)
            rawset(region, "Stop", function(self)
                local was = self.playing
                self.playing = false
                if was and self.scripts.OnStop then self.scripts.OnStop(self) end
            end)
            rawset(region, "IsPlaying", function(self) return self.playing end)
            rawset(region, "SetLooping", function(self, looping) self.looping = looping end)
            rawset(region, "CreateAnimation", function(self, animKind)
                local anim = create(self, "Animation")
                anim.animKind = animKind
                self.anims[#self.anims + 1] = anim
                return anim
            end)
        elseif kind == "FontString" then
            rawset(region, "SetFont", function(self, face, size, flags) self.font = { face, size, flags }; return true end)
            rawset(region, "GetFont", function(self)
                local font = self.font or { "Fonts\\FRIZQT__.TTF", 12, "" }
                return font[1], font[2], font[3]
            end)
        end
        return region
    end
    -- Every group that is still playing.
    function wow.Playing()
        local list = {}
        for _, g in ipairs(wow.groups) do if g.playing then list[#list + 1] = g end end
        return list
    end
end
