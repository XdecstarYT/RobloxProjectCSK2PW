--!strict
--[[
	Services/NotificationService.luau
	Server-authored, transient messages to a player's HUD: "Not enough
	materials", "Election won", "Power shortage". Purely presentational — no
	state lives here — but centralising it keeps a consistent shape and severity
	vocabulary across every service.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)

export type Severity = "info" | "success" | "warning" | "error"

local NotificationService = {
	Name = "NotificationService",
}

function NotificationService:Send(player: Player, severity: Severity, title: string, body: string?)
	Net.fireClient(player, NetRoutes.NOTIFY, {
		severity = severity,
		title = title,
		body = body,
		at = os.time(),
	})
end

function NotificationService:Broadcast(severity: Severity, title: string, body: string?)
	Net.fireAllClients(NetRoutes.NOTIFY, {
		severity = severity,
		title = title,
		body = body,
		at = os.time(),
	})
end

return NotificationService
