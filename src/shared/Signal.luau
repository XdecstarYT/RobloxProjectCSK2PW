--!strict
--[[
	Signal.luau
	A minimal, original event/observer primitive.

	Roblox's BindableEvents copy arguments and cannot pass some types across the
	boundary; a plain-table signal is faster and lossless for in-VM messaging.
	Handlers fire synchronously in subscription order under a pcall so one bad
	listener cannot break the rest.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

type Handler = {
	fn: (...any) -> (),
	connected: boolean,
	once: boolean,
}

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({
		_handlers = {} :: { Handler },
	}, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local handler: Handler = { fn = fn, connected = true, once = false }
	table.insert(self._handlers, handler)

	local connection = {}
	connection.Connected = true
	function connection:Disconnect()
		self.Connected = false
		handler.connected = false
	end
	return connection :: any
end

function Signal:Once(fn: (...any) -> ()): Connection
	local handler: Handler = { fn = fn, connected = true, once = true }
	table.insert(self._handlers, handler)

	local connection = {}
	connection.Connected = true
	function connection:Disconnect()
		self.Connected = false
		handler.connected = false
	end
	return connection :: any
end

function Signal:Fire(...: any)
	-- Iterate over a snapshot so handlers may connect/disconnect during firing.
	local snapshot = table.clone(self._handlers)
	for _, handler in snapshot do
		if not handler.connected then
			continue
		end
		if handler.once then
			handler.connected = false
		end
		local ok, err = pcall(handler.fn, ...)
		if not ok then
			warn(("[Signal] handler error: %s"):format(tostring(err)))
		end
	end

	-- Compact out dead handlers so the list does not grow unbounded.
	for i = #self._handlers, 1, -1 do
		if not self._handlers[i].connected then
			table.remove(self._handlers, i)
		end
	end
end

function Signal:DisconnectAll()
	for _, handler in self._handlers do
		handler.connected = false
	end
	table.clear(self._handlers)
end

function Signal:Destroy()
	self:DisconnectAll()
end

return Signal
