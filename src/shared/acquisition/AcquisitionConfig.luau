--!strict

-- Gold used by this delivery is earned in play and is not purchasable with
-- Robux. Keep that policy explicit and separate from immutable banner odds so
-- a future paid-random policy gate can replace it without changing roll logic.
local ContentSelection = require(script.Parent.Parent.config.ContentSelection)

local AcquisitionConfig = {
	version = 1,
	banners = {
		{
			bannerId = "banner:starter",
			bannerVersion = 1,
			available = true,
			currencyPolicy = "EarnOnlyGold",
			policyDisclosure = "Gold is earned through play. This chest has no Robux purchase or paid-currency conversion.",
		},
		{
			bannerId = ContentSelection.RELEASE_BANNER_ID,
			bannerVersion = 1,
			available = true,
			currencyPolicy = "EarnOnlyGold",
			policyDisclosure = "Gold is earned through play. Odds are disclosed before every Garden Tower Chest pull; duplicates remain separate units.",
		},
	},
}

for _, policy in AcquisitionConfig.banners do
	table.freeze(policy)
end
table.freeze(AcquisitionConfig.banners)
return table.freeze(AcquisitionConfig)
