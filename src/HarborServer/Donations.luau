-- Donation feedback (toasts and booth effects). V1 has no player-to-player donations (APPROVED 2026-11-12)
-- and no timer-based NPC grants: every NPC donation comes from NpcDirector after a real stand visit and is
-- paid out of that NPC's own donation budget.
local Players=game:GetService('Players')
local Profiles=require(script.Parent.Profiles)
local Booths=require(script.Parent.Booths)
local M={};local remote
function M.notify(owner,name,amount,npcModel)
 if not owner.Parent then return end
 remote:FireClient(owner,'Donation',{Name=name,UserId=0,Amount=amount,Currency='Coins',NPC=npcModel~=nil,NPCModel=npcModel,Kind='NpcDonation'})
 local id=Booths.owned[owner.UserId];local entry=id and Booths.entries[id]
 if entry and entry.owner==owner then
  for _,viewer in Players:GetPlayers() do
   local root=viewer.Character and viewer.Character:FindFirstChild('HumanoidRootPart')
   if root and (root.Position-entry.anchor.Position).Magnitude<=120 then remote:FireClient(viewer,'DonationEffect',{BoothModel=entry.model,Amount=amount}) end
  end
 end
end
function M.init(event)
 remote=event
 -- Legacy drain only: transfers queued before player-to-player donations were removed (Profiles.reconcile).
 Profiles.DonationDelivered.Event:Connect(function(owner,senderId,amount)
  if not owner.Parent then return end
  local sender=Players:GetPlayerByUserId(senderId)
  remote:FireClient(owner,'Donation',{Name=sender and sender.DisplayName or ('Player '..senderId),UserId=senderId,Amount=amount,Currency='DCoins',NPC=false,Kind='LegacyTransfer'})
 end)
end
return M
