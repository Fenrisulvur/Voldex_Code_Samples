--[[ services ]]
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")
local players = game:GetService("Players")
local fastcastHandler = require(replicatedStorage.modules.FastCastHandler)

--[[ replication of firing bullets ]]
replicatedStorage.weaponRemotes.fire.OnClientEvent:Connect(function(player, origin, direction, shotgun, bullets)
	if player ~= players.LocalPlayer then
		-- grab some variables
		local gun = player.gun.Value
		local properties = require(gun.settings)

		-- replicated fire sound, will be extracted later to a dedicated function
		local sound = gun.receiver.Fire:Clone()
		sound.Parent = gun.receiver
		sound:Play()
		game:GetService("Debris"):AddItem(sound, 2)

		-- muzzle flash for 3rd person
		gun.receiver.barrel.MuzzleEffect:Emit(gun.receiver.barrel.MuzzleEffect.Rate)

		-- re-fire from the client, uses the same handler as the weapon system and the server
		if shotgun then
			fastcastHandler:fireShotgun(bullets, properties, true, player.Character, player)
		else
			fastcastHandler:fire(origin, direction, properties, true, player.Character, player)
		end
	end
end)
