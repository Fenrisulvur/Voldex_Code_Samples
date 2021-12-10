--[[
	Main weapon handler script. 
]]

--[[main metatable]]
local handler = {}
local fpsMT = {__index = handler}	

--[[Services and requires]]
local Random = Random.new()
local replicatedStorage = game:GetService("ReplicatedStorage")
local RS = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local spring = require(replicatedStorage.modules.spring)
local fastcastHandler = require(replicatedStorage.modules.FastCastHandler)
local mouse = game.Players.LocalPlayer:GetMouse()
local UIS = game:GetService("UserInputService")

--[[Some global variables]]
local CastParams = RaycastParams.new()
CastParams.IgnoreWater = true
CastParams.FilterType = Enum.RaycastFilterType.Blacklist
CastParams.FilterDescendantsInstances = {} 

local aimingSwaySpeed = 0.1 
local swaySpeed = 0.2
local lastClick = tick()
local aimingWalkSway = 0.01
local walkSway = 0.04

--[[
	Bobbing function, based around math.tick 
	speed is the speed of the character 
	addition is for additional bob amount
	and modifier will modify the total bob value (good for slowing or speeding up the bob by a %)
]]
local function getBobbing(addition,speed,modifier)
	return math.sin(tick()*addition*speed)*modifier
end

--[[
	Standard lerp function for two numbers.
	a is the first value, b is the second, and t is the %
]]
local function lerpNumber(a, b, t)
	return a + (b - a) * t
end

--[[
	This creates a new 'instance' of the weapon handler.
	weapons are the current list of weapons, 
	wepGui is the main weapon gui,
	wepData is the server fetched data for the weapons.
]]
function handler.new(weapons, wepGui, wepData)

	local self = {}
	
	self.weapons = weapons --current weapon list
	self.weaponData = wepData --server weapon data
	self.loadedAnimations = {} --animation list, will populat on equip
	self.springs = {} --math spring list
	self.lerpValues = {} --value to lerp list
	self.lerpValues.aim = Instance.new("NumberValue") --aim lerp
	self.springs.walkCycle = spring.create(); --spring dedicated to handling walking movement
	self.springs.sway = spring.create() --spring dedicated to handling gun sway from mouse movement
	self.springs.fire = spring.create() --spring dedicated to handling gun recoil
	self.wepGui = wepGui --main gui to show weapon data
	self.lastShot = tick() --last shot time snapshot
	self.skipFrame = false --used to skip exactly 1 frame to hide certain parts spawning in to be shown

	return setmetatable(self,fpsMT)
end


--[[
	This will fire based on each keyframe reached when it is connected to an animationtrack
	This is mostly used for sounds and reloading in this script
]]
function handler:OnKeyFrame(keyframeName) 
	if keyframeName == "ClothRuffle" then
		self.viewmodel.HumanoidRootPart.ClothRuffle:Play()
	elseif keyframeName == "MagOut" then
		self.viewmodel.receiver.MagOut:Play()
	elseif keyframeName == "MagIn" then
		self.viewmodel.receiver.MagIn:Play()
	elseif keyframeName == "Click" then
		self.viewmodel.receiver.Click:Play()
	elseif keyframeName == "Complete" then
		self.reloading = false
		self.viewmodel.HumanoidRootPart.ClothRuffle2:Play()
		if self.loadedAnimations.action_open then self.loadedAnimations.action_open:Stop() end
		
		--temporary data for responsiveness client-side; will be overridden by server data when request completes
		self:clientReloadCalc()
		self:updateGui() 
		
		--ask for server reload data
		local pass, relData = game.ReplicatedStorage.weaponRemotes.reload:InvokeServer(self.curWeapon)
		
		--print(pass, relData)
		
		--if reload passed update gun data.
		if pass then
			self.weaponData[self.curWeapon] = relData
			self:updateGui() 
		end	
	end

end


