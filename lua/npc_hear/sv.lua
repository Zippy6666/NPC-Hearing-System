util.AddNetworkString("NPCHearExplosion")



NPC_Hearing_NPCs = NPC_Hearing_NPCs or {}



NPC_HEAR_BANG = 1
NPC_HEAR_VOICE = 2
NPC_HEAR_STEP = 3
NPC_HEAR_QUIET = 4



local NPC = FindMetaTable("NPC")
local Developer = GetConVar("developer")
local SNDLVL_NONE = 0
local SNDLVL_GUNFIRE = 140
local SNDLVL_TRANS = {
    "NPC_HEAR_BANG",
    "NPC_HEAR_VOICE",
    "NPC_HEAR_STEP",
    "NPC_HEAR_QUIET",
}



local function GetNPCPercievedLoudness(SoundData)

    local chan = SoundData.Channel
    local lvl = SoundData.SoundLevel


    if (chan==CHAN_WEAPON && lvl > 100) or lvl > SNDLVL_GUNFIRE then
        return NPC_HEAR_BANG
    elseif chan==CHAN_VOICE && lvl >= 90 then
        return NPC_HEAR_VOICE
    elseif chan==CHAN_BODY or lvl >= 70 then
        return NPC_HEAR_STEP
    else
        return NPC_HEAR_QUIET
    end


end



-- React to the heard sound
function NPC:ReactToSound(SoundData, DistSqr)
    local Emitter = SoundData.Entity
    local SoundPos = SoundData.Pos


    local function reset()
        if self:IsCurrentSchedule(SCHED_NPC_FREEZE) then return end -- Don't reset sched if in freeze

        self:TaskComplete()
        self:ClearSchedule()
        self:ClearGoal()
        self:StopMoving()
    end


    -- Reset
    reset()


    -- Set alert if it was loud
    local loudness = GetNPCPercievedLoudness(SoundData)
    if loudness == NPC_HEAR_BANG or loudness == NPC_HEAR_VOICE then
        self:SetNPCState(NPC_STATE_ALERT)
        self:AlertSound()
    end


    if IsValid(Emitter) then
        self:SetTarget(Emitter)
        self:SetSchedule(SCHED_TARGET_FACE)
    end


    -- ZBase support
    if self.IsZBaseNPC then
        self:InternalOnReactToSound((IsValid(Emitter) && Emitter) or game.GetWorld(), SoundPos, GetNPCPercievedLoudness(SoundData))
    end


    -- Mark we started to trace the sound
    self.LastSoundDistSqr = DistSqr
    self.TracingSound = true

    

    -- After some delay...
    local timerNameDelay = "NPCHearSoundDelay"..self:EntIndex()
    timer.Create(timerNameDelay, math.Rand(1, 2), 1, function()


        if !IsValid(self) then return end


        -- If we can't see the sound source...
        if !self:VisibleVec(SoundPos) then

            -- Cannot see source of sound, go to it
            local timerName = "NPCHearSoundThink"..self:EntIndex()
            local sightdist = self:GetMaxLookDistance()^2
            local stop = function()

                reset()


                self.TracingSound = false
                self.LastSoundDistSqr = nil
    
                timer.Remove(timerName)
        
            end


            -- Go to source using SCHED_FORCED_GO 
            self:SetLastPosition(SoundPos)
            self:SetSchedule(self:GetNPCState()==NPC_STATE_ALERT && SCHED_FORCED_GO_RUN or SCHED_FORCED_GO)
    
    
            -- Tick/think
            timer.Create(timerName, 0.5, 0, function()
                if !IsValid(self) then
                    timer.Remove(timerName)
                    return
                end


                local mydist = self:GetPos():DistToSqr(SoundPos)
    
    
                -- Cancel behaviour if a grenade or something rolls by
                -- local hint = sound.GetLoudestSoundHint(SOUND_DANGER, self:GetPos())
                -- if hint then
                --     stop()
                --     return
                -- end


                -- Has an enemy now, stop pursuing sound
                if IsValid(self:GetEnemy()) then
                    stop()
                    return
                end


                -- Can see source now, stop pursuing
                if self:VisibleVec(SoundPos) && mydist<sightdist then
                    stop()
                    return
                end

    
                -- Sched interrupted/done stop 'hear think'
                if !self:IsCurrentSchedule(SCHED_FORCED_GO) && !self:IsCurrentSchedule(SCHED_FORCED_GO_RUN) then
                    stop()
                    return
                end
            end)

        else

            -- Sound source visible, don't start trace after timer
            reset()
            self.TracingSound = false
            self.LastSoundDistSqr = nil

        end
    end)

