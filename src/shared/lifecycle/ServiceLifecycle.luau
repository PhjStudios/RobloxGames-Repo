export type LifecycleState =
	"Registering"
	| "Initializing"
	| "Initialized"
	| "Starting"
	| "Started"
	| "ShuttingDown"
	| "Shutdown"
	| "Failed"

export type ErrorCode =
	"INVALID_CONTEXT"
	| "INVALID_STATE"
	| "INVALID_SERVICE"
	| "INVALID_SERVICE_NAME"
	| "DUPLICATE_SERVICE"
	| "INVALID_DEPENDENCIES"
	| "DUPLICATE_DEPENDENCY"
	| "INVALID_METHOD"
	| "MISSING_DEPENDENCY"
	| "DEPENDENCY_CYCLE"
	| "INITIALIZE_FAILED"
	| "START_FAILED"
	| "SHUTDOWN_FAILED"

export type LifecycleMethod = () -> ()

export type ServiceDefinition = {
	name: string,
	dependencies: { string }?,
	initialize: LifecycleMethod?,
	start: LifecycleMethod?,
	shutdown: LifecycleMethod?,
}

local Log = require(script.Parent.Parent.logging.Log)

type StoredService = {
	name: string,
	dependencies: { string },
	initialize: LifecycleMethod?,
	start: LifecycleMethod?,
	shutdown: LifecycleMethod?,
}

type RunnerData = {
	logger: Log.Logger,
	state: LifecycleState,
	registeredServices: { StoredService },
	servicesByName: { [string]: StoredService },
	serviceOrder: { StoredService }?,
}

local Runner = {}
Runner.__index = Runner

export type Runner = typeof(setmetatable({} :: RunnerData, Runner))

local ServiceLifecycle = {}

local VALID_SERVICE_NAME_PATTERN = "^[A-Za-z][A-Za-z0-9_.-]*$"
local RUNNER_SERVICE_NAME = "<runner>"

local function fail(runner: RunnerData, event: string, code: ErrorCode, serviceName: string, message: string)
	runner.logger:error("lifecycle", event, message, {
		code = code,
		service = serviceName,
		state = runner.state,
	})
end

local function requireState(runner: RunnerData, expectedState: LifecycleState, operation: string)
	if runner.state ~= expectedState then
		fail(
			runner,
			"transition_rejected",
			"INVALID_STATE",
			RUNNER_SERVICE_NAME,
			`Operation '{operation}' requires state '{expectedState}', but the runner is '{runner.state}'`
		)
	end
end

local function validateServiceName(runner: RunnerData, serviceName: unknown, fieldDescription: string): string
	if type(serviceName) ~= "string" or string.match(serviceName, VALID_SERVICE_NAME_PATTERN) == nil then
		fail(
			runner,
			"registration_rejected",
			"INVALID_SERVICE_NAME",
			RUNNER_SERVICE_NAME,
			`{fieldDescription} must match {VALID_SERVICE_NAME_PATTERN}`
		)
	end

	return serviceName
end

local function validateDependencies(runner: RunnerData, serviceName: string, dependenciesValue: unknown): { string }
	if dependenciesValue == nil then
		return {}
	end

	if type(dependenciesValue) ~= "table" then
		fail(
			runner,
			"registration_rejected",
			"INVALID_DEPENDENCIES",
			serviceName,
			"Dependencies must be a contiguous array of service names"
		)
	end

	local dependencies = dependenciesValue :: { [any]: any }
	local dependencyCount = #dependencies
	local keyCount = 0

	for key in dependencies do
		keyCount += 1
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > dependencyCount then
			fail(
				runner,
				"registration_rejected",
				"INVALID_DEPENDENCIES",
				serviceName,
				"Dependencies must use contiguous integer keys starting at one"
			)
		end
	end

	if keyCount ~= dependencyCount then
		fail(
			runner,
			"registration_rejected",
			"INVALID_DEPENDENCIES",
			serviceName,
			"Dependencies must not contain holes"
		)
	end

	local validatedDependencies = {}
	local seenDependencies: { [string]: boolean } = {}

	for index = 1, dependencyCount do
		local dependencyName =
			validateServiceName(runner, dependencies[index], `Dependency {index} for service '{serviceName}'`)

		if seenDependencies[dependencyName] then
			fail(
				runner,
				"registration_rejected",
				"DUPLICATE_DEPENDENCY",
				serviceName,
				`Dependency '{dependencyName}' is listed more than once`
			)
		end

		seenDependencies[dependencyName] = true
		table.insert(validatedDependencies, dependencyName)
	end

	return table.freeze(validatedDependencies)
end

local function validateMethod(
	runner: RunnerData,
	serviceName: string,
	methodName: string,
	methodValue: unknown
): LifecycleMethod?
	if methodValue ~= nil and type(methodValue) ~= "function" then
		fail(
			runner,
			"registration_rejected",
			"INVALID_METHOD",
			serviceName,
			`Lifecycle method '{methodName}' must be a function or nil; received {typeof(methodValue)}`
		)
	end

	return methodValue :: LifecycleMethod?
end

