-- Isolated stage-1 entry point; the existing gameplay entry is unchanged.
local service=require(script.Parent.NPCService)
local ok,err=pcall(service.Start)
if not ok then service.Stop();warn('[NPC] Startup failed: '..tostring(err)) end