--[[
	This will handle weapon equipping. It currently goes off the weapon name.
]]
function handler:equip(wepName)

	-- if the weapon is disabled, or equipped, remove it instead.
	if self.disabled then return end
	if self.equipped then self:remove() end
	mouse.Icon = "http://www.roblox.com/asset?id=190927365"
	
	-- get weapon from storage
	local weapon = replicatedStorage.weapons:FindFirstChild(wepName) -- do not clone
	if not weapon then return end -- if the weapon exists, clone it, else, stop
	weapon = weapon:Clone()
	
	-- gets and sets up the viewmodel
	self.viewmodel = replicatedStorage.viewmodel:Clone()
	for i,v in pairs(weapon:GetChildren()) do -- to be moved to a separate function. Ensures viewmodel is cancollide false and does not cast a shadow.
		v.Parent = self.viewmodel
		if v:IsA("BasePart") then
			v.CanCollide = false
			v.CastShadow = false
		end
	end		

	-- assign properties to this equipped gun
	self.camera = workspace.CurrentCamera
	self.character = game.Players.LocalPlayer.Character

	-- place viewmodel out of sight, will snap back when ready
	self.viewmodel.HumanoidRootPart.CFrame = CFrame.new(0,-100,0)
	self.skipFrame = true
	
	-- Bind gun to the viewmodel's rootpart, making the arms move along with the viewmodel.
	self.viewmodel.HumanoidRootPart.weapon.Part1 = self.viewmodel.weaponRootPart
	self.viewmodel.left.leftHand.Part0 = self.viewmodel.weaponRootPart
	self.viewmodel.right.rightHand.Part0 = self.viewmodel.weaponRootPart

	self.viewmodel.Parent = workspace.Camera
    
	--load gun settings 
	self.settings = require(self.viewmodel.settings)
	if self.viewmodel.attachments:FindFirstChild("Aim") then self.viewmodel.offsets.aim.Value = self.viewmodel.attachments.Aim.CFrame:ToObjectSpace(self.viewmodel.HumanoidRootPart.CFrame) end
	
	--load animation from settings
	self.loadedAnimations.idle = self.viewmodel.AnimationController:LoadAnimation(self.settings.animations.viewmodel.idle)
	self.loadedAnimations.fire = self.viewmodel.AnimationController:LoadAnimation(self.settings.animations.viewmodel.fire)
	self.loadedAnimations.reload = self.viewmodel.AnimationController:LoadAnimation(self.settings.animations.viewmodel.reload)
	self.loadedAnimations.reload2 = self.settings.animations.viewmodel.reload2 ~= nil and self.viewmodel.AnimationController:LoadAnimation(self.settings.animations.viewmodel.reload2) or nil
	self.loadedAnimations.equip = self.settings.animations.viewmodel.equip ~= nil and self.viewmodel.AnimationController:LoadAnimation(self.settings.animations.viewmodel.equip) or nil
	self.loadedAnimations.action_open = self.settings.animations.viewmodel.action_open ~= nil and self.viewmodel.AnimationController:LoadAnimation(self.settings.animations.viewmodel.action_open) or nil
	self.loadedAnimations.sprint = self.viewmodel.AnimationController:LoadAnimation(self.settings.animations.viewmodel.sprint)
 
	--[[
		if the gun has certain animations; connect them to the keyframereached handler, else move on
	]]
	self.loadedAnimations.reload.KeyframeReached:Connect(function(keyframeName) self:OnKeyFrame(keyframeName) end)
	if self.loadedAnimations.reload2 then self.loadedAnimations.reload2.KeyframeReached:Connect(function(keyframeName) self:OnKeyFrame(keyframeName) end) end
	if self.loadedAnimations.action_open and self.weaponData[wepName].mag <= 0 then self.loadedAnimations.action_open:Play(0) end
	
	-- temporary tests for weapon pullout animation, will later be moved to sep function and cleaned up
	if self.loadedAnimations.equip then 
		self.loadedAnimations.equip:Play(0, 1, 2)
		task.wait(.2)
		self.loadedAnimations.idle:Play()
	else
		self.loadedAnimations.idle:Play(0) -- no lerp time from default pos to prevent stupid looking arms for no longer than 0 frames	
	end
	
	

	-- verify the weapon with the server, else remove it
	spawn(function()
		local pass = game.ReplicatedStorage.weaponRemotes.equip:InvokeServer(wepName)
		if not pass then self:remove() end
	end)

	self.curWeapon = wepName
	
	self.equipped = true 
	-- update raycast ignore list
	CastParams.FilterDescendantsInstances = {self.character,  workspace.CurrentCamera} 
	self:updateGui() 
	return true
