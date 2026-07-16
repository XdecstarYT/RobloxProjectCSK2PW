--!strict
--[[
	Config/init.luau
	Aggregates every configuration table behind one require. Because this folder
	has an init.luau, `require(ReplicatedStorage.Nexus.Config)` returns this
	bundle, while `require(...Config.Buildings)` still works for direct access.
]]

local Config = {
	Balance = require(script.Balance),
	Resources = require(script.Resources),
	Buildings = require(script.Buildings),
	Technologies = require(script.Technologies),
	Governments = require(script.Governments),
	Laws = require(script.Laws),
}

return Config
