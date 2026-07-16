--!strict
--[[
	UI/Create.luau
	A tiny declarative helper for building Instance trees without the noise of
	imperative property assignment. Inspired by common Roblox UI idioms but kept
	dependency-free.

	Usage:
		Create("TextButton", {
			Text = "Build",
			Size = UDim2.fromOffset(120, 40),
			[Create.Event] = { Activated = function() ... end },
			[Create.Children] = { Create("UICorner", { CornerRadius = ... }) },
		})
]]

local Create = {}

-- Sentinel keys used inside the property table.
local CHILDREN = newproxy(false)
local EVENT = newproxy(false)

Create.Children = CHILDREN
Create.Event = EVENT

function Create.build(className: string, props: { [any]: any }?): Instance
	local instance = Instance.new(className)
	if props then
		local children = props[CHILDREN]
		local events = props[EVENT]

		for key, value in props do
			if key ~= CHILDREN and key ~= EVENT then
				(instance :: any)[key] = value
			end
		end

		if events then
			for eventName, handler in events do
				(instance :: any)[eventName]:Connect(handler)
			end
		end
		if children then
			for _, child in children do
				child.Parent = instance
			end
		end
	end
	return instance
end

-- Allow calling the module table itself: Create("Frame", { ... }).
local callable = setmetatable(Create, {
	__call = function(_, className: string, props: { [any]: any }?): Instance
		return Create.build(className, props)
	end,
})

-- The `any` cast lets callers use both `Create("Frame")` and `Create.Children`.
return (callable :: any) :: (((className: string, props: { [any]: any }?) -> Instance) & typeof(Create))
