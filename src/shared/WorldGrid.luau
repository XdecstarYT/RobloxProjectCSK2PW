--!strict
--[[
	WorldGrid.luau
	The mapping between the logical build grid (integer tiles the server stores)
	and world-space studs (what the client renders and clicks). Centralising it
	means placement previews, permanent buildings and click-picking all agree on
	exactly where a tile is.

	The grid is centred on the world origin. Tile (0,0) is the corner with the
	most negative X/Z; the ground surface sits at Y = 0.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Nexus.Constants)

local WorldGrid = {}

local STUDS = Constants.STUDS_PER_TILE
local SPAN = Constants.GRID_SIZE * STUDS
local HALF = SPAN / 2

WorldGrid.STUDS = STUDS
WorldGrid.SPAN = SPAN
WorldGrid.GROUND_Y = 0

--- World-space centre of a footprint whose corner tile is (x, z) and whose
--- oriented size is w x h tiles.
function WorldGrid.footprintCenter(x: number, z: number, w: number, h: number): Vector3
	local wx = -HALF + (x + w / 2) * STUDS
	local wz = -HALF + (z + h / 2) * STUDS
	return Vector3.new(wx, WorldGrid.GROUND_Y, wz)
end

--- Convert a world position to the tile it falls in, clamped to the grid.
function WorldGrid.worldToTile(position: Vector3): (number, number)
	local x = math.floor((position.X + HALF) / STUDS)
	local z = math.floor((position.Z + HALF) / STUDS)
	x = math.clamp(x, 0, Constants.GRID_SIZE - 1)
	z = math.clamp(z, 0, Constants.GRID_SIZE - 1)
	return x, z
end

return WorldGrid
