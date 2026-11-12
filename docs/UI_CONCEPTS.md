# UI Concepts — NPC Donation Simulator (CloudHarbor)

> **These are static mockups, not in-game UI.** They are HTML/CSS/SVG renderings (source `.html` next to each `.png` in `docs/ui-concepts/`) drawn over a simplified stand-in of the harbor. Fonts load from Google Fonts. Nothing here is implemented in Roblox yet. **The owner chooses one concept before full UI implementation begins.**

Shared across all concepts: **Coins** = round embossed gold coin with a "C"; **DCoins** = hexagonal teal token with a brass rim and a "D" (different silhouette and colour so they are never confused). Amount lists use only the 14 presets (5 … 100,000); no free-text amounts. The NPC request prompt has exactly Accept / Decline. Colours come from the map palette: teal `#2f9493`, gold `#cca45b`, deep teal `#1d414a`, ivory `#fdf5df`, plus the tints listed per concept.

## A — Harbor Signage
**Idea.** The UI is the market's own signage: painted teal plank boards with brass rivets, a gold inner pinstripe, ivory paper labels pinned on top, balances hung from rope like booth signs. It matches the 48 booths with canopies and sign boards, so menus feel like more stalls rather than an overlay.
- **Palette:** teal `#2f9493` (board), deep teal `#1d414a` (outline/type), gold `#cca45b` (primary action; brass rivets `#f3dca0`→`#8a6420`), ivory `#fdf5df` (paper labels), parchment stripe `#f3e8c9`, rope `#c9a46a`.
- **Type:** Alfa Slab One (headings, numerals, buttons) + Chivo 400/600/800 (labels, rows).
- **Components:** Buttons are ivory paper tags with a deep-teal edge and a hard drop "ledge"; primary = gold. Hover: lift 2px. Pressed: drops 4px, ledge shrinks. Selected preset: ivory tag with a brass stud; unselected: dashed outline, recessed on the teal board; disabled: grey-ivory, flattened. Rows: ivory with alternating parchment; own row gold with deep-teal outline.
- **Motion:** panels swing slightly on their rope and settle (~250 ms); buttons press like a physical tag; coin count ticks up.
- **Mobile:** nav boards stay bottom centre at 80×66 px; balance signs shrink; amount grid stays 4 columns with page buttons.
- **Pros:** Strongest tie to the map's booths; high contrast; chunky touch targets. **Cons:** Heaviest visually; many panels could feel busy; slab type is less "premium".
- **Files:** `A-hud`, `A-hud-mobile`, `A-stand-editor`, `A-npc-request`, `A-npc-donation`, `A-stats`, `A-leaderboard` (`.png` + `.html`).

## B — Marble & Brass
**Idea.** A calm plaza style taken from Compass Plaza itself: ivory marble panels with faint veining, thin gold double-rules, deep-teal serif type. Balances sit in a slim top plaque, navigation is a vertical strip on the right (bottom bar on mobile). Quiet and premium, so the sunny map stays the star.
- **Palette:** ivory `#fdf5df`, marble vein `#c8d6d2`, gold `#cca45b` (rules/accents), deep teal `#1d414a` (type, selected fill), muted label `#7a8c8a`, stone `#d9cda5`.
- **Type:** Cormorant Garamond 500–700 (headings, amounts, balances) + Jost 400–600 uppercase tracked (labels, buttons).
- **Components:** Flat outlined buttons; primary = deep-teal fill with a gold hairline offset. Hover: tint fill; pressed: darker teal. Selected preset: deep-teal tile with inner gold line; unselected: pale outline; disabled: grey-teal outline. Rows separated by hairlines; own row gold tint with a gold left bar.
- **Motion:** fades and 8 px slides, slow (~200 ms); no bounce.
- **Mobile:** bottom icon+label bar (56 px tall), compact top plaque, panels go full width.
- **Pros:** Most refined, least noise, scales to many panels. **Cons:** Least playful; thin lines and light labels need care for contrast on small phones; could read as a generic luxury template without more harbor motifs.
- **Files:** `B-hud`, `B-hud-mobile`, `B-stand-editor`, `B-npc-request`, `B-npc-donation`, `B-stats`, `B-leaderboard`.

## C — Captain's Ledger
**Idea.** The harbormaster's paper: ruled ledger pages with a red margin line and punched holes, section tabs on the screen edge like notebook dividers, circled entries instead of toggles, a red "STAND 14 · OPEN" stamp, and handwritten numerals for money. It suits a market where each donation is an entry in the book.
- **Palette:** page `#f4e8c8`, entry paper `#fbf4de`, rule teal `#2f9493` (low alpha), margin/stamp red `#a3412f` (small accent outside the map palette), ink `#1d414a`, edge `#7d6a3e`, gold `#cca45b`.
- **Type:** IM Fell English italic (titles), Courier Prime (body, labels), Caveat (numerals, sign text).
- **Components:** Buttons are paper slips with hard offset shadow; primary = teal. Hover: shadow grows; pressed: slip sinks onto the page. Selected preset: ink border with a hand-drawn red circle; unselected: dashed outline; disabled: dashed, no shadow. Rows on ledger lines; own row gold wash with a red box.
- **Motion:** tabs slide out ~12 px; page-flip ~180 ms between sections; circle/stamp draws in on selection.
- **Mobile:** tabs shrink to 48 px wide on the left edge; balances on one note at top right.
- **Pros:** Most distinctive; stats and leaderboard feel natural. **Cons:** Monospace and handwriting hurt legibility at small sizes; vertical tab text localises poorly; red accent is outside the map palette; most texture work to build.
- **Files:** `C-hud`, `C-hud-mobile`, `C-stand-editor`, `C-npc-request`, `C-npc-donation`, `C-stats`, `C-leaderboard`.

## Comparison
| | A Harbor Signage | B Marble & Brass | C Captain's Ledger |
|---|---|---|---|
| World fit | Booth signs | Compass Plaza | Harbor office |
| Mood | Playful, sturdy | Calm, premium | Characterful, tactile |
| Mobile readability | Best | Good (thin lines) | Fair |
| Build effort | Medium | Low–medium | High |
| Distinctiveness | High | Medium | Highest |
| Main risk | Busy | Generic | Legibility |

All 21 mockups (7 per concept: HUD, HUD mobile 844×390, stand editor, NPC request, NPC donation, statistics, leaderboard) are in `docs/ui-concepts/`. The owner picks one concept before full UI implementation starts.
