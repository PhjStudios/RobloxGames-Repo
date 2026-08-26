export type CleanupState = "Active" | "Cleaning" | "Cleaned"

export type CleanupTaskKind = "Connection" | "Instance" | "Callback" | "Thread" | "Container"

export type CleanupCallback = () -> ()

local Log = require(script.Parent.Parent.logging.Log)

type TaskEntry = {
	value: unknown,
	kind: CleanupTaskKind,
}

type ContainerData = {
	logger: Log.Logger,
	label: string,
	state: CleanupState,
	tasks: { TaskEntry },
	failureMessage: string?,
}

local Container = {}
Container.__index = Container

export type Container = typeof(setmetatable({} :: ContainerData, Container))

export type CleanupTask = RBXScriptConnection | Instance | CleanupCallback | thread | Container

export type ErrorCode =
	"INVALID_CONTEXT"
	| "INVALID_LABEL"
	| "INVALID_STATE"
	| "UNSUPPORTED_TASK"
	| "INVALID_NESTED_STATE"
	| "NESTING_CYCLE"
	| "CLEANUP_FAILED"

local Cleanup = {}

local VALID_LABEL_PATTERN = "^[A-Za-z][A-Za-z0-9_.-]*$"
local CONTAINER_REGISTRY = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }

local function formatError(container: ContainerData, event: string, code: ErrorCode, message: string): string
	return container.logger:formatRecord("ERROR", "cleanup", event, message, {
		code = code,
		container = container.label,
		state = container.state,
	})
end

local function fail(container: ContainerData, event: string, code: ErrorCode, message: string)
	error(formatError(container, event, code, message), 0)
end

local function classifyTask(value: unknown): CleanupTaskKind?
	local robloxType = typeof(value)
	if robloxType == "RBXScriptConnection" then
		return "Connection"
	elseif robloxType == "Instance" then
		return "Instance"
	end

	local luaType = type(value)
	if luaType == "function" then
		return "Callback"
	elseif luaType == "thread" then
		return "Thread"
	elseif luaType == "table" and CONTAINER_REGISTRY[value] == true then
		return "Container"
	end

	return nil
end

local function containsContainer(root: Container, target: Container, visited: { [any]: boolean }): boolean
	if root == target then
		return true
	end

	if visited[root] then
		return false
	end
	visited[root] = true

	for _, entry in root.tasks do
		if entry.kind == "Container" and containsContainer(entry.value :: Container, target, visited) then
			return true
		end
	end

	return false
end

local function cleanTask(entry: TaskEntry)
	if entry.kind == "Connection" then
		(entry.value :: RBXScriptConnection):Disconnect()
	elseif entry.kind == "Instance" then
		(entry.value :: Instance):Destroy()
	elseif entry.kind == "Callback" then
		(entry.value :: CleanupCallback)()
	elseif entry.kind == "Thread" then
		local threadValue = entry.value :: thread
		if coroutine.status(threadValue) ~= "dead" then
			task.cancel(threadValue)
		end
	else
		(entry.value :: Container):cleanup()
	end
end

function Container.add(self: Container, cleanupTask: CleanupTask): CleanupTask
	if self.state ~= "Active" then
		fail(self, "add_rejected", "INVALID_STATE", "Cleanup tasks may only be added while the container is Active")
	end

	local taskKind = classifyTask(cleanupTask)
	if taskKind == nil then
		fail(
			self,
			"add_rejected",
			"UNSUPPORTED_TASK",
			`Cleanup task must be a connection, Instance, callback, thread, or Cleanup container; received {typeof(
				cleanupTask
			)}`
		)
	end

	if taskKind == "Container" then
		local nestedContainer = cleanupTask :: Container
		if nestedContainer.state ~= "Active" then
			fail(
				self,
				"add_rejected",
				"INVALID_NESTED_STATE",
				`Nested container '{nestedContainer.label}' must be Active; received {nestedContainer.state}`
			)
		end

		if containsContainer(nestedContainer, self, {}) then
			fail(
				self,
				"add_rejected",
				"NESTING_CYCLE",
				`Adding nested container '{nestedContainer.label}' would create an ownership cycle`
			)
		end
	end

	local entry: TaskEntry = {
		value = cleanupTask,
		kind = taskKind,
	}

	table.insert(self.tasks, entry)
	return cleanupTask
end

function Container.cleanup(self: Container)
	if self.state == "Cleaning" then
		fail(self, "cleanup_rejected", "INVALID_STATE", "Cleanup cannot be invoked re-entrantly")
	elseif self.state == "Cleaned" then
		if self.failureMessage ~= nil then
			error(self.failureMessage, 0)
		end
		return
	end

	self.state = "Cleaning"

	local tasksToClean = self.tasks
	self.tasks = {}
	local failures = {}

	for index = #tasksToClean, 1, -1 do
		local entry = tasksToClean[index]
		local success = pcall(cleanTask, entry)
		if not success then
			table.insert(failures, `task {index} ({entry.kind}/{typeof(entry.value)})`)
		end
	end

	self.state = "Cleaned"

	if #failures > 0 then
		self.failureMessage = formatError(
			self,
			"cleanup_failed",
			"CLEANUP_FAILED",
			`Cleanup completed with {#failures} failed task(s): {table.concat(failures, " | ")}`
		)
		error(self.failureMessage, 0)
	end
end

function Container.getState(self: Container): CleanupState
	return self.state
end

function Container.getTaskCount(self: Container): number
	return #self.tasks
end

function Container.getLabel(self: Container): string
	return self.label
end

function Cleanup.new(logger: Log.Logger, label: string): Container
	if not Log.isLogger(logger) then
		error(
			"[ATD][ERROR][context=unknown][role=Unresolved][placeId=unknown][environment=unknown][subsystem=cleanup][event=construction_rejected][code=INVALID_CONTEXT][container=<unknown>][state=Uninitialized] Cleanup requires a genuine context-bound Log",
			0
		)
	end

	if type(label) ~= "string" or string.match(label, VALID_LABEL_PATTERN) == nil then
		logger:error("cleanup", "construction_rejected", `Cleanup label must match {VALID_LABEL_PATTERN}`, {
			code = "INVALID_LABEL",
			container = "<unknown>",
			state = "Uninitialized",
		})
	end

	local container = setmetatable({
		logger = logger,
		label = label,
		state = "Active",
		tasks = {},
		failureMessage = nil,
	}, Container) :: Container

	CONTAINER_REGISTRY[container] = true
	return container
end

return table.freeze(Cleanup)
