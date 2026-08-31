--!strict

-- Gold used by this delivery is earned in play and is not purchasable with
-- Robux. Keep that policy explicit and separate from immutable banner odds so
-- a future paid-random policy gate can replace it without changing roll logic.
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
	},
}

table.freeze(AcquisitionConfig.banners[1])
table.freeze(AcquisitionConfig.banners)
return table.freeze(AcquisitionConfig)
