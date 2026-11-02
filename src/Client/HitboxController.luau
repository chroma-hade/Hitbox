local HitboxController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local Lunora = require(Packages.Lunora)

local LocalPlayer = Players.LocalPlayer

local HitboxService = Lunora.Load("HitboxService")

local Params = OverlapParams.new()

local VisualTransparency = .5

local ClientColor = Color3.new(0, 0, 1)
local ServerColor = Color3.new(1, 0, 0)

local VisualizeStore: { [string]: Part } = {}
local PlaceStore: { [string]: CFrame } = {}
local ConnectionStore: { [string]: RBXScriptConnection } = {}

type PlaceData = {
	CFrame: CFrame?,
	Offset: CFrame?,
	Linger: boolean?
}

type VisualizeData = {
	UUID: string,
	Size: Vector3 | number,
	CFrame: CFrame,
}

type DetectData = {
	UUID: string,
	Size: Vector3 | number,
	PlaceData: PlaceData,
	LifeTime: number?,
}

local function GetRootCFrame(): CFrame?
	local Character = LocalPlayer.Character
	if not Character then
		return nil
	end
	local RootPart: Part = Character:FindFirstChild("HumanoidRootPart") :: Part
	if not RootPart then
		return nil
	end
	return RootPart.CFrame
end

local function GetPlaceCFrame(UUID: string, PlaceData: PlaceData): CFrame?
	if PlaceData.CFrame then
		return PlaceData.CFrame
	end

	if not PlaceData.Offset then
		return nil
	end

	if not PlaceData.Linger and PlaceStore[UUID] then
		return PlaceStore[UUID]
	end

	local RootCFrame = GetRootCFrame()
	if not RootCFrame then
		return nil
	end

	local PlaceCFrame = RootCFrame * PlaceData.Offset
	if not PlaceData.Linger then
		PlaceStore[UUID] = PlaceCFrame
	end
	return PlaceCFrame
end

local function DrawHitbox(UUID: string, Size: Vector3 | number, MainCFrame: CFrame, Color: Color3)
	if not ReplicatedStorage:GetAttribute("VisualHitbox") then
		return
	end

	local MainPart = VisualizeStore[UUID]
	if not MainPart then
		MainPart = Instance.new("Part")
		MainPart.Massless = true
		MainPart.Anchored = true
		MainPart.CanCollide = false
		MainPart.CanQuery = false
		MainPart.CanTouch = false
		MainPart.Transparency = VisualTransparency
		MainPart.CastShadow = false
		MainPart.Material = Enum.Material.SmoothPlastic
		MainPart.Parent = workspace.CurrentCamera
		VisualizeStore[UUID] = MainPart
	end

	if typeof(Size) == "Vector3" then
		MainPart.Size = Size
		MainPart.Shape = Enum.PartType.Block
	elseif typeof(Size) == "number" then
		MainPart.Size = Vector3.new(Size, Size, Size)
		MainPart.Shape = Enum.PartType.Ball
	end

	MainPart.CFrame = MainCFrame

	if MainPart.Color ~= Color then
		MainPart.Color = Color
	end
end

local function GetParts(MainCFrame: CFrame, Size: Vector3 | number): { BasePart }?
	if typeof(Size) == "Vector3" then
		return workspace:GetPartBoundsInBox(MainCFrame, Size, Params)
	elseif typeof(Size) == "number" then
		return workspace:GetPartBoundsInRadius(MainCFrame.Position, Size * .5, Params)
	end
	return nil
end

local function GetVictim(HitPart: BasePart): Model?
	local Victim = HitPart.Parent
	if not Victim or Victim == LocalPlayer.Character or not Victim:FindFirstChild("Humanoid") then
		return nil
	end
	return Victim :: Model
end

local function DetectHits(Data: DetectData, Reported: { Model })
	local MainCFrame = GetPlaceCFrame(Data.UUID, Data.PlaceData)
	if not MainCFrame then
		return
	end

	DrawHitbox(Data.UUID, Data.Size, MainCFrame, ClientColor)

	local HitParts = GetParts(MainCFrame, Data.Size)
	local RootCFrame = GetRootCFrame()
	if not HitParts or not RootCFrame then
		return
	end

	for Index, HitPart in HitParts do
		local Victim = GetVictim(HitPart)
		if not Victim or table.find(Reported, Victim) then
			continue
		end
		table.insert(Reported, Victim)
		HitboxService.ReportHit(Data.UUID, Victim, RootCFrame):Fire()
	end
end

function HitboxController.Visualize(Data: VisualizeData)
	DrawHitbox(Data.UUID, Data.Size, Data.CFrame, ServerColor)
end

function HitboxController.Detect(Data: DetectData)
	local Reported: { Model } = {}
	ConnectionStore[Data.UUID] = RunService.Heartbeat:Connect(function()
		DetectHits(Data, Reported)
	end)

	if not Data.LifeTime then
		return
	end

	task.delay(Data.LifeTime, HitboxController.Destroy, Data.UUID)
end

function HitboxController.Destroy(UUID: string)
	local Connection = ConnectionStore[UUID]
	if Connection then
		Connection:Disconnect()
		ConnectionStore[UUID] = nil
	end

	PlaceStore[UUID] = nil

	local MainPart = VisualizeStore[UUID]
	if not MainPart then
		return
	end
	MainPart:Destroy()

	VisualizeStore[UUID] = nil
end

return HitboxController
