local class = {}
jcms.class_Add("merekisv1ultrakill", class, true)

class.mdl = "models/ultrakill/v1_pm.mdl"
class.mdls_pvp = {
	[1] = "models/ultrakill/v2.mdl",
	[2] = "models/ultrakill/v1_pm.mdl"
}

class.deathSound = "npc/scanner/scanner_explode_crash2.wav"

class.health = 100
class.shield = 0
class.shieldRegen = 0
class.shieldDelay = 9999
class.shieldText = "#merekisv1ultrakill.blood_is_fuel"

class.damage = 1.0
class.hurtMul = 3 -- Might as well be functionally 33 HP but I want to make medkits and other forms of healing more ineffective here.
class.hurtReduce = -1
class.speedMul = 1.33
class.walkSpeed = 350
class.runSpeed = 350
class.jumpPower = 420

class.gravity = 0.95

class.noFallDamage = true
class.sprintHack = false

function class.OnSpawn(ply)
	ply:SetDuckSpeed(0.02)
	ply:SetUnDuckSpeed(0.02)

	ply.jcms_v1Stamina = 3
	ply.jcms_v1StyleRankId = 1
	ply.jcms_v1StyleScore = 0

	merekisv1ultrakill_UpdateV1s(ply)
	merekisv1ultrakill_SetupStyleTimer(ply)
	merekisv1ultrakill_NetSendStyle(ply, 1, 0)
end

function class.OnDeath(ply)
	if ply.jcms_v1ScrapeSnd then
		ply.jcms_v1ScrapeSnd:Stop()
		ply.jcms_v1ScrapeSnd = nil
	end
end

-- Walljumping {{{
	class.wallJumps = 3
	class.wallTraceVecs = {
		{ 1, 0 },
		{ 0, 1 },
		{ -1, 0 },
		{ 0, -1 },
		
		{ 1, 1 },
		{ -1, 1 },
		{ -1, -1 },
		{ 1, -1 }
	}
-- }}}

function class.Think(ply)
	local plyTbl = ply:GetTable()
	local dt = FrameTime()

	plyTbl.jcms_v1Stamina = math.Clamp((plyTbl.jcms_v1Stamina or 0) + dt * 0.7, 0, 3)

	if plyTbl.jcms_v1Slamming then
		local pos1 = ply:GetPos()
		local pos2 = ply:GetVelocity()
		pos2.x = 0
		pos2.y = 0
		pos2.z = pos2.z * dt * 4
		pos2:Add(pos1)

		local tr = util.TraceEntityHull({
			start = pos1, 
			endpos = pos2,
			filter = ply,
			mask = MASK_SHOT
		}, ply)

		if not plyTbl.jcms_v1SlamVictims then
			plyTbl.jcms_v1SlamVictims = {}
		end

		local v1,v2=ply:GetHull()
		local victim = tr.Entity
		if IsValid(victim) and not plyTbl.jcms_v1SlamVictims[ victim ] then
			plyTbl.jcms_v1SlamVictims[ victim ] = true
			if victim:Health() > 0 and victim.TakeDamageInfo then
				local dmgAmount = 25
				if victim.jcms_danger == jcms.NPC_DANGER_FODDER then
					dmgAmount = 75
				elseif victim.jcms_danger == jcms.NPC_DANGER_STRONG then
					dmgAmount = 50
				end

				local dmg = DamageInfo()
				dmg:SetAttacker(ply)
				dmg:SetInflictor(ply)
				dmg:SetDamageType(DMG_CLUB)
				dmg:SetReportedPosition(pos1)
				dmg:SetDamagePosition(pos1)
				dmg:SetDamageForce(ply:GetVelocity())
				dmg:SetDamage(dmgAmount)
				victim:TakeDamageInfo(dmg)
				victim:EmitSound("physics/body/body_medium_break3.wav", 100, 97, 1)
			end
		end
	else
		if plyTbl.jcms_v1SlamVictims then
			plyTbl.jcms_v1SlamVictims = nil
		end
	end
end

