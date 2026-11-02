local Hitbox = {}
Hitbox.__index = Hitbox

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local Lunora = require(Packages.Lunora)

local HitboxController = Lunora.Load("HitboxController")

local Params = OverlapParams.new()

local ReceiverReady = false

local ReachBuffer = 3
local InterpolationWindow = .25
local MaxReachTolerance = 30
local RootHistoryLength = 1

local CatchUpBuffer = .15
local MaxCatchUp = .6

local ReportGraceBuffer = .1
local MaxReportGrace = .5

local ClientStore: { [string]: HitboxObject } = {}
local FilterList: { Instance } = {}

local Resolver: ((HitboxData, Model, CFrame) -> Resolution)? = nil
local SpeedProvider: ((Model) -> number)? = nil

type HitboxObject = typeof(setmetatable({}, Hitbox))

type Resolution = "Hit" | "Blocked" | "Ignore"

type HitboxData = {
	User: Model?,
	Size: Vector3 | number,
	PlaceData: {CFrame: CFrame?, Offset: CFrame?, Linger: boolean?},
	LifeTime: number?,
	IsClient: boolean?,
	[string]: any,
}

type RootSample = {
	Time: number,
	Position: Vector3,
}

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
	if not Victim or not Victim:FindFirstChild("Humanoid") then
		return nil
	end
	return Victim :: Model
end

local function IsInFilter(Victim: Model): boolean
	if #FilterList == 0 then
		return true
	end
	for Index, Folder in FilterList do
		if Victim:IsDescendantOf(Folder) then
			return true
		end
	end
	return false
end

local function GetRootPart(Character: Model?): Part?
	if not Character then
		return nil
	end
	return Character:FindFirstChild("HumanoidRootPart") :: Part?
end

local function GetAllowedSpeed(Character: Model): number
	local Humanoid: Humanoid? = Character:FindFirstChildOfClass("Humanoid")
	local WalkSpeed = if Humanoid then Humanoid.WalkSpeed else 0
	local ExtraSpeed = if SpeedProvider then SpeedProvider(Character) else 0
	return WalkSpeed + ExtraSpeed
end

local function GetDistanceToSegment(Point: Vector3, From: Vector3, To: Vector3): number
	local Segment = To - From
	local LengthSquared = Segment:Dot(Segment)
	if LengthSquared == 0 then
		return (Point - From).Magnitude
	end
	local Progress = math.clamp((Point - From):Dot(Segment) / LengthSquared, 0, 1)
	return (Point - (From + Segment * Progress)).Magnitude
end

local function IsInReach(MainCFrame: CFrame, Size: Vector3 | number, Point: Vector3, Tolerance: number): boolean
	local LocalPoint = MainCFrame:PointToObjectSpace(Point)
	if typeof(Size) == "number" then
		return LocalPoint.Magnitude <= Size * .5 + Tolerance
	end
	local HalfSize = Size * .5 + Vector3.one * Tolerance
	return math.abs(LocalPoint.X) <= HalfSize.X and math.abs(LocalPoint.Y) <= HalfSize.Y and math.abs(LocalPoint.Z) <= HalfSize.Z
end

local function EnsureReceiver()
	if ReceiverReady then
		return
	end
	local HitboxService = Lunora.LoadSelf("HitboxService")
	if not HitboxService then
		return
	end
	ReceiverReady = true
	HitboxService.SetReceiver(Hitbox.ReportHit)
end

function Hitbox:GetCFrameFrom(RootCFrame: CFrame?): CFrame?
	local Offset: CFrame? = self.PlaceData.Offset
	if RootCFrame and Offset then
		return RootCFrame * Offset
	end
	return self.CFrame
end

function Hitbox:GetCFrame(): CFrame?
	local RootPart = GetRootPart(self.User)
	return self:GetCFrameFrom(RootPart and RootPart.CFrame)
end

function Hitbox:RecordRoot()
	local RootPart = GetRootPart(self.User)
	if not RootPart then
		return
	end
	local Now = os.clock()
	local History: { RootSample } = self.RootHistory
	table.insert(History, { Time = Now, Position = RootPart.Position })
	while History[1] and Now - History[1].Time > RootHistoryLength do
		table.remove(History, 1)
	end
end

function Hitbox:GetRecentTravel(Window: number): number
	local RootPart = GetRootPart(self.User)
	if not RootPart then
		return 0
	end
	local Now = os.clock()
	local Travel = 0
	for Index, Sample: RootSample in self.RootHistory do
		if Now - Sample.Time > Window then
			continue
		end
		Travel = math.max(Travel, (Sample.Position - RootPart.Position).Magnitude)
	end
	return Travel
end

function Hitbox:TryHit(Victim: Model, MainCFrame: CFrame)
	if not self.UUID or table.find(self.HitVictims, Victim) then
		return
	end

	local Result: Resolution = if Resolver then Resolver(self.Data, Victim, MainCFrame) else "Hit"
	if Result == "Ignore" then
		return
	end
	table.insert(self.HitVictims, Victim)

	local Callback = if Result == "Blocked" then self.BlockedFunc else self.HitFunc
	if not Callback then
		return
	end
	task.defer(Callback, Victim)
end

function Hitbox:ConfirmReport(Victim: Model, VictimRoot: Part, ClientRoot: CFrame, Window: number)
	if not VictimRoot:IsDescendantOf(workspace) then
		return
	end

	local MainCFrame = self:GetCFrameFrom(ClientRoot)
	if not MainCFrame then
		return
	end

	local VictimTolerance = math.min(ReachBuffer + VictimRoot.AssemblyLinearVelocity.Magnitude * Window, MaxReachTolerance)
	if not IsInReach(MainCFrame, self.Size, VictimRoot.Position, VictimTolerance) then
		return
	end

	self:TryHit(Victim, MainCFrame)
