local HitboxService = {
	Public = {},
}

local Receiver: ((Player, string, Model, CFrame) -> ())? = nil

local function IsFinite(Position: Vector3): boolean
	return Position == Position and Position.Magnitude < math.huge
end

local function ReportHit(Player: Player, UUID: string, Victim: Model, ClientRoot: CFrame)
	if typeof(UUID) ~= "string" or typeof(Victim) ~= "Instance" or typeof(ClientRoot) ~= "CFrame" then
		return
	end
	if not Victim:IsA("Model") or not IsFinite(ClientRoot.Position) or not Receiver then
		return
	end
	Receiver(Player, UUID, Victim, ClientRoot)
end

function HitboxService.SetReceiver(Function: (Player, string, Model, CFrame) -> ())
	Receiver = Function
end

HitboxService.Public.ReportHit = ReportHit

return HitboxService
