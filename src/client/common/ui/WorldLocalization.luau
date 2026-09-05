--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldMessages = require(ReplicatedStorage.Shared.localization.WorldMessages)
local Accessibility = require(ReplicatedStorage.Shared.settings.Accessibility)
local TextLayout = require(script.Parent.TextLayout)
local WorldLocalization = {}

function WorldLocalization.new(world: Instance)
	local displays: { [BillboardGui]: boolean } = {}
	local count = 0
	local savedSettings: any = {}
	local function observe(candidate: Instance)
		if
			count < 32
			and candidate.Name == "ATDQueueWorldDisplay"
			and candidate:IsA("BillboardGui")
			and not displays[candidate]
		then
			displays[candidate] = true
			count += 1
		end
	end
	for _, candidate in world:GetDescendants() do
		observe(candidate)
	end
	local connection = world.DescendantAdded:Connect(observe)
	local lastStep = -math.huge
	return {
		applySettings = function(_self: any, settings: any)
			savedSettings = { uiScale = settings.uiScale }
		end,
		step = function(_self: any, now: number)
			if now - lastStep < 0.25 then
				return
			end
			lastStep = now
			local preferences = Accessibility.resolve(savedSettings, Accessibility.readPreferences())
			for display in displays do
				if display.Parent == nil then
					displays[display] = nil
					count -= 1
				else
					local height = 82
					local labels = 0
					for _, descendant in display:GetDescendants() do
						if descendant:IsA("TextLabel") and labels < 16 and WorldMessages.render(descendant) then
							labels += 1
							descendant.TextSize = math.floor(18 * preferences.textScale * preferences.uiScale)
							local rowHeight =
								TextLayout.measure(descendant.Text, descendant.TextSize, 344, descendant.Font)
							descendant.Size = UDim2.new(1, -16, 0, rowHeight)
							height += rowHeight + 3
						end
					end
					display.Size = UDim2.fromOffset(360, height)
					local panel = display:FindFirstChild("Panel")
					if panel ~= nil and panel:IsA("Frame") then
						panel.BackgroundTransparency = preferences.transparency
					end
				end
			end
		end,
		cleanup = function()
			connection:Disconnect()
			table.clear(displays)
		end,
	}
end

return table.freeze(WorldLocalization)