local function resolveServiceOrder(runner: RunnerData): { StoredService }
	local indegrees: { [string]: number } = {}
	local dependents: { [string]: { string } } = {}

	for _, service in runner.registeredServices do
		indegrees[service.name] = 0
		dependents[service.name] = {}
	end

	for _, service in runner.registeredServices do
		for _, dependencyName in service.dependencies do
			if runner.servicesByName[dependencyName] == nil then
				fail(
					runner,
					"dependency_rejected",
					"MISSING_DEPENDENCY",
					service.name,
					`Dependency '{dependencyName}' is not registered`
				)
			end

			indegrees[service.name] += 1
			table.insert(dependents[dependencyName], service.name)
		end
	end

	local order = {}
	local orderedNames: { [string]: boolean } = {}

	while #order < #runner.registeredServices do
		local nextService: StoredService? = nil

		for _, service in runner.registeredServices do
			if not orderedNames[service.name] and indegrees[service.name] == 0 then
				nextService = service
				break
			end
		end

		if nextService == nil then
			local cycleNames = {}
			for _, service in runner.registeredServices do
				if not orderedNames[service.name] then
					table.insert(cycleNames, service.name)
				end
			end

			local cycleDescription = table.concat(cycleNames, ",")
			fail(
				runner,
				"dependency_rejected",
				"DEPENDENCY_CYCLE",
				cycleDescription,
				`Dependency cycle includes: {cycleDescription}`
			)
		end

		orderedNames[nextService.name] = true
		table.insert(order, nextService)

		for _, dependentName in dependents[nextService.name] do
			indegrees[dependentName] -= 1
		end
	end

	return table.freeze(order)
end

local function invokeMethod(service: StoredService, methodName: "initialize" | "start" | "shutdown"): boolean
	local method = service[methodName]
	if method == nil then
		return true
	end
	return pcall(method)
end

local function unwindReachedServices(serviceOrder: { StoredService }, lastReachedIndex: number): string?
	local firstFailure: string? = nil
	for index = lastReachedIndex, 1, -1 do
		local service = serviceOrder[index]
		if not invokeMethod(service, "shutdown") and firstFailure == nil then
			firstFailure = service.name
		end
	end
	return firstFailure
end

function Runner.register(self: Runner, service: ServiceDefinition)
	requireState(self, "Registering", "register")

	if type(service) ~= "table" then
		fail(
			self,
			"registration_rejected",
			"INVALID_SERVICE",
			RUNNER_SERVICE_NAME,
			`Service definition must be a table; received {typeof(service)}`
		)
	end

	local serviceValue = service :: any
	local serviceName = validateServiceName(self, serviceValue.name, "Service name")

	if self.servicesByName[serviceName] ~= nil then
		fail(
			self,
			"registration_rejected",
			"DUPLICATE_SERVICE",
			serviceName,
			`Service '{serviceName}' is already registered`
		)
	end

	local storedService: StoredService = table.freeze({
		name = serviceName,
		dependencies = validateDependencies(self, serviceName, serviceValue.dependencies),
		initialize = validateMethod(self, serviceName, "initialize", serviceValue.initialize),
		start = validateMethod(self, serviceName, "start", serviceValue.start),
		shutdown = validateMethod(self, serviceName, "shutdown", serviceValue.shutdown),
	})

	self.servicesByName[serviceName] = storedService
	table.insert(self.registeredServices, storedService)
end

function Runner.initialize(self: Runner)
	requireState(self, "Registering", "initialize")

	self.serviceOrder = resolveServiceOrder(self)
	self.state = "Initializing"

	for index, service in self.serviceOrder do
		if not invokeMethod(service, "initialize") then
			self.state = "Failed"
			unwindReachedServices(self.serviceOrder, index)
			fail(
				self,
				"initialize_failed",
				"INITIALIZE_FAILED",
				service.name,
				"Lifecycle method 'initialize' failed; reached services were unwound"
			)
		end
	end

	self.state = "Initialized"
end

function Runner.start(self: Runner)
	requireState(self, "Initialized", "start")

	self.state = "Starting"

	local serviceOrder = self.serviceOrder :: { StoredService }
	for _, service in serviceOrder do
		if not invokeMethod(service, "start") then
			self.state = "Failed"
			unwindReachedServices(serviceOrder, #serviceOrder)
			fail(
				self,
				"start_failed",
				"START_FAILED",
				service.name,
				"Lifecycle method 'start' failed; initialized services were unwound"
			)
		end
	end

	self.state = "Started"
end

function Runner.shutdown(self: Runner)
	requireState(self, "Started", "shutdown")

	self.state = "ShuttingDown"

	local serviceOrder = self.serviceOrder :: { StoredService }
	local firstFailure = unwindReachedServices(serviceOrder, #serviceOrder)
	if firstFailure ~= nil then
		self.state = "Failed"
		fail(
			self,
			"shutdown_failed",
			"SHUTDOWN_FAILED",
			firstFailure,
			"Lifecycle shutdown attempted every service and one or more methods failed"
		)
	end

	self.state = "Shutdown"
end

function Runner.getState(self: Runner): LifecycleState
	return self.state
end

function Runner.getRegisteredServiceCount(self: Runner): number
	return #self.registeredServices
end

function Runner.getServiceOrder(self: Runner): { string }
	if self.serviceOrder == nil then
		fail(
			self,
			"inspection_rejected",
			"INVALID_STATE",
			RUNNER_SERVICE_NAME,
			"Service order is unavailable until initialization resolves dependencies"
		)
	end

	local serviceNames = {}
	for _, service in self.serviceOrder do
		table.insert(serviceNames, service.name)
	end

	return serviceNames
end

function ServiceLifecycle.new(logger: Log.Logger): Runner
	if not Log.isLogger(logger) then
		error(
			`[ATD][ERROR][context=unknown][role=Unresolved][placeId=unknown][environment=unknown][subsystem=lifecycle][event=construction_rejected][code=INVALID_CONTEXT][service={RUNNER_SERVICE_NAME}][state=Uninitialized] ServiceLifecycle requires a genuine context-bound Log`,
			0
		)
	end

	return setmetatable({
		logger = logger,
		state = "Registering",
		registeredServices = {},
		servicesByName = {},
		serviceOrder = nil,
	}, Runner) :: Runner
end

return table.freeze(ServiceLifecycle)
