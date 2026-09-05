--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AudioManifest = require(ReplicatedStorage.Shared.presentation.AudioManifest)
local PresentationPolicy = require(ReplicatedStorage.Shared.presentation.PresentationPolicy)

export type Adapter = {
	now: () -> number,
	setVolume: (string, number) -> (),
	create: (string, string, boolean) -> any,
	loaded: (any) -> boolean,
	play: (any) -> (),
	destroy: (any) -> (),
	cleanup: () -> (),
}

type Track = {
	handle: any,
	key: string,
	group: string,
	priority: number,
	createdAt: number,
	startedAt: number?,
	duration: number,
	looped: boolean,
}

type Data = {
	adapter: Adapter,
	manifest: any,
	tracks: { Track },
	lastCue: { [string]: number },
	unavailable: { [string]: boolean },
	scene: string?,
	cleaned: boolean,
	started: number,
	dropped: number,
	failed: number,
	settings: { [string]: number },
}

local AudioDirector = { ROOT_NAME = "_ATDAudio", LOAD_TIMEOUT_SECONDS = 4 }
local Methods = {}
Methods.__index = Methods
local DATA: { [any]: Data } = setmetatable({}, { __mode = "k" }) :: any
local SCENES = table.freeze({ Lobby = true, Match = true, Boss = true, Victory = true, Defeat = true })

local function increment(value: number): number
	return math.min(value + 1, 1_000_000_000)
end

