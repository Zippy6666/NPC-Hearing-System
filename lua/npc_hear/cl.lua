-- Client sound emitted for host, catch that as well
-- For now, only for explosions
hook.Add( "EntityEmitSound", "NPCHearing", function(SoundData)
    if game.IsDedicated() then return end
    if !NPC_HEAR.EnabledCvar:GetBool() or LocalPlayer()!=Entity(1) then return end


    if SoundData.OriginalSoundName == "BaseExplosionEffect.Sound" then
        net.Start("NPCHearExplosion")
        net.WriteVector(SoundData.Pos)
        net.SendToServer()
    end
end)


-- Options menu
hook.Add("PopulateToolMenu", "NPCHearing", function()

    spawnmenu.AddToolMenuOption("Options", "AI", "Hearing", "Hearing", "", "", function(panel)
        panel:CheckBox("Enabled", "npc_hearing_enable")
        panel:Help("Enable NPC hearing")
    end)

end)