end

--[[
	This will handle weapon removing, with an override to skip animations if the player dies
]]
function handler:remove(override)
	if not override then
		if self.sprinting or self.reloading or self.firing then return false end
		self:aim(false)
		local vm = self.viewmodel
		local tweeningInformation = TweenInfo.new(0.6, Enum.EasingStyle.Quart,Enum.EasingDirection.Out) --tween properties	
		local properties = { Value = 1 } --tween properties	
		self.equipped = false
		if self.loadedAnimations.equip then self.loadedAnimations.equip:Play(.1, 1, -2) end --play equip anim in reverse
		task.wait(0.2) -- wait until the tween finished so the gun lowers itself smoothly before deletion, will later move to tween.completed 
		
		if vm then
			vm:Destroy()
		end
	end
	
	-- reset some variables for the gun
	self.viewmodel = nil
	self.equipped = false
	mouse.Icon = ""
	self.disabled = true
	self.curWeapon = nil
	workspace.CurrentCamera.FieldOfView = 70
	
	-- tell server to remove the weapon
	spawn(function()
		game.ReplicatedStorage.weaponRemotes.unequip:InvokeServer()
	end)

	
	self.disabled = false
	self:updateGui() 
	return true
end


--[[
	This will handle weapon aiming, based off of toaim, true is aiming, false is not
]]
function handler:aim(toaim)
	if self.sprinting or self.disabled or not self.equipped or self.reloading then return end
	self.aiming = toaim
	game:GetService("UserInputService").MouseIconEnabled = not toaim
	
	-- tell the server that the weapon is being aimed
	replicatedStorage.weaponRemotes.aim:FireServer(toaim)	
	

	if toaim then
		-- temporary properties for testing tweens for aim and camera fov, will later be placed into gun settings instead of here
		local tweeningInformation = TweenInfo.new(.4, Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
		local properties = { Value = 1 }
		tweenService:Create(self.lerpValues.aim,tweeningInformation,properties):Play()	
		tweenService:Create(self.camera,tweeningInformation,{ FieldOfView = self.viewmodel.offsets:FindFirstChild("aimFov") and self.viewmodel.offsets.aimFov.value or 70 }):Play()		
	else
		-- temporary properties for testing tweens for aim and camera fov, will later be placed into gun settings instead of here
		local tweeningInformation = TweenInfo.new(0.3, Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
		local properties = { Value = 0 }
		tweenService:Create(self.lerpValues.aim,tweeningInformation,properties):Play()
		tweenService:Create(self.camera,tweeningInformation,{ FieldOfView = 70 }):Play()
	end

end

--[[
	This will handle weapon reloading
]]
function handler:reload()
	if self.sprinting or self.aiming or self.reloading or self.disabled or not self.equipped or self.firing then return end
	-- no ammo? then no reload
	if self.weaponData[self.curWeapon].spare <= 0 then return end
	self.reloading = true
	--allows two different animations. One for empty mag and one for non-empty
	if self.weaponData[self.curWeapon].mag <= 0 and self.loadedAnimations.reload2 then 
		self.loadedAnimations.reload2:Play(0)
	else
		self.loadedAnimations.reload:Play(0) 
	end
	
end

--[[
	This will handle weapon sprinting, similar to aiming is based off a bool value of sprinting or not sprinting
]]
function handler:sprint(tosprint)
	if self.reloading or self.disabled or not self.equipped or self.firing then return end
	self.sprinting = tosprint
	-- load or stop sprint anim
	if tosprint then
		self.loadedAnimations.sprint:Play()
	else
		self.loadedAnimations.sprint:Stop()
	end
	game.Players.localPlayer.Character.Humanoid.WalkSpeed = tosprint and 25 or 16
end

--[[
	Temporary reload data for the client, will be overridden by the server
]]
function handler:clientReloadCalc()
	-- no ammo means no reload
	if self.weaponData[self.curWeapon].spare <= 0 then return false end
	
	-- if the spare ammo has less than or equal to a mags worth
	if (self.weaponData[self.curWeapon].spare - (self.weaponData[self.curWeapon].settings.firing.magCapacity - self.weaponData[self.curWeapon].mag)) <= 0 then
		self.weaponData[self.curWeapon].mag = self.weaponData[self.curWeapon].mag + self.weaponData[self.curWeapon].spare
		self.weaponData[self.curWeapon].spare = 0
	-- if the spare ammo has more than the mags worth
	else
		self.weaponData[self.curWeapon].spare = self.weaponData[self.curWeapon].spare - (self.weaponData[self.curWeapon].settings.firing.magCapacity - self.weaponData[self.curWeapon].mag)
		self.weaponData[self.curWeapon].mag = self.weaponData[self.curWeapon].settings.firing.magCapacity
	end
end

--[[
	update the gui
]]
function handler:updateGui() 
	if self.wepGui == nil then return end
	self.wepGui.Enabled = self.equipped
	if not self.equipped then return end
	-- show weapon stats
	self.wepGui.Data.name.Text = self.curWeapon or ""
	self.wepGui.Data.Mag.Text = self.weaponData[self.curWeapon].mag 
	self.wepGui.Data.Reserve.Text = self.weaponData[self.curWeapon].spare 
	self.wepGui.Data.Capacity.Text = self.weaponData[self.curWeapon].settings.firing.magCapacity
		
end

--[[
	Function to handle firing effects
]]
function handler:fireFX()
	local sound = self.viewmodel.receiver.Fire:Clone()
	sound.Parent = self.viewmodel.receiver
	sound:Play()

	game:GetService("Debris"):AddItem(sound,2)
end

--[[
	Function to handle recoil effect
]]
function handler:fireRecoil()
	local patt = self.settings.recoil.patterns[math.random(1, #self.settings.recoil.patterns)] 
	local rec = Vector3.new( Random:NextNumber(patt.min.x, patt.max.x), Random:NextNumber(patt.min.y, patt.max.y), Random:NextNumber(patt.min.z, patt.max.z) ) * (self.aiming and 0.5 or 1)

	self.springs.fire:shove(rec)
end

--[[
	Get mouse position, but with a ignorelist and better handling
]]
function handler:GetMouse(Distance, CastParams)
	
	local MouseLocation = game:GetService("UserInputService"):GetMouseLocation()
	local UnitRay = workspace.CurrentCamera:ViewportPointToRay(MouseLocation.x, MouseLocation.y)
	
	local origin = UnitRay.Origin
	local endp = UnitRay.Direction * Distance
	local Hit = workspace:Raycast(origin, endp, CastParams)
	
	if Hit then 
		return Hit.Position
	else
		return UnitRay.Origin * UnitRay.Direction * Distance
	end
end


--[[
	Update the entire weapon, this includes sway, recoil, walking, etc
]]
function handler:update(deltaTime)
	if self.viewmodel then
		-- skip exactly one frame if required
		if self.skipFrame then RS.RenderStepped:Wait() self.skipFrame = false return end
		-- get velocity for walkCycle
		local velocity = self.character.HumanoidRootPart.Velocity

		-- aim overwrites idle.
		local idleOffset = self.viewmodel.offsets.idle.Value
		local aimOffset = idleOffset:lerp(self.viewmodel.offsets.aim.Value,self.lerpValues.aim.Value)
		local finalOffset = aimOffset
		-- get mouse movement
		local mouseDelta = UIS:GetMouseDelta()
		-- modify sway speed based on aiming
		if self.aiming then mouseDelta = mouseDelta * aimingSwaySpeed else mouseDelta = mouseDelta * swaySpeed end
		
		self.springs.sway:shove(Vector3.new(mouseDelta.x / 200,mouseDelta.y / 200)) --not sure if this needs deltaTime filtering

		-- speed can be dependent on a value changed when running, or standing still, or aiming, etc.
		-- this makes the bobble faster.
		local speed = 1
		
		-- modifier can be dependent on a value changed when aiming, or standing still, etc.
		local modifier = self.aiming and aimingWalkSway or walkSway

		-- Bobbing
		local movementSway = Vector3.new(getBobbing(10,speed,modifier),getBobbing(5,speed,modifier),getBobbing(5,speed,modifier))

		-- if velocity is 0, then so will the walk cycle
		self.springs.walkCycle:shove((movementSway / 25) * deltaTime * 60 * math.min(velocity.Magnitude, 32))

		-- update all springs
		local sway = self.springs.sway:update(deltaTime)
		local walkCycle = self.springs.walkCycle:update(deltaTime)
		local recoil = self.springs.fire:update(deltaTime)

		-- Recoil
		self.camera.CFrame = self.camera.CFrame * CFrame.Angles(recoil.x,recoil.y,recoil.z)

		-- set viewmodel cframe to the final offset
		self.viewmodel.HumanoidRootPart.CFrame = self.camera.CFrame:ToWorldSpace(finalOffset)
		
		-- this is temporary testing of values before i incorporate them to globals to prevent "magic numbers"
		if self.sprinting then
			movementSway = Vector3.new(getBobbing(7, 2, .04),getBobbing(7,2,.04),getBobbing(33,2,.52))
			self.viewmodel.HumanoidRootPart.CFrame = self.viewmodel.HumanoidRootPart.CFrame:ToWorldSpace(CFrame.new( walkCycle.x / 2 + ( (.2  * math.sin(5 * 1 * tick())) * math.clamp(math.min(velocity.Magnitude, 32), 0, 1)  )  ,walkCycle.y / 2,0))
		-- this is the original sway before sprint
		else
			movementSway = Vector3.new(getBobbing(10,speed,modifier),getBobbing(5,speed,modifier),getBobbing(5,speed,modifier))
			self.viewmodel.HumanoidRootPart.CFrame = self.viewmodel.HumanoidRootPart.CFrame:ToWorldSpace(CFrame.new(walkCycle.x / 2,walkCycle.y / 2,0))
		end
		-- Rotate rootpart based on sway
		self.viewmodel.HumanoidRootPart.CFrame = self.viewmodel.HumanoidRootPart.CFrame * CFrame.Angles(-sway.y,-sway.x,0)
		self.viewmodel.HumanoidRootPart.CFrame = self.viewmodel.HumanoidRootPart.CFrame * CFrame.Angles(-walkCycle.x,walkCycle.y,0)
		-- if the gui exists, update
		if self.wepGui then
			local camera = workspace.CurrentCamera
			local vector, onScreen = camera:WorldToScreenPoint(self.viewmodel.receiver.barrel.WorldPosition)
			self.wepGui.Data.Position = UDim2.fromOffset(vector.x - 150, vector.y + 50)
			
		end
		
	end
end

--[[
	Fire the weapon, this is a chunky function that i've been breaking up into smaller parts.
]]
function handler:fire(tofire)
	if self.sprinting or self.reloading or self.disabled or not self.equipped or self.firing and tofire then return end
	self.firing = tofire
	if not tofire or self.weaponData[self.curWeapon].mag <= 0 then return end -- no ammo
	if (tick() - lastClick) < (60/self.settings.firing.rpm) then return end -- clicking faster that fire rate
	if not self.viewmodel:FindFirstChild("receiver") then return end  -- no gun 
	
	-- update tickvalues 
	lastClick = tick() 
	local clickTick = lastClick 
	
	while self.firing and clickTick == lastClick do -- break if the player clicked again to prevent overlapping firing loops
		self.haltFire = true
		-- [[ shotgun is handled differently than normal guns, this will be split out later ]]
		if self.settings.firing.shotgun then
			self.weaponData[self.curWeapon].mag = self.weaponData[self.curWeapon].mag - 1
			self.loadedAnimations.fire:Play(0,1,2)
			self.viewmodel.receiver.barrel.MuzzleEffect:Emit(self.viewmodel.receiver.barrel.MuzzleEffect.Rate)
			
			self:fireFX()
				
			self:fireRecoil()
			
			self:updateGui() 
		end
		
		--shotgun pellet table
		local pellets = {}

		for i = 1, self.settings.firing.shots or 1 do -- prime data for each shot based on shots per trigger fire in the settings
			local origin = self.viewmodel.receiver.barrel.WorldPosition  -- where the bullet starts
			local endPos  = self:GetMouse(1000, CastParams) -- mouse.Hit.p, but better
			-- this is a simple test calculation to make the first shot accurate and increase as the trigger is held, this will be improved later
			local offsetCalc =  not self.settings.firing.shotgun and math.max(0.5 - (tick() - self.lastShot), 0 ) or 1
			-- base settings for spread
			local baseSpread = self.settings.firing.spread * offsetCalc
			-- bullet distance
			local distance = (endPos - origin).magnitude
			-- bullet spread
			local spread = Vector3.new((math.random(-baseSpread,baseSpread) / 250) * distance, (math.random(-baseSpread, baseSpread) / 250) * distance, (math.random(-baseSpread, baseSpread) / 250) * distance)
			-- direction of the bullet
			local direction = CFrame.new(origin, endPos + spread )

			
			
			if self.settings.firing.shotgun then 
				-- combine the pellets into a table
				table.insert(pellets,#pellets+1, {origin, direction} )
			else
				-- fire each round
				if self.weaponData[self.curWeapon].mag <= 0 then continue end
				self.loadedAnimations.fire:Play(0,1,2)
				
				-- this is a handler for fastcast, it will handle bullet firing
				fastcastHandler:fire(origin, direction, self.settings, false, game.Players.LocalPlayer.Character, game.Players.LocalPlayer)
				-- Muzzle flash
				self.viewmodel.receiver.barrel.MuzzleEffect:Emit(self.viewmodel.receiver.barrel.MuzzleEffect.Rate)
				
				self:fireFX()
				self:fireRecoil()
				self.weaponData[self.curWeapon].mag = self.weaponData[self.curWeapon].mag - 1
				self:updateGui() 
				
				
			end

			if self.weaponData[self.curWeapon].mag <= 0  and not self.settings.firing.shotgun then break end -- if its a shotgun then continue, else end because no ammo (each pellet wont take 1 ammo)
			if self.settings.firing.burstDelay then task.wait(self.settings.firing.burstDelay) end -- burst delay for burst fire weapons
		end

		-- send all shotgun pellets to be handled at once
		if self.settings.firing.shotgun then
			fastcastHandler:fireShotgun(pellets, self.settings, false, game.Players.LocalPlayer.Character, game.Players.LocalPlayer) 
		end


		task.wait(60/self.settings.firing.rpm) -- wait for the firerate
		-- sanity check to break if gun is not automatic, button isnt pressed, or the tick click is not the same.
		if not self.settings.firing.auto or not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) or clickTick ~= lastClick then break end 
		if not self.curWeapon or self.weaponData[self.curWeapon].mag <= 0 then break end -- break if no ammo
	end
	self.haltFire = false
	-- last round bolt hold open anim if applicable
	if self.loadedAnimations.action_open and self.weaponData[self.curWeapon].mag <= 0 then self.loadedAnimations.action_open:Play(0) end 
end

return handler