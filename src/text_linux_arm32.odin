package main

// Keep emoji priority; use the installed text fonts only for missing glyphs.
// LG Display Regular covers broad scripts. LGIndia supplies U+2024 instead.
FALLBACK_FONT_PATHS :: [?]cstring {
	"/usr/share/fonts/NotoEmoji-Regular.ttf",
	"/usr/share/fonts/LG_Display-Regular.ttf",
	"/usr/share/fonts/LG_Display_IN.ttf",
}