end

function Hitbox:AwaitCatchUp(Victim: Model, ClientRoot: CFrame, Duration: number, OnCaughtUp: () -> ())
	if self.PendingReports[Victim] then
		return
	end

	local Deadline = os.clock() + Duration
	local LastPosition: Vector3? = nil
	local Connection: RBXScriptConnection

	local function StopWaiting()
		Connection:Disconnect()
		self.PendingReports[Victim] = nil
	end

	Connection = RunService.Heartbeat:Connect(function()
		local RootPart = GetRootPart(self.User)
		if not RootPart or os.clock() > Deadline then
			StopWaiting()
			return
		end
		local Position = RootPart.Position
		local Distance = GetDistanceToSegment(ClientRoot.Position, LastPosition or Position, Position)
		LastPosition = Position
		if Distance > ReachBuffer then
			return
		end
		StopWaiting()
		OnCaughtUp()
	end)

	self.PendingReports[Victim] = Connection
end

function Hitbox:DetectOnServer(LifeTime: number?)
	self.Connection = RunService.Heartbeat:Connect(function()
		local MainCFrame = self:GetCFrame()
		if not MainCFrame then
			return
		end

		local HitParts = GetParts(MainCFrame, self.Size)
		if not HitParts then
			return
		end

		HitboxController.Visualize({
			UUID = self.UUID,
			Size = self.Size,
			CFrame = MainCFrame,
		}):Fire()

		for Index, HitPart in HitParts do
			local Victim = GetVictim(HitPart)
			if not Victim then
				continue
			end
			self:TryHit(Victim, MainCFrame)
		end
	end)

	if not LifeTime then
		return
	end

	task.delay(LifeTime, function()
		self:Destroy()
	end)
end

function Hitbox:DetectOnClient(LifeTime: number?)
	local ClientUser: Player = self.ClientUser
	local PlaceData = self.PlaceData

	EnsureReceiver()

	self.RootHistory = {}
	self.PendingReports = {} :: { [Model]: RBXScriptConnection }
	self.Connection = RunService.Heartbeat:Connect(function()
		self:RecordRoot()
	end)

	ClientStore[self.UUID] = self

	HitboxController.Detect({
		UUID = self.UUID,
		Size = self.Size,
		PlaceData = {
			CFrame = self.CFrame,
			Offset = PlaceData.Offset,
			Linger = PlaceData.Linger,
		},
		LifeTime = LifeTime,
	}):Fire(ClientUser)

	if not LifeTime then
		return
	end

	local ReportGrace = math.min(ClientUser:GetNetworkPing() + ReportGraceBuffer, MaxReportGrace) + MaxCatchUp
	task.delay(LifeTime + ReportGrace, function()
		self:Destroy()
	end)
end

function Hitbox.new(Data: HitboxData)
	local User: Model? = Data.User

	local self = setmetatable({}, Hitbox)
	self.Data = Data
	self.User = User
	self.PlaceData = Data.PlaceData
	self.CFrame = Data.PlaceData.CFrame
	self.Size = Data.Size
	self.HitVictims = {}
	self.UUID = HttpService:GenerateGUID()
	self.ClientUser = User and Players:GetPlayerFromCharacter(User)

	if self.ClientUser and Data.IsClient then
		self:DetectOnClient(Data.LifeTime)
		return self
	end
	self:DetectOnServer(Data.LifeTime)

	return self
end

function Hitbox.SetResolver(Function: (HitboxData, Model, CFrame) -> Resolution)
	Resolver = Function
end

function Hitbox.SetFilter(Folders: { Instance })
	FilterList = Folders
	Params.FilterType = Enum.RaycastFilterType.Include
	Params.FilterDescendantsInstances = Folders
end

function Hitbox.SetSpeedProvider(Function: (Model) -> number)
	SpeedProvider = Function
end

function Hitbox.ReportHit(Player: Player, UUID: string, Victim: Model, ClientRoot: CFrame)
	local Target = ClientStore[UUID]
	if not Target or Target.ClientUser ~= Player then
		return
	end

	if not IsInFilter(Victim) or not Victim:FindFirstChild("Humanoid") then
		return
	end

	local UserRoot = GetRootPart(Target.User)
	local VictimRoot = GetRootPart(Victim)
	if not UserRoot or not VictimRoot then
		return
	end

	local Window = Player:GetNetworkPing() + InterpolationWindow
	local AllowedTravel = math.max(Target:GetRecentTravel(Window), GetAllowedSpeed(Target.User) * Window)

	local Drift = (ClientRoot.Position - UserRoot.Position).Magnitude
	local AllowedDrift = math.min(ReachBuffer + AllowedTravel, MaxReachTolerance)
	if Drift <= AllowedDrift then
		Target:ConfirmReport(Victim, VictimRoot, ClientRoot, Window)
		return
	end

	Target:AwaitCatchUp(Victim, ClientRoot, math.min(Window + CatchUpBuffer, MaxCatchUp), function()
		Target:ConfirmReport(Victim, VictimRoot, ClientRoot, Window)
	end)
end

function Hitbox:OnHit(Function: (Model) -> ())
	self.HitFunc = Function
end

function Hitbox:OnBlocked(Function: (Model) -> ())
	self.BlockedFunc = Function
end

function Hitbox:ResetVictims()
	table.clear(self.HitVictims)
end

function Hitbox:Destroy()
	if not self.UUID then
		return
	end

	if self.Connection then
		self.Connection:Disconnect()
	end

	for Index, Pending: RBXScriptConnection in self.PendingReports or {} do
		Pending:Disconnect()
	end

	ClientStore[self.UUID] = nil
	HitboxController.Destroy(self.UUID):Fire()

	table.clear(self)
end

return Hitbox
