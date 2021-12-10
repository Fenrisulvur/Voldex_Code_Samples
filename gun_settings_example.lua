-- gun model
local root = script.Parent

local data = {
	animations = { -- store all animations for the gun
		viewmodel = { -- animations for the viewmodel
			idle = root.animations.idle,
			fire = root.animations.fire,
			reload = root.animations.reload,
			equip = root.animations.equip,
			sprint = root.animations.sprint,
		},
		player = { -- animations for the player (serverside for other players)
			aim = root.serverAnimations.aim,
			aimFire = root.serverAnimations.aimFire,
			idle = root.serverAnimations.idle,
			idleFire = root.serverAnimations.idleFire,
		},
	},

	firing = { -- gun stats
		damage = 15,
		headshot = 20,
		rpm = 200,
		spread = 0.5,
		magCapacity = 20,
		velocity = 2500,
		range = 2000,
		auto = false,
		burstDelay = 0.05,
		shots = 3,
		shotgun = false,
	},

	recoil = {
		patterns = { -- recoil patterns to be chosen at random, will fluctuate between min and max. this will be expanded later
			{ min = Vector3.new(0.01, 0., 0), max = Vector3.new(0.03, 0.01, 0) },
		},
	},
}

return data
