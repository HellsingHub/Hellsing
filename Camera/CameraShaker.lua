local CameraShaker = {}
CameraShaker.__index = CameraShaker

local profileBegin = debug.profilebegin
local profileEnd = debug.profileend
local profileTag = "CameraShakerUpdate"

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RAD = math.rad
local v3Zero = V3()

local CameraShakeInstance = loadstring(game:HttpGet("https://raw.githubusercontent.com/LanezHub/Hellsing/refs/heads/ModuleScript/Camera/CameraShakeInstance.lua"))()
local CameraShakeState = CameraShakeInstance.CameraShakeState

local defaultPosInfluence = V3(0.15, 0.15, 0.15)
local defaultRotInfluence = V3(1, 1, 1)


CameraShaker.CameraShakeInstance = CameraShakeInstance
CameraShaker.Presets = (function()
	local CameraShakePresets = {
		Bump = function()
			local c = CameraShakeInstance.new(2.5, 4, 0.1, 0.75)
			c.PositionInfluence = Vector3.new(0.15, 0.15, 0.15)
			c.RotationInfluence = Vector3.new(1, 1, 1)
			return c
		end;

		Explosion = function()
			local c = CameraShakeInstance.new(5, 10, 0, 1.5)
			c.PositionInfluence = Vector3.new(0.25, 0.25, 0.25)
			c.RotationInfluence = Vector3.new(4, 1, 1)
			return c
		end;

		Earthquake = function()
			local c = CameraShakeInstance.new(0.6, 3.5, 2, 10)
			c.PositionInfluence = Vector3.new(0.25, 0.25, 0.25)
			c.RotationInfluence = Vector3.new(1, 1, 4)
			return c
		end;

		BadTrip = function()
			local c = CameraShakeInstance.new(10, 0.15, 5, 10)
			c.PositionInfluence = Vector3.new(0, 0, 0.15)
			c.RotationInfluence = Vector3.new(2, 1, 4)
			return c
		end;

		HandheldCamera = function()
			local c = CameraShakeInstance.new(1, 0.25, 5, 10)
			c.PositionInfluence = Vector3.new(0, 0, 0)
			c.RotationInfluence = Vector3.new(1, 0.5, 0.5)
			return c
		end;

		Vibration = function()
			local c = CameraShakeInstance.new(0.4, 20, 2, 2)
			c.PositionInfluence = Vector3.new(0, 0.15, 0)
			c.RotationInfluence = Vector3.new(1.25, 0, 4)
			return c
		end;

		RoughDriving = function()
			local c = CameraShakeInstance.new(1, 2, 1, 1)
			c.PositionInfluence = Vector3.new(0, 0, 0)
			c.RotationInfluence = Vector3.new(1, 1, 1)
			return c
		end;


	}

	return setmetatable({}, {
		__index = function(t, i)
			local f = CameraShakePresets[i]
			if (type(f) == "function") then
				return f()
			end
			error("No preset found with index \"" .. i .. "\"")
		end;
	})
end)


function CameraShaker.new(renderPriority, callback)
	
	assert(type(renderPriority) == "number", "RenderPriority must be a number (e.g.: Enum.RenderPriority.Camera.Value)")
	assert(type(callback) == "function", "Callback must be a function")
	
	local self = setmetatable({
		_running = false;
		_renderName = "CameraShaker";
		_renderPriority = renderPriority;
		_posAddShake = v3Zero;
		_rotAddShake = v3Zero;
		_camShakeInstances = {};
		_removeInstances = {};
		_callback = callback;
	}, CameraShaker)
	
	return self
	
end


function CameraShaker:Start()
	if (self._running) then return end
	self._running = true
	local callback = self._callback
	game:GetService("RunService"):BindToRenderStep(self._renderName, self._renderPriority, function(dt)
		profileBegin(profileTag)
		local cf = self:Update(dt)
		profileEnd()
		callback(cf)
	end)
end


function CameraShaker:Stop()
	if (not self._running) then return end
	game:GetService("RunService"):UnbindFromRenderStep(self._renderName)
	self._running = false
end


function CameraShaker:Update(dt)
	
	local posAddShake = v3Zero
	local rotAddShake = v3Zero
	
	local instances = self._camShakeInstances
	
	-- Update all instances:
	for i = 1,#instances do
		
		local c = instances[i]
		
		local state = c:GetState()
		
		if (state == CameraShakeState.Inactive and c.DeleteOnInactive) then
			self._removeInstances[#self._removeInstances + 1] = i
		elseif (state ~= CameraShakeState.Inactive) then
			posAddShake = posAddShake + (c:UpdateShake(dt) * c.PositionInfluence)
			rotAddShake = rotAddShake + (c:UpdateShake(dt) * c.RotationInfluence)
		end
		
	end
	
	-- Remove dead instances:
	for i = #self._removeInstances,1,-1 do
		local instIndex = self._removeInstances[i]
		table.remove(instances, instIndex)
		self._removeInstances[i] = nil
	end
	
	return CF(posAddShake) *
			ANG(0, RAD(rotAddShake.Y), 0) *
			ANG(RAD(rotAddShake.X), 0, RAD(rotAddShake.Z))
	
end


function CameraShaker:Shake(shakeInstance)
	assert(type(shakeInstance) == "table" and shakeInstance._camShakeInstance , "ShakeInstance must be of type CameraShakeInstance")
	self._camShakeInstances[#self._camShakeInstances + 1] = shakeInstance
	return shakeInstance
end


function CameraShaker:ShakeSustain(shakeInstance)
	assert(type(shakeInstance) == "table" and shakeInstance._camShakeInstance , "ShakeInstance must be of type CameraShakeInstance")
	self._camShakeInstances[#self._camShakeInstances + 1] = shakeInstance
	shakeInstance:StartFadeIn(shakeInstance.fadeInDuration)
	return shakeInstance
end


function CameraShaker:ShakeOnce(magnitude, roughness, fadeInTime, fadeOutTime, posInfluence, rotInfluence)
	local shakeInstance = CameraShakeInstance.new(magnitude, roughness, fadeInTime, fadeOutTime)
	shakeInstance.PositionInfluence = (typeof(posInfluence) == "Vector3" and posInfluence or defaultPosInfluence)
	shakeInstance.RotationInfluence = (typeof(rotInfluence) == "Vector3" and rotInfluence or defaultRotInfluence)
	self._camShakeInstances[#self._camShakeInstances + 1] = shakeInstance
	return shakeInstance
end


function CameraShaker:StartShake(magnitude, roughness, fadeInTime, posInfluence, rotInfluence)
	local shakeInstance = CameraShakeInstance.new(magnitude, roughness, fadeInTime)
	shakeInstance.PositionInfluence = (typeof(posInfluence) == "Vector3" and posInfluence or defaultPosInfluence)
	shakeInstance.RotationInfluence = (typeof(rotInfluence) == "Vector3" and rotInfluence or defaultRotInfluence)
	shakeInstance:StartFadeIn(fadeInTime)
	self._camShakeInstances[#self._camShakeInstances + 1] = shakeInstance
	return shakeInstance
end


return CameraShaker