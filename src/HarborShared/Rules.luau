-- Pure, non-yielding economic rules. Invoked only by server profile transactions.
local Rules = {}
function Rules.credit(data, currency, amount, config)
    assert(currency == "Coins" or currency == "Pearls", "Unknown currency")
    assert(type(amount) == "number" and amount == amount and amount >= 0 and amount % 1 == 0, "Invalid reward")
    data[currency] = math.min(config.MaxBalance, data[currency] + amount)
end
function Rules.daily(data, now, config)
    local day = math.floor(now / config.DailySeconds)
    if data.LastDaily >= day then return false, "Daily reward already claimed. Resets at 00:00 UTC." end
    data.LastDaily = day
    Rules.credit(data, "Coins", config.DailyCoins, config)
    Rules.credit(data, "Pearls", config.DailyPearls, config)
    return true, "Daily reward: +100 Coins and +5 Pearls!"
end
function Rules.buy(data, key, now, config)
    local item = config.Shop[key]
    if not item then return false, "Unknown shop item." end
    if item.Kind ~= "Boost" and data.Inventory[key] then return false, "Already owned. Equip it instead." end
    if data[item.Currency] < item.Price then return false, "Not enough " .. item.Currency .. "." end
    if item.Kind == "Boost" and data.BoostUntil > now then return false, "Your boost is already active." end
    data[item.Currency] -= item.Price
    if item.Kind == "Boost" then data.BoostUntil = now + item.Seconds else data.Inventory[key] = true end
    return true, "Unlocked: " .. item.Label
end
function Rules.equip(data, key, config)
    if key == "Supporter" and data.Passes and data.Passes.Supporter then
        if data.Equipped.Title == "Supporter" then data.Equipped.Title=nil else data.Equipped.Title="Supporter" end
        return true, "Supporter title equipped."
    end
    local item = config.Shop[key]
    if not item or item.Kind == "Boost" or not data.Inventory[key] then return false, "You don't own this cosmetic." end
    if data.Equipped[item.Kind] == key then data.Equipped[item.Kind] = nil else data.Equipped[item.Kind] = key end
    return true, "Cosmetic updated."
end
function Rules.quest(data, key, config)
    local quest = config.Quests[key]
    if not quest then return false, "Unknown quest." end
    if data.Quests[key] then return false, "Quest already claimed." end
    local value = data[quest.Field]
    if quest.Field == "Items" then value = 0; for _ in data.Inventory do value += 1 end end
    if type(value) ~= "number" or value < quest.Target then return false, "Quest is not complete yet." end
    data.Quests[key] = true
    Rules.credit(data, "Coins", quest.Coins, config)
    Rules.credit(data, "Pearls", quest.Pearls, config)
    return true, "Quest complete: " .. quest.Label
end
function Rules.tick(data, seconds, now, config)
    seconds = math.clamp(math.floor(seconds), 0, 60)
    local before = data.PlaySeconds
    data.PlaySeconds += seconds
    local minutes = math.floor(data.PlaySeconds / 60) - math.floor(before / 60)
    data.XP += minutes * config.XPPerMinute
    local index = math.floor(data.PlaySeconds / config.PlayRewardSeconds)
    local rewards = math.max(0, index - data.RewardIndex)
    data.RewardIndex = index
    if rewards > 0 then
        -- Apply boost only while it is active when this server interval settles.
        local multiplier = data.BoostUntil > now and 2 or 1
        Rules.credit(data, "Coins", rewards * config.PlayRewardCoins * multiplier, config)
        Rules.credit(data, "Pearls", rewards, config)
    end
    return true, rewards
end
return Rules
