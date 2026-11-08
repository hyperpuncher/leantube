package model

import "core:strings"

Card_Action :: struct {
	kind:                   enum {
		Browse,
		Edit_Playlist,
		Feedback,
		Playlists,
		Menu,
	},
	label, target, payload: string,
	remove:                 bool,
}

card_action_destroy :: proc(action: ^Card_Action) {
	delete(action.label); delete(action.target); delete(action.payload)
	action^ = {}
}

card_actions_destroy :: proc(actions: ^[dynamic]Card_Action) {
	for &action in actions^ {card_action_destroy(&action)}
	delete(actions^)
	actions^ = nil
}

card_action_clone :: proc(action: Card_Action) -> Card_Action {
	return {
		kind = action.kind,
		label = strings.clone(action.label),
		target = strings.clone(action.target),
		payload = strings.clone(action.payload),
		remove = action.remove,
	}
}