-- Movement {{{
	function class.PerformPowerSlam(ply)
		ply:EmitSound("merekisv1ultrakill/slam.wav", 120)

		local ed = EffectData()
		ed:SetOrigin(ply:GetPos())
		ed:SetScale(200)
		ed:SetEntity(ply)
		util.Effect("ThumperDust", ed)

		-- reused from dog code
		local pos = ply:GetPos()
		local output = {}
		local trdata = { mask = MASK_SOLID, output = output }
		local downwards = Vector(0, 0, -20)
		
		local force = Vector(0, 0, 420)

		for i, ent in ipairs( ents.FindInSphere(pos, 300) ) do
			trdata.start = ent:GetPos()
			trdata.endpos = trdata.start + downwards
			trdata.filter = ent
			util.TraceEntityHull(trdata, ent)
				
			if output.Fraction < 1 then
				local phys = ent:GetPhysicsObject()
				if IsValid(phys) then
					local mt = ent:GetMoveType()
					if mt == MOVETYPE_STEP then
						ent:SetVelocity(force)
					elseif mt == MOVETYPE_WALK then
						ent:SetVelocity(force - ent:GetVelocity()*0.8)
					elseif mt == MOVETYPE_VPHYSICS then
						phys:Wake()
						phys:AddVelocity(force)
						phys:AddAngleVelocity(VectorRand(-100, 100))
					end
				end
			end
		end
	end

	function class.SetupMove(ply, mv, cmd)
		if not ply:Alive() then return end
		if not ply:GetMoveType() == MOVETYPE_WALK then return end
		if IsValid(ply:GetVehicle()) or IsValid(ply:GetNWEntity("jcms_vehicle")) then return end
		local plyTbl = ply:GetTable()
		local ct = CurTime()
		
		local isMoving = mv:GetForwardSpeed() ~= 0 or mv:GetSideSpeed() ~= 0 or mv:GetUpSpeed() ~= 0
		local isMovingStrictlyForward = mv:GetForwardSpeed() > 0 and mv:GetSideSpeed() == 0
		local isOnGround = ply:IsOnGround()
		local isSprinting = mv:KeyDown(IN_SPEED)
		local isCreeped = IsValid( jcms.zombieCreepCells[ jcms.zombieCreep_GetCell( ply:GetPos() ) ] )

		-- sprinthack but implemented manually {{{
			local nSpd = bit.bnot(IN_SPEED)
			local bttns = mv:GetButtons()
			mv:SetButtons(bit.band(nSpd, bttns))
		-- }}}

		local runSpeed = ply:GetRunSpeed()
		local slideSpeedMul = 1.45
		local slamPower = 1500
		local dashSpeedMul = isCreeped and 2.5 or 4.5
		local dashAirborneTime = 0.14
		local wallClimbSpeedMul = 0.45
		local powerSlamTime = 0.1

		local shouldDoScrapeSound = false

		-- calculating movement {{{
			local vel = mv:GetVelocity()
			local ang = ply:EyeAngles()
			local ang2D = Angle(0, ang.y, 0)
			local dir2D = ang2D:Forward()
			
			local dir2DSlide = dir2D
			if isMoving and not isMovingStrictlyForward then
				dir2DSlide = Vector(vel.x, vel.y, 0)
				dir2DSlide:Normalize()
			end

			local dir2DDesired
			if isMoving then
				local v1 = ang2D:Forward()
				v1:Mul( mv:GetForwardSpeed() )
				local v2 = ang2D:Right()
				v2:Mul( mv:GetSideSpeed() )
				v1:Add(v2)
				dir2DDesired = v1
				dir2DDesired:Normalize()
				-- GET THE Pu N>?? ? ? ?GET IT??? V2 GETS DESTROYED!! AND V1 LIVES ON!! WITH PART OF v2 IN IT!
			else
				dir2DDesired = ang2D:Forward()
			end
		-- }}}

		-- Storing air speed {{{
			local resetTopSpeed = false
			local speed2D = vel:Length2D()
			if isOnGround then
				if ct - (plyTbl.jcms_v1LastAirborneTime or 0) > dashAirborneTime then
					resetTopSpeed = true
				end
			else
				plyTbl.jcms_v1LastAirborneTime = ct
				if speed2D < runSpeed * slideSpeedMul then
					resetTopSpeed = true
				end
			end

			if resetTopSpeed then
				plyTbl.jcms_v1AirSpeedStore = runSpeed * slideSpeedMul
			else
				plyTbl.jcms_v1AirSpeedStore = math.max(speed2D, plyTbl.jcms_v1AirSpeedStore or 0)
			end
		-- }}}

		-- walls and air strafing {{{
			if not isOnGround then
				local checkDist = 10
				local pos = ply:GetPos()
				local checkPos = Vector(pos)
				local pos_x, pos_y, pos_z = pos:Unpack()

				local tr = {}
				local td = {
					start = pos,
					endpos = checkPos,
					filter = ply,
					mask = MASK_PLAYERSOLID_BRUSHONLY,
					output = tr
				}

				local wallHugging = false
				for i, walltracevec in ipairs(class.wallTraceVecs) do
					checkPos:SetUnpacked(pos_x + walltracevec[1]*checkDist, pos_y + walltracevec[2]*checkDist, pos_z)
					util.TraceEntityHull(td, ply)

					if tr.Hit then
						tr.WallTraceVec = walltracevec
						wallHugging = true
						break
					end
				end

				if wallHugging and not plyTbl.jcms_v1Slamming then
					local vel_new = mv:GetVelocity()
					local zspeed = vel.z
					local zcap = -runSpeed * wallClimbSpeedMul
					if zspeed < zcap then -- sliding down the walls instead of falling, caps z speed only if its negative and too fast
						vel_new.z = zcap
						mv:SetVelocity(vel_new)
						shouldDoScrapeSound = true
					end

					if mv:KeyPressed(IN_JUMP) and (plyTbl.jcms_v1WallJumps or 0) > 0 then
						local walltracevec = tr.WallTraceVec
						local wallNormal = Vector(
							-walltracevec[1]*0.88,
							-walltracevec[2]*0.88,
							1
						)
						
						wallNormal:Mul(ply:GetJumpPower())
						mv:SetVelocity(wallNormal)
						ply:EmitSound("npc/dog/dog_footstep_run"..math.random(1, 8)..".wav", 100, 117)
						
						plyTbl.jcms_v1WallJumps = math.max(0, (plyTbl.jcms_v1WallJumps or 0) - 1)
						if plyTbl.jcms_v1WallJumps == 0 then
							ply:EmitSound("npc/dog/dog_pneumatic"..math.random(1, 2)..".wav", 100, 130)
						end
					end
				end

				if speed2D < runSpeed and not wallHugging and not isOnGround and isMoving and not plyTbl.jcms_v1Slamming then
					local added = dir2DDesired * runSpeed
					added:Mul(FrameTime())
					vel:Add(added)
					mv:SetVelocity(vel)
				end
			else
				plyTbl.jcms_v1WallJumps = class.wallJumps
			end
		-- }}}

		-- john ultrakill actions {{{
			-- slam {{{
				if not isOnGround then
					if mv:KeyPressed(IN_DUCK) and not plyTbl.jcms_v1Slamming then
						mv:SetVelocity( Vector(0, 0, -slamPower) )
						plyTbl.jcms_v1Slamming = true
						plyTbl.jcms_v1HoldingSlamming = true
					end
				elseif plyTbl.jcms_v1Slamming then
					plyTbl.jcms_v1LastSlamLand = ct
					plyTbl.jcms_v1Slamming = false
				end

				if plyTbl.jcms_v1HoldingSlamming then
					if not mv:KeyDown(IN_DUCK) then
						plyTbl.jcms_v1HoldingSlamming = false
					end

					if isOnGround and plyTbl.jcms_v1LastSlamLand and (ct - plyTbl.jcms_v1LastSlamLand) > powerSlamTime then
						if not plyTbl.jcms_v1PerformedPowerSlam then
							plyTbl.jcms_v1PerformedPowerSlam = true
							class.PerformPowerSlam(ply)
						end
					end
				else
					plyTbl.jcms_v1PerformedPowerSlam = false
				end
			-- }}}

			-- slide {{{
				if mv:KeyDown(IN_DUCK) and isOnGround and not plyTbl.jcms_v1HoldingSlamming and plyTbl.jcms_v1SlideVector then
					mv:SetVelocity(isCreeped and plyTbl.jcms_v1SlideVectorCreeped or plyTbl.jcms_v1SlideVector)
					shouldDoScrapeSound = true
				else
					plyTbl.jcms_v1SlideVector = plyTbl.jcms_v1AirSpeedStore * dir2DSlide
					plyTbl.jcms_v1SlideVectorCreeped = plyTbl.jcms_v1SlideVector * 0.35
				end
			-- }}}

			-- dash {{{
				if isSprinting then
					if not plyTbl.jcms_v1Dashed and plyTbl.jcms_v1Stamina ~= nil then
						plyTbl.jcms_v1Dashed = true
						if plyTbl.jcms_v1Stamina >= 1 then
							if SERVER then
								plyTbl.jcms_v1Stamina = plyTbl.jcms_v1Stamina - 1
							end
							
							mv:SetVelocity( (runSpeed * dashSpeedMul) * dir2DDesired )
							plyTbl.jcms_v1LastDash = ct
							plyTbl.jcms_v1DashShouldCancel = not isOnGround
							ply:EmitSound("merekisv1ultrakill/dash.wav", 100)

							plyTbl.jcms_v1Slamming = false
							if SERVER then
								merekisv1ultrakill_NetSendStamina(ply, plyTbl.jcms_v1Stamina)
							end
						else
							ply:EmitSound("physics/metal/metal_sheet_impact_bullet2.wav", 100, 137, 0.5)
						end
					end
				else
					plyTbl.jcms_v1Dashed = false
				end
				
				-- staying airborne
				if (ct - (plyTbl.jcms_v1LastDash or 0) < dashAirborneTime) and (not plyTbl.jcms_v1Slamming) and (plyTbl.jcms_v1DashShouldCancel) then
					local vel_new = mv:GetVelocity()
					vel_new.z = 0
					mv:SetVelocity(vel_new)
				elseif plyTbl.jcms_v1DashShouldCancel then
					plyTbl.jcms_v1DashShouldCancel = false
					local vel_new = mv:GetVelocity()
					local speed_new = vel_new:Length()
					if speed_new > runSpeed and speed_new ~= 0 then
						local reductionMul = runSpeed / speed_new
						vel_new:Mul(reductionMul)
						mv:SetVelocity(vel_new)
					end
				end
			-- }}}
		-- }}}

		-- scraping and jumping sound {{{
			if shouldDoScrapeSound then
				if not plyTbl.jcms_v1ScrapeSnd then
					plyTbl.jcms_v1ScrapeSnd = CreateSound(ply, "physics/metal/canister_scrape_rough_loop1.wav")
				end

				plyTbl.jcms_v1ScrapeSnd:PlayEx(1, 187)
			else
				if plyTbl.jcms_v1ScrapeSnd then
					plyTbl.jcms_v1ScrapeSnd:Stop()
					plyTbl.jcms_v1ScrapeSnd = nil
				end
			end

			if mv:KeyPressed(IN_JUMP) and isOnGround then
				ply:EmitSound("npc/dog/dog_footstep_run02.wav", 100, 147)
			end
		-- }}}
	end
-- }}}

