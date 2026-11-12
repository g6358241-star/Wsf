--!strict
return {
	storeName = "PlayerData_v1",
	schemaVersion = 1,
	autosaveSeconds = 60,
	sessionLockTtlSeconds = 180, -- a lock older than this is treated as abandoned by a crashed server
	loadAttempts = 6,
	retryBaseSeconds = 1,

	History = {
		maxRecords = 200, -- OPEN (§10 Statistics): history depth
		dailyDays = 30, -- OPEN: chart period
	},

	Memory = {
		retentionSeconds = 3 * 24 * 3600, -- AGREED: 3 days after the latest meaningful interaction
		maxEventsPerNpc = 4,
		maxNpcs = 300, -- size guard for the DataStore entry
	},

	Reputation = {
		maxReasonLog = 20,
	},

	Products = {
		-- OPEN: Developer Product ids and pack contents are not approved. Empty = no products are offered.
		-- [productId] = { kind = "PrimaryPack", amount = 0 }
	} :: { [number]: { kind: string, amount: number } },
	VipGamePassId = 0, -- OPEN: 0 = VIP not configured yet
}
