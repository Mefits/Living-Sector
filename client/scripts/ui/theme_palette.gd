class_name ThemePalette
extends RefCounted

## Shared color palette for the holographic HUD theme. Referenced by the
## Theme resource (for StyleBoxes and font colors) and by custom-drawn
## controls (MarketCell, Minimap, toast defaults) that can't receive
## theme overrides through the normal cascade.
##
## Edit here once; the whole UI follows.

const PRIMARY := Color("#55d0ff")        # info / borders / accents
const PRIMARY_DIM := Color("#2a7ea0")    # inactive / secondary lines
const PRIMARY_BRIGHT := Color("#aae5ff") # hover / active highlights

const PANEL_BG := Color(0.05, 0.08, 0.12, 0.85)          # dark translucent
const PANEL_BG_SOLID := Color(0.04, 0.06, 0.10, 1.0)     # opaque panels
const PANEL_HEADER_BG := Color(0.08, 0.14, 0.20, 0.9)    # slightly lit

const TEXT := Color("#dff3ff")           # default body text
const TEXT_DIM := Color("#8aaacc")       # captions / subtitles
const TEXT_BRIGHT := Color("#ffffff")    # titles on accent chips

const SUCCESS := Color("#7cd992")        # cheap / healthy / delivered
const WARN := Color("#ffb347")           # caution / mid-risk
const DANGER := Color("#ff5a5a")         # high-risk / broke / shortage
const INFO := Color("#55d0ff")           # alias for PRIMARY

const SEPARATOR := Color(0.35, 0.55, 0.75, 0.35)