local function safeTime(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value < 1e12
end

local function destroy(data: Data, index: number)
	local track = table.remove(data.tracks, index)
	pcall(data.adapter.destroy, track.handle)
end

local function reject(data: Data): boolean
	data.dropped = increment(data.dropped)
	return false
end

local function markUnavailable(data: Data, key: string)
	if not data.unavailable[key] then
		data.unavailable[key] = true
		data.failed = increment(data.failed)
	end
end

local function hasProvenance(entry: any, group: string): boolean
	if type(entry) ~= "table" or entry.approved ~= true or entry.permissionVerified ~= true or entry.group ~= group then
		return false
	end
	if
		type(entry.assetId) ~= "string"
		or #entry.assetId > 40
		or not string.match(entry.assetId, "^rbxassetid://[1-9][0-9]+$")
	then
		return false
	end
	for _, name in { "owner", "license", "source" } do
		local value = entry[name]
		if type(value) ~= "string" or #value < 1 or #value > 240 or string.find(value, "[%c]") then
			return false
		end
	end
	return true
end

local function admit(
	data: Data,
	key: string,
	group: string,
	priority: number,
	duration: number,
	looped: boolean
): boolean
	if data.cleaned or data.unavailable[key] then
		return reject(data)
	end
	-- One cold-load attempt per key is enough. Later occurrences remain optional
	-- while that attempt loads; they must not create a queue of stale sounds.
	for _, track in data.tracks do
		if track.key == key and track.startedAt == nil then
			return reject(data)
		end
	end
	local entry = data.manifest.entries[key]
	if not hasProvenance(entry, group) then
		markUnavailable(data, key)
		return reject(data)
	end
	local now = data.adapter.now()
	if not safeTime(now) then
		return reject(data)
	end
	local groupCount = 0
	for _, track in data.tracks do
		if track.group == group then
			groupCount += 1
		end
	end
	if group == "UI" and groupCount >= PresentationPolicy.MAX_UI_SOUNDS then
		local candidate: number? = nil
		for index, track in data.tracks do
			if track.group == group and track.priority < priority then
				candidate = index
				break
			end
		end
		if candidate == nil then
			return reject(data)
		end
		destroy(data, candidate)
	end
	if #data.tracks >= PresentationPolicy.MAX_SOUNDS then
		local candidate: number? = nil
		for index, track in data.tracks do
			if
				not track.looped
				and track.priority < priority
				and (candidate == nil or track.priority < data.tracks[candidate].priority)
			then
				candidate = index
			end
		end
		if candidate == nil then
			return reject(data)
		end
		destroy(data, candidate)
	end
	local created, handle = pcall(data.adapter.create, entry.assetId, group, looped)
	if not created or handle == nil then
		markUnavailable(data, key)
		return reject(data)
	end
	table.insert(data.tracks, {
		handle = handle,
		key = key,
		group = group,
		priority = priority,
		createdAt = now,
		duration = duration,
		looped = looped,
	})
	return true
end

function AudioDirector.new(adapter: Adapter, manifest: any?)
	local self = setmetatable({}, Methods)
	local selectedManifest = if type(manifest) == "table"
			and getmetatable(manifest) == nil
			and manifest.version == AudioManifest.version
			and type(manifest.entries) == "table"
			and getmetatable(manifest.entries) == nil
		then manifest
		else AudioManifest
	DATA[self] = {
		adapter = adapter,
		manifest = selectedManifest,
		tracks = {},
		lastCue = {},
		unavailable = {},
		scene = nil,
		cleaned = false,
		started = 0,
		dropped = 0,
		failed = 0,
		settings = { Master = 0, Music = 1, SFX = 1, UI = 1 },
	}
	return self
end

function Methods.applySettings(self: any, settings: any): boolean
	local data = DATA[self]
	if data.cleaned or type(settings) ~= "table" then
		return false
	end
	for _, field in { "masterVolume", "musicVolume", "sfxVolume", "uiVolume" } do
		local value = settings[field]
		if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
			return false
		end
	end
	local values = {
		Master = settings.masterVolume,
		Music = settings.musicVolume,
		SFX = settings.sfxVolume,
		UI = settings.uiVolume,
	}
	for group, volume in values do
		data.settings[group] = volume
		pcall(data.adapter.setVolume, group, volume)
	end
	return true
end

function Methods.setScene(self: any, scene: unknown): boolean
	local data = DATA[self]
	if data.cleaned or type(scene) ~= "string" or not SCENES[scene] then
		return false
	end
	if data.scene == scene then
		return true
	end
	-- A scene change stops the preceding track immediately. This bounds music to
	-- one voice even when the next asset is unavailable or slow to load.
	for index = #data.tracks, 1, -1 do
		if data.tracks[index].group == "Music" then
			destroy(data, index)
		end
	end
	data.scene = scene
	admit(data, `Music.{scene}`, "Music", 4, 0, true)
	return true
end

function Methods.cue(self: any, key: unknown): boolean
	local data = DATA[self]
	if data.cleaned or type(key) ~= "string" then
		return false
	end
	local cue = PresentationPolicy.CUES[key]
	if cue == nil then
		return false
	end
	local now = data.adapter.now()
	if not safeTime(now) then
		return false
	end
	local previous = data.lastCue[key]
	if previous ~= nil and now - previous < cue.minimumInterval then
		return reject(data)
	end
	data.lastCue[key] = now
	return admit(data, key, cue.group, cue.priority, cue.duration, false)
end

function Methods.step(self: any, timeValue: unknown)
	local data = DATA[self]
	if data.cleaned or not safeTime(timeValue) then
		return
	end
	local now = timeValue :: number
	for index = #data.tracks, 1, -1 do
		local track = data.tracks[index]
		if track.startedAt == nil then
			local checked, loaded = pcall(data.adapter.loaded, track.handle)
			if not checked or now - track.createdAt >= AudioDirector.LOAD_TIMEOUT_SECONDS then
				markUnavailable(data, track.key)
				destroy(data, index)
			elseif loaded and not track.looped and now - track.createdAt >= track.duration then
				-- The asset may now be cached for the next cue, but this occurrence
				-- is already stale and must never play after its visual outcome.
				data.dropped = increment(data.dropped)
				destroy(data, index)
			elseif loaded then
				local played = pcall(data.adapter.play, track.handle)
				if played then
					track.startedAt = now
					data.started = increment(data.started)
				else
					markUnavailable(data, track.key)
					destroy(data, index)
				end
			end
		elseif not track.looped and now - track.startedAt >= track.duration then
			destroy(data, index)
		end
	end
end

function Methods.getMetrics(self: any): any
	local data = DATA[self]
	return table.freeze({
		activeSounds = #data.tracks,
		started = data.started,
		dropped = data.dropped,
		unavailable = data.failed,
		scene = data.scene,
		cleaned = data.cleaned,
	})
end

function Methods.cleanup(self: any): boolean
	local data = DATA[self]
	if data.cleaned then
		return true
	end
	data.cleaned = true
	for index = #data.tracks, 1, -1 do
		destroy(data, index)
	end
	table.clear(data.lastCue)
	table.clear(data.unavailable)
	pcall(data.adapter.cleanup)
	return true
end

function AudioDirector.newForSoundService(soundService: Instance)
	local root: Folder? = nil
	local groups: { [string]: SoundGroup } = {}
	pcall(function()
		if soundService:FindFirstChild(AudioDirector.ROOT_NAME) ~= nil then
			return
		end
		local folder = Instance.new("Folder")
		folder.Name = AudioDirector.ROOT_NAME
		root = folder
		local master = Instance.new("SoundGroup")
		master.Name = "Master"
		-- Wait for the saved settings projection before unmuting first-join audio.
		master.Volume = 0
		master.Parent = folder
		groups.Master = master
		for _, name in { "Music", "SFX", "UI" } do
			local group = Instance.new("SoundGroup")
			group.Name = name
			group.Volume = 1
			group.Parent = master
			groups[name] = group
		end
		folder.Parent = soundService
	end)
	return AudioDirector.new({
		now = os.clock,
		setVolume = function(group, volume)
			if groups[group] ~= nil then
				groups[group].Volume = volume
			end
		end,
		create = function(assetId, group, looped)
			if root == nil or groups[group] == nil then
				return nil
			end
			local sound = Instance.new("Sound")
			local configured = pcall(function()
				sound.Name = "ATDVoice"
				sound.Volume = 0.6
				sound.Looped = looped
				sound.SoundGroup = groups[group]
				sound.SoundId = assetId
				sound.Parent = root
			end)
			if not configured then
				sound:Destroy()
				return nil
			end
			return sound
		end,
		loaded = function(sound)
			return sound.IsLoaded
		end,
		play = function(sound)
			sound:Play()
		end,
		destroy = function(sound)
			pcall(function()
				sound:Stop()
			end)
			sound:Destroy()
		end,
		cleanup = function()
			if root ~= nil then
				root:Destroy()
				root = nil
			end
			table.clear(groups)
		end,
	})
end

table.freeze(Methods)
return table.freeze(AudioDirector)
