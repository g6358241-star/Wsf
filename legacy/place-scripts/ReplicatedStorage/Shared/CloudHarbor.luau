--!strict
-- Cloud Harbor map helpers. No ownership, currency or donation logic is enabled.
-- The static model lives in Workspace.CloudHarbor and is visible in Edit mode.
local Harbor = {}
export type Booth = Model

function Harbor.getMap(): Model
 return workspace:WaitForChild("CloudHarbor") :: Model
end

-- Sorted, stable names let later systems map booth IDs to ownership records.
function Harbor.getBooths(): {Booth}
 local booths: {Booth} = {}
 for _, child in Harbor.getMap():WaitForChild("Booths"):GetChildren() do
  if child:IsA("Model") then table.insert(booths, child) end
 end
 table.sort(booths, function(a, b) return a.Name < b.Name end)
 return booths
end

-- Clone an existing booth, preserving PrimaryPart, SignAttachment and ClaimPrompt.
-- Call on the server. Name must be unique in the target Booths folder.
function Harbor.cloneBooth(template: Booth, name: string, at: CFrame): Booth
 local folder = Harbor.getMap():WaitForChild("Booths")
 assert(not folder:FindFirstChild(name), "Booth name already exists")
 assert(template.PrimaryPart ~= nil, "Booth must have a PrimaryPart")
 local booth = template:Clone()
 booth.Name = name
 booth:PivotTo(at)
 local prompt = booth:FindFirstChild("ClaimPrompt", true)
 if prompt and prompt:IsA("ProximityPrompt") then prompt.Enabled = false end
 booth.Parent = folder
 return booth
end

-- Only predefined text is used here. Future player-written signs must go through
-- TextService filtering on the server before being displayed to other players.
function Harbor.setClaimPromptsEnabled(enabled: boolean)
 for _, booth in Harbor.getBooths() do
  local prompt = booth:FindFirstChild("ClaimPrompt", true)
  if prompt and prompt:IsA("ProximityPrompt") then prompt.Enabled = enabled end
 end
end
return Harbor
