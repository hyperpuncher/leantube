#+test
package main

import "core:testing"
import sdl "vendor:sdl3"

@(test)
remote_moves_between_rail_and_cards_without_changing_the_selected_card :: proc(t: ^testing.T) {
	old_selected, old_columns := selected, grid_columns
	old_focus, old_cursor, old_active := rail_focus, rail_cursor, rail_active
	defer {
		selected, grid_columns = old_selected, old_columns
		rail_focus, rail_cursor, rail_active = old_focus, old_cursor, old_active
	}
	grid_columns = 3
	selected = 4
	rail_focus = false
	rail_active = .Search
	testing.expect(t, !navigation_key(sdl.K_LEFT, nil))
	selected = 3
	testing.expect(t, navigation_key(sdl.K_LEFT, nil))
	testing.expect(t, rail_focus)
	testing.expect_value(t, rail_cursor, .Search)
	navigation_key(sdl.K_DOWN, nil)
	testing.expect_value(t, rail_cursor, .Subscriptions)
	for _ in 0 ..< 8 {navigation_key(sdl.K_DOWN, nil)}
	testing.expect_value(t, rail_cursor, .Liked)
	for _ in 0 ..< 8 {navigation_key(sdl.K_UP, nil)}
	testing.expect_value(t, rail_cursor, .Account)
	navigation_key(sdl.K_RIGHT, nil)
	testing.expect(t, !rail_focus)
	testing.expect_value(t, selected, 3)
}
