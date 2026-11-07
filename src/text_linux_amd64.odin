package main

FALLBACK_FONT_PATHS :: [?]cstring {
	#config(EMOJI_FONT_PATH, "/usr/share/fonts/noto/NotoEmoji-Regular.ttf"),
	#config(TEXT_FALLBACK_FONT_PATH, "/usr/share/fonts/noto/NotoSans-Regular.ttf"),
	// Host Noto Sans already covers the TV-specific punctuation fallback.
	#config(TEXT_PUNCT_FONT_PATH, ""),
	"fonts/NotoSansMath.ttf",
}
