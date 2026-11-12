-- All monetization identifiers live here. 0 means disabled, never a real purchase.
-- Creator Dashboard > experience > Monetization > Developer Products/Passes > Copy ID.
-- Sound IDs must be owned by or shared with this experience.
local Config = {
    -- Stage 1 only. Numeric RGB tables keep Config usable in pure Luau tests.
    NPC = {
        Enabled = true, WalkSpeed = 7,
        Animations={Idle="rbxassetid://507766666",Walk="rbxassetid://507777826"},
        AgentRadius = 2, AgentHeight = 6, JumpHeight = 4.5, TickSeconds = .12,
        -- Locomotion only. Population, decisions and money live in ServerScriptService.NpcCore.Config.
        MinWaypoints = 16, SpawnSpacing = .15,
        IdleMin = 3, IdleMax = 7, PathTimeout = 100, WaypointTimeout = 7,
        StuckSeconds = 3.5, PathRetries = 2, MaxConcurrentPaths = 4, QueueWaitSeconds = 20,
        FarThinkSeconds = .3, -- movement checks for NPCs far from every player (decisions are unaffected)
        ChatScanSeconds = 1, DespawnFadeSeconds = .6,
        ChatDistance = 7, ChatSeconds = 5.5, ChatCooldownMin = 20, ChatCooldownMax = 34,
        BubbleDistance = 90, VisualDistance = 155, AnimationDistance = 100,
        Names = {"Mira","Kai","Robin","Sky","Alex","Sage","River","Sunny","Remy","Ash","Avery","Jules","Cedar","Nova"},
        Colors = {{177,144,216},{108,184,203},{226,170,195},{218,191,132},{133,192,171},{139,163,217},{215,148,144}},
        Skins = {{244,211,181},{205,158,120},{155,110,82},{104,75,60},{232,188,149}},
        Trousers = {62,72,94},
    },
    -- APPROVED (owner, 2026-11-12): Coins = primary, DCoins = secondary, Pearls = legacy (see docs/PEARLS.md).
    -- Coins: NPC donations, Robux packs, playtime/daily/quest rewards. Spent on NPC requests.
    -- DCoins: ONLY from donating to NPCs. Never sold, bundled or granted by unrelated rewards.
    Currencies = {
        Primary = "Coins",
        Secondary = "DCoins",
        Coins = {Label = "Coins", Icon = ""}, -- OPEN: icon asset not chosen yet (UI concept phase)
        DCoins = {Label = "DCoins", Icon = "rbxassetid://82441152708239"},
    },
    -- Display data for existing client scripts. StartingBalance must stay 0: a starting grant would be an
    -- unrelated DCoins source. Existing saved DCoins balances are left untouched (see Migration).
    TestCurrency = {Name="DCoins", Icon="rbxassetid://82441152708239", StartingBalance=0},
    -- Player stand presets (brief §4.2, §12.12). No custom amounts in V1. Players may list any number of these.
    Stand = {
        Presets = {5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000}, -- PROPOSAL values
        DefaultOffers = {5, 10, 25, 50, 100}, -- applied on first claim until the stand editor UI exists
        ReservedForPlayers = 6, -- NPCs never take the last N free booths
    },
    Migration = {
        -- OPEN owner decision: DCoins saved before 2026-11-12 came from the old 500 starting grant and test donations.
        -- false = keep them spendable as-is. true = move them to LegacyDCoins (kept in the save, not spendable).
        QuarantineTestDCoins = false,
    },
    RealPaymentsEnabled = false,
    Version = 2,
    DataStore = "HarborProfiles_TestCurrency_v2",
    StudioMemoryOnly = true, -- Studio never writes production keys.
    AutosaveSeconds = 60,
    LeaseSeconds = 180,
    SaveAttempts = 3,
    DailySeconds = 86400, -- UTC calendar-day claim, NOT a rolling cooldown.
    PlayRewardSeconds = 300,
    PlayRewardCoins = 50,
    DailyCoins = 100,
    DailyPearls = 5,
    XPPerMinute = 10,
    XPPerLevel = 100,
    MaxBalance = 1000000000,
    BoardsSeconds = 120,
    MaxBoothText = 80,
    DonationSoundId = 0,
    -- Robux packs grant Coins ONLY (APPROVED). Never Pearls or DCoins. Amounts/prices are OPEN.
    Products = {
        SupportSmall = {Id = 0, Label = "Coin pack (small)", Coins = 100},
        SupportLarge = {Id = 0, Label = "Coin pack (large)", Coins = 600},
    },
    Passes = {
        Supporter = {Id = 0, Label = "Permanent Supporter title"},
    },
    -- Player-to-player donations and Robux transfers are removed from V1 (APPROVED). A future update
    -- would add a separate service; Profiles keeps only a drain for transfers queued before removal.
    Shop = {
        Sailor = {Label = "Sailor title", Kind = "Title", Currency = "Coins", Price = 150},
        Captain = {Label = "Captain title", Kind = "Title", Currency = "Pearls", Price = 30},
        SeaTrail = {Label = "Seafoam trail", Kind = "Effect", Currency = "Coins", Price = 250},
        GoldBooth = {Label = "Golden booth trim", Kind = "Booth", Currency = "Pearls", Price = 20},
        HarborHat = {Label = "Harbor lantern", Kind = "Accessory", Currency = "Coins", Price = 300},
        DoubleCoins = {Label = "2x play coins / 10 min", Kind = "Boost", Currency = "Pearls", Price = 10, Seconds = 600},
    },
    Quests = {
        Welcome = {Label = "Claim a booth", Field = "Claims", Target = 1, Coins = 75, Pearls = 1},
        Explorer = {Label = "Spend 10 minutes in the harbor", Field = "PlaySeconds", Target = 600, Coins = 150, Pearls = 3},
        Collector = {Label = "Own 3 cosmetics", Field = "Items", Target = 3, Coins = 200, Pearls = 5},
    },
}
return Config