-- Style mechanics {{{
	if CLIENT then
		surface.CreateFont("merekisv1ultrakill_style", {
			font = system.IsLinux() and "jcms_semibold.ttf" or "IBM Plex Sans SemiBold",
			antialias = true,
			extended = true,
			size = 105
		})
	end

	class.styleRanks = { -- 1-indexed for logic but 0-indexed for net!
		{
			letter = "D", letter_col = Color(89, 89, 211),
			rest = "estructive", rest_col = color_white,
			hideIfEmpty = true,
			
			hurtMul = 1, invTime = 0,
			scoreCapacity = 100,
			scoreFullDecayTime = 15
		},

		{
			letter = "C", letter_col = Color(77, 236, 103),
			rest = "haotic", rest_col = color_white,

			hurtMul = 0.9, invTime = 0,
			scoreCapacity = 110,
			scoreFullDecayTime = 14
		},

		{
			letter = "B", letter_col = Color(241, 224, 69),
			rest = "rutal", rest_col = color_white,

			hurtMul = 0.8, invTime = 0,
			scoreCapacity = 120,
			scoreFullDecayTime = 13
		},

		{
			letter = "A", letter_col = Color(231, 145, 64),
			rest = "narchic", rest_col = color_white,

			hurtMul = 0.75, invTime = 0,
			scoreCapacity = 130,
			scoreFullDecayTime = 11
		},

		{
			letter = "S", letter_col = Color(170, 30, 30),
			rest = "upreme", rest_col = color_white,

			hurtMul = 0.7, invTime = 0.015,
			scoreCapacity = 140,
			scoreFullDecayTime = 10
		},

		{
			letter = "SS", letter_col = Color(202, 34, 34),
			rest = "adistic", rest_col = Color(255, 198, 198),

			hurtMul = 0.65, invTime = 0.02,
			scoreCapacity = 145,
			scoreFullDecayTime = 9
		},

		{
			letter = "SSS", letter_col = Color(226, 14, 14),
			rest = "hitstorm", rest_col = Color(255, 143, 143),

			hurtMul = 0.6, invTime = 0.025,
			scoreCapacity = 150,
			scoreFullDecayTime = 8
		},

		{
			letter = "MAP SWEEPER", letter_col = Color(255, 0, 0), final = true,

			hurtMul = 0.45, invTime = 0.05,
			scoreCapacity = 150,
			scoreFullDecayTime = 7
		}
	}

	class.styleNominations = {
		{ -- KILL
			name = "kill",
			name_displayFunc = function(count)
				if count <= 3 then
					return "#merekisv1ultrakill.nom_kill" .. count
				else
					return language.GetPhrase("merekisv1ultrakill.nom_killx"):format(count)
				end
			end,

			score_calcFunc = function(count)
				if count == 1 then
					return 10
				elseif count == 2 then
					return 30
				elseif count == 3 then
					return 80
				else
					return 100 + (count-3)*15
				end
			end,

			expireTime = 0.25 -- no expire time = applies instantly (same as expireTime=0)
		},

		{ -- SWARMER KILL
			name = "weakkill",
			name_displayFunc = function(count)
				if count <= 3 then
					return "#merekisv1ultrakill.nom_weakkill" .. count
				else
					return language.GetPhrase("merekisv1ultrakill.nom_weakkillx"):format(count)
				end
			end,

			score_calcFunc = function(count)
				if count == 1 then
					return 3
				elseif count == 2 then
					return 15
				elseif count == 3 then
					return 30
				else
					return 50 + (count-3)*12
				end
			end,

			expireTime = 0.25,
			meh = true
		},

		{ -- AIR KILL
			name = "airkill",
			name_displayFunc = function(count)
				if count > 1 then
					return language.GetPhrase("#merekisv1ultrakill.nom_airkillx"):format(count)
				else
					return "#merekisv1ultrakill.nom_airkill"
				end
			end,

			score_calcFunc = function(count)
				if count == 1 then
					return 40
				elseif count == 2 then
					return 100
				elseif count == 3 then
					return 180
				else
					return 200 + 25*(count-3)
				end
			end,
			
			expireTime = 0.35
		},

		{ -- HEADSHOT
			name = "headshot",
			score = 55
		},
		
		{ -- BULLSEYE (AIR HEADSHOT)
			name = "airheadshot",
			score = 135,
			cool = true
		},

		{ -- EXPLODED / NUKED
			name = "exploded",
			name_displayFunc = function(count)
				if count == 1 then
					return "#merekisv1ultrakill.nom_exploded"
				elseif count >= 50 then
					return language.GetPhrase("merekisv1ultrakill.nom_explodednuke"):format(count)
				else
					return language.GetPhrase("merekisv1ultrakill.nom_explodedx"):format(count)
				end
			end,

			score_calcFunc = function(count)
				if count == 1 then
					return 30
				elseif count == 2 then
					return 75
				elseif count == 3 then
					return 100
				else
					local nukeBonus = count >= 50 and 300 or 0
					return 110 + (count-3)*10 + nukeBonus
				end
			end,

			expireTime = 0.35,
			expireTimeRenews = 0.2
		},

		{ -- VAPORIZED
			name = "dissolved",
			name_displayFunc = function(count)
				if count == 1 then
					return "#merekisv1ultrakill.nom_dissolved"
				else
					return language.GetPhrase("merekisv1ultrakill.nom_dissolvedx"):format(count)
				end
			end,

			score_calcFunc = function(count)
				if count == 1 then
					return 25
				elseif count == 2 then
					return 70
				elseif count == 3 then
					return 90
				else
					return 100 + (count-3)*9
				end
			end,

			expireTime = 0.45,
			expireTimeRenews = 0.3
		},

		{ -- MINCED
			name = "minced",
			score = 15,
			meh = true
		},

		{ -- AIR MINCED
			name = "airminced",
			score = 60,
			cool = true
		},

		{ -- FIREWORKS
			name = "airexploded",
			name_displayFunc = function(count)
				if count > 1 then
					return language.GetPhrase("merekisv1ultrakill.nom_airexplodedx"):format(count)
				else
					return "#merekisv1ultrakill.nom_airexploded"
				end
			end,

			score_calcFunc = function(count)
				if count == 1 then
					return 55
				elseif count == 2 then
					return 135
				elseif count == 3 then
					return 210
				else
					return 250 + (count-3)*25
				end
			end,

			expireTime = 0.2,
			cool = true
		},

		{ -- DISRESPECT
			name = "disrespect",
			score = 8
		},

		{ -- BACKFIRE
			name = "backfire",
			name_displayFunc = function(count)
				if count > 1 then
					return language.GetPhrase("merekisv1ultrakill.nom_backfirex"):format(count)
				else
					return "#merekisv1ultrakill.nom_backfire"
				end
			end,

			score_calcFunc = function(count)
				return 150 + (count-1)*30
			end,

			expireTime = 0.1,
			cool = true
		},

		{ -- POINT DEFENSE
			name = "pointdefense",
			score = 20
		},

		{ -- TURRET KILL
			name = "turretkill",
			name_displayFunc = function(count)
				if count <= 1 then
					return "#merekisv1ultrakill.nom_turretkill"
				else
					return language.GetPhrase("merekisv1ultrakill.nom_turretkillx"):format(count)
				end
			end,

			score_calcFunc = function(count)
				return 1 + count*2
			end,

			expireTime = 0.5,
			expireTimeRenews = 0.15,

			meh = true
		},

		{ -- ZAPPED (tesla kill)
			name = "teslakill",
			name_displayFunc = function(count)
				if count <= 1 then
					return "#merekisv1ultrakill.nom_teslakill"
				else
					return language.GetPhrase("merekisv1ultrakill.nom_teslakillx"):format(count)
				end
			end,

			score_calcFunc = function(count)
				return 1 + math.ceil(count^1.75)
			end,

			expireTime = 0.5,
			expireTimeRenews = 0.25,

			meh = true
		},

		{ -- FRIED
			name = "fried",
			name_displayFunc = function(count)
				if count <= 1 then
					return "#merekisv1ultrakill.nom_fried"
				else
					return language.GetPhrase("merekisv1ultrakill.nom_friedx"):format(count)
				end
			end,

			score_calcFunc = function(count)
				return 4 + math.ceil(count^1.65)
			end,

			expireTime = 0.75,
			expireTimeRenews = 0.66,

			meh = true
		},

		{ -- STUNSTICK KILL
			name = "stunstickkill",
			name_displayFunc = function(count)
				if count <= 1 then
					return "#merekisv1ultrakill.nom_stunstickkill"
				else
					return language.GetPhrase("merekisv1ultrakill.nom_stunstickkillx"):format(count)
				end
			end,

			score_calcFunc = function(count)
				return 15 + math.ceil(count^2)*10
			end,

			expireTime = 0.3
		},

		{ -- STUNDUNK
			name = "airstunstickkill",
			score = 75,
			cool = true
		},

		{ -- CRABBED
			name = "crabbed",
			name_displayFunc = function(count)
				if count <= 1 then
					return "#merekisv1ultrakill.nom_crabbed"
				else
					return language.GetPhrase("merekisv1ultrakill.nom_crabbedx"):format(count)
				end
			end,

			score_calcFunc = function(count)
				return math.ceil(count^1.5)*12
			end,

			expireTime = 0.1,
			cool = true
		},

		{ -- BOSS DOWN
			name = "bosskill",
			score = 100
		},

		{ -- HOME RUN
			name = "homerun",
			score = 120,
			cool = true
		},

		{ -- RECLAIMED
			name = "unhack",
			score = 10
		},

		{ -- ROADKILL
			name = "runover",
			name_displayFunc = function(count)
				if count <= 1 then
					return "#merekisv1ultrakill.nom_runover"
				else
					return language.GetPhrase("merekisv1ultrakill.nom_runoverx"):format(count)
				end
			end,

			score_calcFunc = function(count)
				if count == 1 then
					return 8
				elseif count == 2 then
					return 25
				elseif count == 3 then
					return 65
				else
					return 80 + (count-3)*15
				end
			end,

			expireTime = 0.5,
			expireTimeRenews = 0.25,
		}
	}

	class.styleNominationsIndexDict = {}
	for i, nomination in ipairs(class.styleNominations) do
		class.styleNominationsIndexDict[ nomination.name ] = i
	end

	function class.GetCurrentStyleRank(ply)
		local rankId = ply.jcms_v1StyleRankId or 1
		return class.styleRanks[ math.Clamp(rankId, 1, #class.styleRanks) ]
	end

	function class.GetCurrentStyleScore(ply)
		local rank = class.GetCurrentStyleRank(ply)
		local score = ply.jcms_v1StyleScore or 0
		return math.Clamp( score, 0, rank.scoreCapacity )
	end

	if SERVER then
		function merekisv1ultrakill_NetSendStyle(ply, rank, score, nominations)
			net.Start("merekisv1ultrakillmsg")
				net.WriteBool(false)
				net.WriteUInt((tonumber(rank) or 1) - 1, 3)
				net.WriteUInt(tonumber(score) or 0, 8)

				local nominationBitCount = 6
				local nominationMaxCount = (2^nominationBitCount) - 1
				if type(nominations) == "table" then
					net.WriteUInt(math.min(nominationMaxCount, #nominations), nominationBitCount)
					local start_i = math.max(1, #nominations - nominationMaxCount + 1)
					for i=start_i, #nominations do
						local nom = nominations[i]
						if type(nom) == "table" and type(nom.id) == "number" then
							net.WriteUInt(nom.id, 5)
							if nom.count > 15 then
								net.WriteBool(true) -- extended bits
								net.WriteUInt(math.min(65535, nom.count), 16)
							else
								net.WriteBool(false)
								net.WriteUInt(math.max(0, nom.count), 4)
							end
						end 
					end
				else
					net.WriteUInt(0, nominationBitCount)
				end
			net.Send(ply)
		end

		function merekisv1ultrakill_AddNomination(ply, name, count)
			count = tonumber(count) or 1
			name = tostring(name or "kill")

			local nomIndex = class.styleNominationsIndexDict[ name ] 
			if not nomIndex then
				return
			end
			local nomData = class.styleNominations[ nomIndex ]

			if not ply.jcms_v1Nominations then
				ply.jcms_v1Nominations = {}
			end

			local ct = CurTime()
			local nom = ply.jcms_v1Nominations[ name ]
			if nom then
				nom.count = nom.count + count
				if nomData.expireTimeRenew then
					nom.expiresAt = math.max(nom.expiresAt, ct + nomData.expireTimeRenew)
				end
			else
				nom = { count = count, expiresAt = ct + (nomData.expireTime or 0) }
				ply.jcms_v1Nominations[ name ] = nom
			end

			return nom
		end

		function merekisv1ultrakill_ThinkStyle(ply, dt)
			local rank = class.GetCurrentStyleRank(ply)
			local score = class.GetCurrentStyleScore(ply)

			if not ply.jcms_v1Nominations then return end
			local ct = CurTime()

			ply.jcms_v1StyleScore = math.max(0, score - dt * rank.scoreCapacity / rank.scoreFullDecayTime)
			local networkedNominations = {}
			local shouldNetwork = false

			for name, nom in pairs(ply.jcms_v1Nominations) do
				local nomIndex = class.styleNominationsIndexDict[ name ]
				if not nomIndex then
					ply.jcms_v1Nominations[ name ] = nil
					continue 
				end

				if ct >= nom.expiresAt then
					ply.jcms_v1Nominations[ name ] = nil
					local nomData = class.styleNominations[ nomIndex ]

					local score = tonumber(nomData.score) or 0
					if nomData.score_calcFunc then
						score = tonumber( nomData.score_calcFunc(nom.count) ) or 0
					end

					ply.jcms_v1StyleScore = ply.jcms_v1StyleScore + score
					table.insert(networkedNominations, { id = nomIndex, count = nom.count })
					shouldNetwork = true
				end
			end

			ply.jcms_v1StyleRankId = ply.jcms_v1StyleRankId or 1
			ply.jcms_v1StyleScore = ply.jcms_v1StyleScore or 0

			for i=1, 8 do -- would use a while loop here but don't want to accidentally freeze the game
				if ply.jcms_v1StyleScore <= 0 then
					-- Decreasing rank
					if ply.jcms_v1StyleRankId > 1 then -- cant decrease below the first
						ply.jcms_v1StyleRankId = ply.jcms_v1StyleRankId - 1
						local rank_new = class.GetCurrentStyleRank(ply)
						ply.jcms_v1StyleScore = rank_new.scoreCapacity
						shouldNetwork = true
					end
					break
				else
					local rank_cur = class.GetCurrentStyleRank(ply)
					if ply.jcms_v1StyleScore > rank_cur.scoreCapacity then
						if ply.jcms_v1StyleRankId < #class.styleRanks then
							-- level up to new rank
							ply.jcms_v1StyleScore = ply.jcms_v1StyleScore - rank_cur.scoreCapacity
							ply.jcms_v1StyleRankId = math.min(#class.styleRanks, ply.jcms_v1StyleRankId + 1)
							shouldNetwork = true
						else
							-- final rank reached - simply clamp
							ply.jcms_v1StyleScore = math.min(ply.jcms_v1StyleScore, rank_cur.scoreCapacity)
							shouldNetwork = true
							break
						end
					else
						break
					end
				end
			end

			if shouldNetwork then
				merekisv1ultrakill_NetSendStyle(ply, ply.jcms_v1StyleRankId, ply.jcms_v1StyleScore, networkedNominations)
			end
		end

		function merekisv1ultrakill_SetupStyleTimer(ply)
			local timerId = "merekisv1ultrakill_StyleThink" .. ply:EntIndex() .. ply:Nick()
			local dt = 0.1
			timer.Create(timerId, dt, 0, function()
				if not (IsValid(ply) and ply:Alive() and ply:GetNWString("jcms_class") == "merekisv1ultrakill") then
					timer.Remove(timerId)
					return
				end

				merekisv1ultrakill_ThinkStyle(ply, dt)
			end)
		end
	end

	if CLIENT then
		function merekisv1ultrakill_AddNomination(name, count)
			local nomIndex = class.styleNominationsIndexDict[name]
			if not nomIndex then return end
			local ply = LocalPlayer()

			if not ply.jcms_v1StyleNominations then
				ply.jcms_v1StyleNominations = {}
			end

			local nomCount = #ply.jcms_v1StyleNominations
			local delay = 0
			if nomCount > 8 then
				delay = (nomCount - 8)*0.07
			end

			table.insert(ply.jcms_v1StyleNominations, { index = nomIndex, name = name, count = count, alpha = 0, y = 0, delay = delay, timeleft = 7 })
		end

		hook.Add("Think", "merekisv1ultrakill_StyleThink", function()
			local ply = LocalPlayer()
			if not ply:Alive() then return end
			if ply:GetObserverMode() ~= OBS_MODE_NONE then return end
			if ply:GetNWString("jcms_class", "infantry") ~= "merekisv1ultrakill" then return end
			local dt = FrameTime()
			
			local rank = class.GetCurrentStyleRank(ply)
			ply.jcms_v1StyleScore = math.max(0, (ply.jcms_v1StyleScore or 0) - dt * rank.scoreCapacity / rank.scoreFullDecayTime)
			
			local nominations = ply.jcms_v1StyleNominations
			if nominations and #nominations > 0 then
				for i=#nominations, 1, -1 do
					local nom = nominations[i]
					local isAlive = nom.delay > 0 or nom.timeleft > 0
					local pressureMul = (#nominations > 8 and i==1) and 5 or 1
					
					local W = (dt > 1/30) and 1 or 4
					nom.y = (nom.y*W + (i-1))/(W+1)

					if isAlive then
						if nom.delay > 0 then
							nom.delay = math.max(0, nom.delay - dt)
						else
							nom.alpha = math.min(1, nom.alpha + dt*8)
							nom.timeleft = math.max(0, nom.timeleft - dt*pressureMul)
						end
					else
						nom.alpha = math.max(0, nom.alpha - dt*4)
						if nom.alpha <= 0 then
							table.remove(nominations, i)
						end
					end
				end
			end
		end)
	end
-- }}}

-- Network {{{
	if SERVER then
		util.AddNetworkString("merekisv1ultrakillmsg")

		function merekisv1ultrakill_NetSendStamina(ply, value)
			net.Start("merekisv1ultrakillmsg")
				net.WriteBool(true)
				net.WriteFloat(tonumber(value) or 0)
			net.Send(ply)
		end
	end

	if CLIENT then
		net.Receive("merekisv1ultrakillmsg", function(len)
			local ply = LocalPlayer()
			local isStamina = net.ReadBool()
			if isStamina then
				-- Update stamina
				ply.jcms_v1Stamina = net.ReadFloat()
			else
				-- Style
				ply.jcms_v1StyleRankId = net.ReadUInt(3) + 1
				ply.jcms_v1StyleScore = net.ReadUInt(8)

				local nomCount = net.ReadUInt(6)
				if ply.jcms_v1StyleRankId == 0 and ply.jcms_v1StyleScore == 0 and nomCount == 0 then
					-- clear the nominations since all zeros means we just spawned in
					if type(ply.jcms_v1StyleNominations) == "table" then
						table.Empty(ply.jcms_v1StyleNominations)
					else
						ply.jcms_v1StyleNominations = {}
					end
				end

				for i=1, nomCount do
					local nomId = net.ReadUInt(5)
					local nomCount = 0

					local extended = net.ReadBool()
					if extended then
						nomCount = net.ReadUInt(16)
					else
						nomCount = net.ReadUInt(4)
					end

					if class.styleNominations[nomId] then
						local s, err = pcall(merekisv1ultrakill_AddNomination, class.styleNominations[nomId].name, nomCount)
						if not s then ErrorNoHaltWithStack(err) end
					end
				end
			end
		end)
	end
-- }}}

if SERVER then
	-- Healing {{{
		merekisv1ultrakill_allV1s = merekisv1ultrakill_allV1s or {}

		function merekisv1ultrakill_CheckV1(ply)
			return IsValid(ply) and ply:IsPlayer() and ply:Alive() and ply:Health() > 0 and ply:GetObserverMode() == OBS_MODE_NONE and ply:GetNWString("jcms_class", "infantry") == "merekisv1ultrakill"
		end

		function merekisv1ultrakill_UpdateV1s(add)
			local dict = {}
			for i=#merekisv1ultrakill_allV1s, 1, -1 do
				local ply = merekisv1ultrakill_allV1s[i]
				if dict[ply] or not merekisv1ultrakill_CheckV1(ply) then
					table.remove(merekisv1ultrakill_allV1s, i)
				end
				dict[ply] = true
			end

			if add and not dict[add] and merekisv1ultrakill_CheckV1(add) then
				table.insert(merekisv1ultrakill_allV1s, add)
			end
			
			return merekisv1ultrakill_allV1s
		end

		function merekisv1ultrakill_HandleBloodDousing(victim, dmg)
			local dmgPos = dmg:GetDamagePosition()
			local victimPos = victim:WorldSpaceCenter()
			local rad2 = 256^2
			for i, ply in ipairs( merekisv1ultrakill_UpdateV1s() ) do
				if ply == victim then continue end
				local plyPos = ply:WorldSpaceCenter()
				if plyPos:DistToSqr(dmgPos) <= rad2 or plyPos:DistToSqr(victimPos) <= rad2 then
					local healingDone = math.min( victim:GetMaxHealth()/2, dmg:GetDamage()/2, (victim.jcms_bounty or 100)/3.5 )
					local attacker = dmg:GetAttacker()
					if attacker ~= ply then
						healingDone = healingDone * 0.3
					end
					merekisv1ultrakill_Heal(ply, healingDone)
				end
			end
		end

		function merekisv1ultrakill_Heal(ply, amount)
			if amount <= 0 then return end
			if ply:Health() >= ply:GetMaxHealth() then return end
			
			local accumulator = tonumber( ply:GetInternalVariable("m_flDamageAccumulator") ) or 0
			local newAccumulator = accumulator - amount

			if newAccumulator >= 0 then
				ply:SetSaveValue("m_flDamageAccumulator", newAccumulator)
			else
				local addedWholes = math.ceil(-newAccumulator)
				if addedWholes > 0 then
					local health = ply:Health()
					ply:SetHealth( math.Clamp(health + addedWholes, health, ply:GetMaxHealth()) )
				end
				
				if ply:Health() >= ply:GetMaxHealth() then
					ply:SetSaveValue("m_flDamageAccumulator", 0)
				else
					newAccumulator = newAccumulator % 1
					ply:SetSaveValue("m_flDamageAccumulator", newAccumulator)
				end
			end
		end

		hook.Add("PostEntityTakeDamage", "merekisv1ultrakill_HealFromDamage", function(ent, dmg, wasTaken)
			if not wasTaken then return end
			if dmg:GetDamage() <= 0 then return end
			if not (ent:IsNPC() or ent:IsNextBot() or ent:IsPlayer()) then return end
			merekisv1ultrakill_HandleBloodDousing(ent, dmg)
		end)
	-- }}}

	-- Invincibility {{{
		function class.GetHurtMul(ply)
			return class.GetCurrentStyleRank(ply).hurtMul
		end

		function class.GetInvincibilityTime(ply)
			return class.GetCurrentStyleRank(ply).invTime
		end

		function class.TakeDamage(ply, dmg)
			local dmgType = dmg:GetDamageType()
			if bit.band(dmgType, bit.bor(DMG_BLAST, DMG_BLAST_SURFACE, DMG_CRUSH)) > 0 then
				dmg:ScaleDamage(0.5)

				local v
				if IsValid(dmg:GetInflictor()) then
					v = ply:EyePos() - dmg:GetInflictor():WorldSpaceCenter()
				else
					v = dmg:GetDamagePosition() - dmg:GetReportedPosition()
				end
				local force = math.max(0, math.Remap(v:Length(), 0, 200, 800, 100))

				if force > 0 then
					v:Normalize()
					v.z = v.z + 0.1
					v:Mul(force)
					ply:SetVelocity(v)
				end
			end

			if bit.band(dmgType, bit.bor(DMG_SLASH, DMG_CLUB)) > 0 then
				dmg:ScaleDamage(2.5)

				if dmg:GetDamage() < 20 and dmg:GetDamage() > 0.1 then
					dmg:SetDamage(20)
				end
			end

			dmg:ScaleDamage(class.GetHurtMul(ply))

			local amount = dmg:GetDamage()
			local plyTbl = ply:GetTable()
			local ct = CurTime()

			if plyTbl.jcms_v1InvUntil and ct <= plyTbl.jcms_v1InvUntil then
				dmg:ScaleDamage(0.01) -- pseudo invincibility frames, take 1% damage
				jcms_util_shieldDamageEffect(dmg, amount)
			else
				plyTbl.jcms_v1InvUntil = ct + class.GetInvincibilityTime(ply)
			end
		end
	-- }}}

	function class.OnKill(ply, npc, inflictor)
		if not ( IsValid(npc) and npc:IsNPC() or npc:IsNextBot() ) then return end
		local lastTrace = npc.jcms_lastHurtTrace
		local lastDamageType = npc.jcms_lastDamageType or DMG_GENERIC

		if not IsValid(inflictor) then inflictor = nil end
		local isMidair = not npc:IsOnGround() and (npc:GetMoveType() == MOVETYPE_STEP or npc:GetMoveType() == MOVETYPE_WALK)

		if npc.jcms_danger and npc.jcms_danger >= jcms.NPC_DANGER_BOSS then
			merekisv1ultrakill_AddNomination(ply, "bosskill", 1)
		end

		if inflictor then
			if inflictor == npc then
				merekisv1ultrakill_AddNomination(ply, "backfire", 1)
			elseif inflictor.GetTurretKind then
				merekisv1ultrakill_AddNomination(ply, "turretkill", 1)
				return
			elseif inflictor:GetClass() == "jcms_tesla" then
				merekisv1ultrakill_AddNomination(ply, "teslakill", 1)
				return
			elseif jcms.util_IsStunstick(inflictor) then
				merekisv1ultrakill_AddNomination(ply, isMidair and "airstunstickkill" or "stunstickkill", 1)
				return
			elseif inflictor:GetClass() == "npc_headcrab_fast" then
				merekisv1ultrakill_AddNomination(ply, "crabbed", 1)
				return
			elseif inflictor:GetClass() == "jcms_landmine" and not constraint.HasConstraints(inflictor) then
				local phys = inflictor:GetPhysicsObject()
				if IsValid(phys) and phys:GetVelocity():LengthSqr() >= 1000^2 then
					merekisv1ultrakill_AddNomination(ply, "homerun", 1)
					return
				end
			end
		end
		
		local isHeadshot = lastTrace and lastTrace.HitGroup == HITGROUP_HEAD or false

		if bit.band(lastDamageType, DMG_VEHICLE) > 0 then
			merekisv1ultrakill_AddNomination(ply, "runover", 1)
			return
		end

		if bit.band(lastDamageType, DMG_DISSOLVE) > 0 then
			merekisv1ultrakill_AddNomination(ply, "dissolved", 1)
			return
		end

		if bit.band(lastDamageType, DMG_CRUSH) > 0 or (bit.band(lastDamageType, DMG_CLUB) > 0 and inflictor == ply) then
			merekisv1ultrakill_AddNomination(ply, isMidair and "airminced" or "minced", 1)
			return
		end

		if isHeadshot and bit.band(lastDamageType, DMG_BULLET) > 0 then
			merekisv1ultrakill_AddNomination(ply, isMidair and "airheadshot" or "headshot", 1)
		end

		if bit.band(lastDamageType, bit.bor(DMG_BLAST, DMG_BLAST_SURFACE)) > 0 then
			if inflictor and inflictor:GetOwner() == npc then
				merekisv1ultrakill_AddNomination(ply, "backfire", 1)
			else
				merekisv1ultrakill_AddNomination(ply, isMidair and "airexploded" or "exploded", 1)
			end
			return
		end

		if bit.band(lastDamageType, bit.bor(DMG_BURN, DMG_SLOWBURN)) > 0 and bit.band(lastDamageType, bit.bor(DMG_BULLET, DMG_SLASH, DMG_CLUB, DMG_BUCKSHOT)) == 0 then
			merekisv1ultrakill_AddNomination(ply, "fried", 1)
			return
		end

		local isWeak = npc:GetMaxHealth() <= 20 or (npc.jcms_bounty and npc.jcms_bounty < 20)
		merekisv1ultrakill_AddNomination(ply, isMidair and "airkill" or (isWeak and "weakkill" or "kill"), 1)
	end

	function class.OnDealDamage(ply, ent, dmg)
		local inflictor = dmg:GetInflictor()
		local isStunstick = IsValid(inflictor) and jcms.util_IsStunstick(inflictor)
		
		if isStunstick then
			if ent.jcms_danger and ent.jcms_danger >= jcms.NPC_DANGER_BOSS then
				merekisv1ultrakill_AddNomination(ply, "disrespect", 1)
				return
			elseif ent.GetHackedByRebels and ent:GetHackedByRebels() then
				merekisv1ultrakill_AddNomination(ply, "unhack", 1)
				return
			end
		end

		if ent:Health() > 0 and dmg:GetDamage() > ent:Health() then
			local entclass = ent:GetClass()
			if entclass == "jcms_micromissile" and ent.jcms_owner ~= ply then
				merekisv1ultrakill_AddNomination(ply, "pointdefense", 1)
			end
		end 
	end
end

if CLIENT then
	function class.DrawHUD(ply)
		class.DrawHUDStamina(ply)
		class.DrawHUDStyle(ply)
	end

	function class.DrawHUDStamina(ply)
		local stamina = ply.jcms_v1Stamina or 0
		local staminaWidth = 100
		local hasEnough = stamina >= 1
		local off = 6

		jcms.setup3d2dDiagonal(false, true)
			surface.SetDrawColor(hasEnough and jcms.color_dark_alt or jcms.color_dark)
			for i=1, 3 do
				surface.DrawRect(250 + (staminaWidth + 12)*(i-1), -100, staminaWidth, 16)
			end

			surface.SetDrawColor(hasEnough and jcms.color_bright_alt or jcms.color_bright)
			render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
			for i=1, 3 do
				if stamina >= i then
					surface.DrawRect(250 + (staminaWidth + 12)*(i-1) + off, -100 - off, staminaWidth, 16)
				else
					local staminaRemainder = stamina%1
					if staminaRemainder > 0 then
						surface.DrawRect(250 + (staminaWidth + 12)*(i-1) + off, -100 - off, staminaWidth*staminaRemainder, 16)
					end
					break
				end
			end
			render.OverrideBlend(false)
		cam.End3D2D()
	end

	function class.DrawHUDStyle(ply)
		local w, h = 600, 1000
		local x, y = -100 - w, -h/2 - 200
		
		local h_rank = 150
		local h_timer = 32

		local deathPhrase = "#merekisv1ultrakill.death"
		local deathPhraseChance = 0
		if not ply:Alive() then 
			deathPhraseChance = 0.4
		else
			deathPhraseChance = math.Clamp(math.Remap(ply:Health(), 0, ply:GetMaxHealth()*0.05, 0.3, 0), 0, 0.3)
		end

		local rank = class.GetCurrentStyleRank(ply)
		local score = class.GetCurrentStyleScore(ply)

		local scoreFrac = math.Clamp(score / rank.scoreCapacity, 0, 1)
		local nominations = ply.jcms_v1StyleNominations

		if rank.hideIfEmpty and score <= 0 and (not nominations or #nominations <= 0) then
			return
		end

		jcms.setup3d2dCentral("right")
			surface.SetAlphaMultiplier(0.5)
				surface.SetDrawColor(jcms.color_dark)
				surface.DrawRect(x, y, w, h_rank)
				surface.DrawRect(x + 32, y + h_rank + 32, w, h_timer)
			surface.SetAlphaMultiplier(1)

			local off = 4
			render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
				surface.SetDrawColor(jcms.color_bright)
				surface.DrawRect(x + 24, y - 10, w - 64, 4)
				surface.DrawRect(x + 48, y + h_rank + 6, w - 64, 4)
				surface.SetDrawColor(jcms.color_pulsing)
				jcms.hud_DrawStripedRect(x + 32 - off, y + h_rank + 32, w, h_timer, 72, CurTime()%1*72)
				surface.SetDrawColor(jcms.color_bright)
				surface.DrawRect(x + 32 - off, y + h_rank + 32, w*scoreFrac, h_timer)
			render.OverrideBlend(false)

			local font = "merekisv1ultrakill_style"
			surface.SetFont(font)
			local tw_all = surface.GetTextSize(rank.letter .. (rank.rest or ""))

			if rank.hurtMul < 1 then
				local str = language.GetPhrase("merekisv1ultrakill.hurtmul"):format( math.Round( (rank.hurtMul - 1)*100 ) )
				if math.random() < deathPhraseChance then
					str = deathPhrase
				end

				draw.SimpleText(str, "jcms_hud_small", x - 16, y - 24, jcms.color_dark, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
				render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
					draw.SimpleText(str, "jcms_hud_small", x - 16 - off/2, y - 24, jcms.color_bright, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
				render.OverrideBlend(false)
			end

			if rank.invTime > 0 then
				local str = language.GetPhrase("merekisv1ultrakill.invframes"):format(rank.invTime*1000)
				if math.random() < deathPhraseChance then
					str = deathPhrase
				end

				draw.SimpleText(str, "jcms_hud_small", x + w + 16, y - 24, jcms.color_dark_alt, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
				render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
					draw.SimpleText(str, "jcms_hud_small", x + w + 16 - off/2, y - 24, jcms.color_bright_alt, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
				render.OverrideBlend(false)
			end

			if rank.final then
				for i=1, 3 do
					local shake_a = math.random() * math.pi * 2
					local shake_mag = math.random() * (8 + i*4)
					local shake_x, shake_y = math.cos(shake_a)*shake_mag, math.sin(shake_a)*shake_mag
					local col = rank.letter_col
					if i == 2 then
						col = jcms.color_alert1
					elseif i == 3 then
						col = jcms.color_alert2
					end
					
					render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
					draw.SimpleText(rank.letter, font, x + w/2 - tw_all/2 + shake_x, y + h_rank/2 + shake_y, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					render.OverrideBlend(false)
				end
			else
				local tw1 = draw.SimpleText(rank.letter, font, x + w/2 - tw_all/2, y + h_rank/2, rank.letter_col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				if rank.rest then
					draw.SimpleText(rank.rest, font, x + w/2 - tw_all/2 + tw1, y + h_rank/2, rank.rest_col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end

			end

			if nominations and #nominations > 0 then
				for i, nom in ipairs(nominations) do
					local nomData = class.styleNominations[ nom.index or -1 ]
					if nomData and nom.alpha > 0 then
						surface.SetAlphaMultiplier(nom.alpha^2)
						local text = "+ "
						if nomData.name_displayFunc then
							text = text .. language.GetPhrase(tostring(nomData.name_displayFunc(nom.count)))
						else
							text = text .. language.GetPhrase("merekisv1ultrakill.nom_" .. nomData.name)
						end

						if math.random() < deathPhraseChance then
							text = deathPhrase
						end

						local isSpecial = not nomData.expireTime
						local col = isSpecial and jcms.color_bright_alt or jcms.color_bright
						local colDark = isSpecial and jcms.color_dark_alt or jcms.color_dark

						if nomData.cool then
							col = jcms.color_alert
						elseif nomData.meh then
							col = jcms.color_pulsing
						end

						local nom_y = y + h_rank + h_timer + 84 + 72*nom.y
						draw.SimpleText(text, "jcms_hud_big", x, nom_y, colDark)
						render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
							draw.SimpleText(text, "jcms_hud_big", x - off, nom_y, col)
						render.OverrideBlend(false)
						surface.SetAlphaMultiplier(1)
					end
				end
			end
		cam.End3D2D()
	end

	hook.Add("Think", "merekisv1ultrakill_StaminaRestoration", function()
		local ply = LocalPlayer()

		if not ply.jcms_v1Stamina then
			ply.jcms_v1Stamina = 3
		end

		ply.jcms_v1Stamina = math.Clamp( ply.jcms_v1Stamina + FrameTime()*0.7, 0, 3 )
	end)
end