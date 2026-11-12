-- All monetization identifiers live here. 0 means disabled, never a real purchase.
-- Creator Dashboard > experience > Monetization > Developer Products/Passes > Copy ID.
-- Sound IDs must be owned by or shared with this experience.
local Config = {
    -- Stage 1 only. Numeric RGB tables keep Config usable in pure Luau tests.
    NPC = {
        Enabled = true, Count = 14, WalkSpeed = 7,
        Animations={Idle="rbxassetid://507766666",Walk="rbxassetid://507777826"},
        AgentRadius = 2, AgentHeight = 6, JumpHeight = 4.5, TickSeconds = .12,
        MinWaypoints = 16, SpawnSpacing = .15, VisitStandSeconds = 2, DonationIntervalMin=3, DonationIntervalMax=7, DonationMin=1, DonationMax=5,
        IdleMin = 3, IdleMax = 7, PathTimeout = 100, WaypointTimeout = 7,
        StuckSeconds = 3.5, PathRetries = 2, MaxConcurrentPaths = 2,
        ChatDistance = 7, ChatSeconds = 5.5, ChatCooldownMin = 20, ChatCooldownMax = 34,
        BubbleDistance = 90, VisualDistance = 155, AnimationDistance = 100,
        Names = {"Mira","Kai","Robin","Sky","Alex","Sage","River","Sunny","Remy","Ash","Avery","Jules","Cedar","Nova"},
        Colors = {{177,144,216},{108,184,203},{226,170,195},{218,191,132},{133,192,171},{139,163,217},{215,148,144}},
        Skins = {{244,211,181},{205,158,120},{155,110,82},{104,75,60},{232,188,149}},
        Trousers = {62,72,94},
    },
    TestCurrency = {Name="D", Icon="rbxassetid://82441152708239", StartingBalance=500, MinDonation=1, MaxDonation=10000},
    RealPaymentsEnabled = false,
    Version = 1,
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
    Products = {
        SupportSmall = {Id = 0, Label = "Support the game", Coins = 100, Pearls = 2},
        SupportLarge = {Id = 0, Label = "Support the game + bonus", Coins = 600, Pearls = 10},
    },
    Passes = {
        Supporter = {Id = 0, Label = "Permanent Supporter title"},
    },
    -- Products/passes support the EXPERIENCE CREATOR, not players at booths.
    -- Player-to-player Robux must use Roblox Transfers; never simulate it with products.
    TransfersEnabled = false,
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
