# Hitbox

Hitboxes for [Lunora](https://github.com/chroma-hade/Lunora)! Run them on the server, or on the attacker's client with the server checking every hit.

Server hitboxes are the plain kind: the server looks for overlaps every frame. Client hitboxes let the attacker's own screen decide what got hit, so hits feel instant, and the server checks each report so nobody lands a punch from across the map. Set `IsClient = true` on a player's hitbox to get the client kind. NPCs always run on the server.

## Getting it

You need Lunora at `ReplicatedStorage.Packages.Lunora`.

Grab `Hitbox.rbxm` from the [releases page](https://github.com/chroma-hade/Hitbox/releases) and put it in `ReplicatedStorage.Packages` too.

If you use Wally, add both to your `wally.toml`:

```toml
[dependencies]
Lunora = "chroma-hade/lunora@1.0.0"
Hitbox = "chroma-hade/hitbox@1.0.0"
```

## Setting it up

Hitbox comes with a service and a controller. Hand them to Lunora next to your own modules.

```lua
-- server
Lunora.AddModules(ReplicatedStorage.Packages.Hitbox.Server)
Lunora.AddModules(ServerStorage.Services)
Lunora.Start()
```

```lua
-- client
Lunora.AddModules(ReplicatedStorage.Packages.Hitbox.Client)
Lunora.AddModules(script.Parent.Controllers)
Lunora.Start()
```

With Wally, `Packages.Hitbox` is just a link, so the folders sit in `_Index` instead:

```lua
local HitboxFolder = ReplicatedStorage.Packages._Index["chroma-hade_hitbox@1.0.0"].hitbox
Lunora.AddModules(HitboxFolder.Server)
```

## Using it

```lua
local Hitbox = require(ReplicatedStorage.Packages.Hitbox)

local Punch = Hitbox.new({
    User = Character,
    Size = Vector3.new(6, 5, 6),
    PlaceData = { Offset = CFrame.new(0, 0, -3), Linger = true },
    LifeTime = 0.1,
    IsClient = true,
})

Punch:OnHit(function(Victim)
    Victim.Humanoid:TakeDamage(10)
end)
```

Each victim gets hit once per hitbox. Anything with a `Humanoid` counts as a victim.

- `Size` is a `Vector3` for a box, or a number for a ball (that's the diameter).
- `PlaceData.Offset` places it in front of the user's `HumanoidRootPart`, and `Linger` keeps it following them. Use `PlaceData.CFrame` instead for a fixed spot.
- Leave out `LifeTime` and it stays until you call `Punch:Destroy()`.

## Your rules

Hitbox doesn't know what blocking or ragdolls mean in your game, so you tell it. Set these once, in some module's `Init`.

```lua
Hitbox.SetResolver(function(Data, Victim, HitboxCFrame)
    if Victim:GetAttribute("Blocking") and Data.Blockable then
        return "Blocked"
    end
    return "Hit"
end)

Hitbox.SetFilter({ workspace.Characters })
```

`Data` is the exact table you passed to `Hitbox.new`, so you can stick your own fields in there, like `Blockable` above. Return `"Hit"`, `"Blocked"` or `"Ignore"`. `"Blocked"` runs `:OnBlocked` instead of `:OnHit`, and `"Ignore"` lets the victim get hit later in the same swing.

`SetFilter` limits hitboxes to those folders. Leave it out and everything counts.

## How the server checks

The client tells the server who it hit and where the attacker was standing. The server only believes that spot if the attacker could have gotten there in time, based on their `WalkSpeed` and the ping. Standing still, that's barely a few studs!

If your game moves characters some other way, like a dash, tell Hitbox how fast:

```lua
Hitbox.SetSpeedProvider(function(Character)
    return Character:GetAttribute("DashSpeed") or 0
end)
```

Reports that still don't add up wait a moment to see if the server catches up, then get thrown out☆

## Seeing them

Set a `VisualHitbox` attribute to `true` on `ReplicatedStorage`. Client hitboxes show up blue, server ones red.

## Everything

| | |
|---|---|
| `Hitbox.new(Data)` | Makes a hitbox and starts it |
| `hitbox:OnHit(Function)` | Runs for each victim that got hit |
| `hitbox:OnBlocked(Function)` | Runs for each victim your resolver blocked |
| `hitbox:Destroy()` | Stops it early |
| `Hitbox.SetResolver(Function)` | Decides hit, blocked or ignored |
| `Hitbox.SetFilter(Folders)` | Only check inside these folders |
| `Hitbox.SetSpeedProvider(Function)` | Extra speed a character can have, on top of `WalkSpeed` |

## License

MIT, so go wild☆ Just keep the license file around.
