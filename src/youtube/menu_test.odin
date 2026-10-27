#+test
package youtube

import "../model"
import "core:encoding/json"
import "core:testing"

@(test)
card_menu_keeps_only_supported_actions_and_request_fields :: proc(t: ^testing.T) {
	value, error := json.parse(
		`{"showMenuCommand":{"menu":{"menuRenderer":{"items":[
		{"menuNavigationItemRenderer":{"text":{"simpleText":"Play"},"navigationEndpoint":{"watchEndpoint":{"videoId":"DN953UW8iJ8","ustreamerConfig":"not retained"}}}},
		{"menuServiceItemRenderer":{"text":{"simpleText":"Save to Watch later"},"serviceEndpoint":{"playlistEditEndpoint":{"playlistId":"WL","actions":[{"action":"ACTION_ADD_VIDEO","addedVideoId":"DN953UW8iJ8"}]}}}},
		{"menuNavigationItemRenderer":{"text":{"simpleText":"Save to playlist"},"navigationEndpoint":{"addToPlaylistEndpoint":{"videoId":"DN953UW8iJ8"}}}},
		{"menuNavigationItemRenderer":{"text":{"simpleText":"Go to channel"},"navigationEndpoint":{"browseEndpoint":{"browseId":"UC-example"}}}},
		{"menuServiceItemRenderer":{"text":{"simpleText":"Not interested"},"serviceEndpoint":{"feedbackEndpoint":{"feedbackToken":"feedback-fixture","actions":[{"ignored":"client-only UI action"}]}}}},
		{"menuServiceItemRenderer":{"text":{"simpleText":"Hide"},"serviceEndpoint":{"feedbackEndpoint":{"feedbackToken":"hide-fixture"}}}},
		{"menuServiceItemRenderer":{"text":{"simpleText":"Unsupported"},"serviceEndpoint":{"unknownEndpoint":{}}}}
	]}}}}`,
	)
	if !testing.expect_value(t, error, .None) {return}
	defer json.destroy_value(value)
	actions := parse_card_actions(value)
	defer model.card_actions_destroy(&actions)
	if !testing.expect_value(t, len(actions), 4) {return}
	testing.expect_value(t, actions[0].kind, .Edit_Playlist)
	testing.expect_value(t, actions[0].target, "WL")
	testing.expect_value(t, actions[2].kind, .Browse)
	testing.expect_value(t, actions[2].target, "UC-example")
	for index in ([]int{0, 1, 3}) {
		request, err := json.parse(actions[index].payload)
		if !testing.expect_value(t, err, .None) {continue}
		defer json.destroy_value(request)
		client_name, _ := field(
			field(field(request, "context"), "client"),
			"clientName",
		).(json.String)
		testing.expect_value(t, string(client_name), "TVHTML5")
		object, _ := request.(json.Object)
		testing.expect_value(t, len(object), index == 0 ? 3 : 2)
		if index == 0 {
			id, _ := field(request, "playlistId").(json.String)
			testing.expect_value(t, string(id), "WL")
			edits, _ := field(request, "actions").(json.Array)
			if testing.expect_value(t, len(edits), 1) {
				command, _ := field(edits[0], "action").(json.String)
				video, _ := field(edits[0], "addedVideoId").(json.String)
				testing.expect_value(t, string(command), "ACTION_ADD_VIDEO")
				testing.expect_value(t, string(video), "DN953UW8iJ8")
			}
		} else if index == 1 {
			ids, _ := field(request, "videoIds").(json.Array)
			if testing.expect_value(t, len(ids), 1) {
				id, _ := ids[0].(json.String)
				testing.expect_value(t, string(id), "DN953UW8iJ8")
			}
		} else {
			tokens, _ := field(request, "feedbackTokens").(json.Array)
			if testing.expect_value(t, len(tokens), 1) {
				token, _ := tokens[0].(json.String)
				testing.expect_value(t, string(token), "feedback-fixture")
			}
		}
	}
}

@(test)
playlist_picker_uses_membership_to_choose_add_or_remove :: proc(t: ^testing.T) {
	value, error := json.parse(
		`{"contents":[{"addToPlaylistRenderer":{"playlists":[
		{"playlistAddToOptionRenderer":{"title":{"simpleText":"Watch later"},"containsSelectedVideos":"ALL","addToPlaylistServiceEndpoint":{"playlistEditEndpoint":{"playlistId":"WL","actions":[{"action":"ACTION_ADD_VIDEO","addedVideoId":"DN953UW8iJ8"}]}},"removeFromPlaylistServiceEndpoint":{"playlistEditEndpoint":{"playlistId":"WL","actions":[{"action":"ACTION_REMOVE_VIDEO","setVideoId":"set-fixture"}]}}}},
		{"playlistAddToOptionRenderer":{"title":{"simpleText":"Favorites"},"containsSelectedVideos":"NONE","addToPlaylistServiceEndpoint":{"playlistEditEndpoint":{"playlistId":"PL-fixture","actions":[{"action":"ACTION_ADD_VIDEO","addedVideoId":"DN953UW8iJ8"}]}}}}
	]}}]}`,
	)
	if !testing.expect_value(t, error, .None) {return}
	defer json.destroy_value(value)
	actions: [dynamic]model.Card_Action
	playlist_actions(value, &actions)
	defer model.card_actions_destroy(&actions)
	if !testing.expect_value(t, len(actions), 2) {return}
	testing.expect_value(t, actions[0].label, "Remove from Watch later")
	testing.expect_value(t, actions[1].label, "Add to Favorites")
	for expected, i in ([2]struct {
			playlist, command, key, id: string,
		}{{"WL", "ACTION_REMOVE_VIDEO", "setVideoId", "set-fixture"}, {"PL-fixture", "ACTION_ADD_VIDEO", "addedVideoId", "DN953UW8iJ8"}}) {
		request, err := json.parse(actions[i].payload)
		if !testing.expect_value(t, err, .None) {continue}
		defer json.destroy_value(request)
		playlist, _ := field(request, "playlistId").(json.String)
		testing.expect_value(t, string(playlist), expected.playlist)
		edits, _ := field(request, "actions").(json.Array)
		if !testing.expect_value(t, len(edits), 1) {continue}
		edit, _ := edits[0].(json.Object)
		testing.expect_value(t, len(edit), 2)
		command, _ := field(edits[0], "action").(json.String)
		id, _ := field(edits[0], expected.key).(json.String)
		testing.expect_value(t, string(command), expected.command)
		testing.expect_value(t, string(id), expected.id)
	}
}