end




local function CalcHearDistSqr( ent, SoundData )
    local lvl = SoundData.SoundLevel


    local DistTbl = {
        [NPC_HEAR_BANG] = lvl*40,
        [NPC_HEAR_VOICE] = lvl*18,
        [NPC_HEAR_STEP] = lvl*12,
        [NPC_HEAR_QUIET] = 150,
    }
    local dist = DistTbl[GetNPCPercievedLoudness(SoundData)] * (ent.HearDistMult or 1)


    -- Sound is muffled behind something
    if !ent:VisibleVec(SoundData.Pos) then
        dist = dist*0.5
    end


    return dist^2
end



-- Did we hear the sound?
function NPC:HeardSound(SoundData, DistSqr)
    local Emitter = SoundData.Entity


    -- Too close, likely its own footsteps for example
    if DistSqr < 100 then
        return false
    end


    -- No sound level??
    if SoundData.SoundLevel <= SNDLVL_NONE then
        return false
    end


    -- ZBase NPC steps cannot be heard, for compatability sake...
    if Emitter.IsZBaseStepEnt then
        return false
    end


    if self.TracingSound then

        if self.LastSoundDistSqr && DistSqr < self.LastSoundDistSqr then
        else
            return false
        end

    end


    -- Cooldown
    if self.NextHearSound > CurTime() then
        return false
    end


     -- Don't react to itself
    if Emitter==self then
        return false
    end


    -- Don't react to something owned by itself, like a grenade
    if IsValid(Emitter) && Emitter:GetOwner() == self then
        return false
    end


    -- Don't care about sounds when already in combat
    if self:GetNPCState()==NPC_STATE_COMBAT then
        return false
    end


    -- In a dormant schedule, don't react
    if self:IsCurrentSchedule(SCHED_NPC_FREEZE) or self:GetNPCState() == NPC_STATE_SCRIPT then
        return false
    end


    -- Don't react to an ally
    if self:Disposition(Emitter)==D_LI then
        return false
    end
    

     -- Too far
    if DistSqr > CalcHearDistSqr( self, SoundData ) then
        return false
    end
    

    self.NextHearSound = CurTime()+math.Rand(1, 2)
    return true
end



local function OnEntEmitSound(SoundData)

    if !IsValid(SoundData.Entity) then return end

    for _, npc in ipairs(NPC_Hearing_NPCs) do
        local DistSqr = npc:GetPos():DistToSqr(SoundData.Pos)

        if npc:HeardSound(SoundData, DistSqr) then

            if Developer:GetBool() then
                MsgN(npc, " heard sound ("..SNDLVL_TRANS[GetNPCPercievedLoudness(SoundData)]..")!")
            end

            npc:ReactToSound(SoundData, DistSqr)

        end
    end

end




net.Receive("NPCHearExplosion", function(_, ply)
    if ply == Entity(1) && ply:IsSuperAdmin() then

        local SoundData = {}
        SoundData.SoundLevel = SNDLVL_GUNFIRE
        SoundData.Channel = CHAN_WEAPON
        SoundData.Pos = net.ReadVector()
        SoundData.Entity = ents.Create("base_gmodentity")
        SoundData.Entity:SetNoDraw(true)
        SoundData.Entity:SetPos(SoundData.Pos)
        SoundData.Entity:Spawn()
        OnEntEmitSound(SoundData)
        SafeRemoveEntityDelayed(SoundData.Entity, 5)

    end
end)



hook.Add("EntityEmitSound", "NPCHearing", function(SoundData)
    if !NPC_HEAR.EnabledCvar:GetBool() then return end
    if !IsValid(SoundData.Entity) then return end

    if SoundData.Volume > 0.25 && SoundData.SoundLevel > 25 then
        if !SoundData.Pos then
            SoundData.Pos = SoundData.Entity:GetPos()
        end

        OnEntEmitSound(SoundData)
    end
end)


-- Register NPC
hook.Add( "OnEntityCreated", "NPCHearing_RegisterNPC", function( ent )
    conv.callNextTick(function()
        if !IsValid(ent) then return end

        if ent:IsNPC() && ent:GetMoveType()==MOVETYPE_STEP && !ent.IsVJBaseSNPC then

            ent.NextHearSound = CurTime()
            ent.TracingSound = false

            table.insert(NPC_Hearing_NPCs, ent)

            ent:CallOnRemove("RemoveFromNPC_Hearing_NPCs", function()
                table.RemoveByValue(NPC_Hearing_NPCs, ent)
            end)

        end
    end)
end)
