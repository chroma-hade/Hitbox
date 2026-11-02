local HitboxService = {
	Public = {},
}

local Receiver: ((Player, string, Model, CFrame) -> ())? = nil

local function ReportHit(Player: Player, UUID: string, Victim: Model, ClientRoot: CFrame)
	if typeof(UUID) ~= "string" or typeof(Victim) ~= "Instance" or typeof(ClientRoot) ~= "CFrame" then
		return
	end
	if not Victim:IsA("Model") or not Receiver then
		return
	end
	Receiver(Player, UUID, Victim, ClientRoot)
end

function HitboxService.SetReceiver(Function: (Player, string, Model, CFrame) -> ())
	Receiver = Function
end

HitboxService.Public.ReportHit = ReportHit

return HitboxService
