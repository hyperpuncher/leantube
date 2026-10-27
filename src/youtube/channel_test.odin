#+test
package youtube

import "../model"
import "core:strings"
import "core:testing"

CHANNEL_VIDEO :: `{"lockupViewModel":{"contentId":"DN953UW8iJ8","contentType":"LOCKUP_CONTENT_TYPE_VIDEO","metadata":{"lockupMetadataViewModel":{"title":{"content":"A channel video"},"metadata":{"contentMetadataViewModel":{"metadataRows":[{"metadataParts":[{"text":{"content":"1,234,567 views"}},{"text":{"content":"2 years ago"}}]}]}}}},"contentImage":{"thumbnailViewModel":{"image":{"sources":[{"url":"https://images.example/large","width":720},{"url":"https://images.example/small","width":320},{"url":"http://images.example/insecure","width":1080}]},"overlays":[{"thumbnailBottomOverlayViewModel":{"badges":[{"thumbnailBadgeViewModel":{"text":"CC"}},{"thumbnailBadgeViewModel":{"text":"15:51"}}]}}]}}}}`

@(test)
channel_reads_selected_tab_header_and_dropdown_sort_commands :: proc(t: ^testing.T) {
	catalog, error, visitor := parse_channel(
		`{"responseContext":{"visitorData":"channel-session"},
		"metadata":{"channelMetadataRenderer":{"title":"A channel","avatar":{"thumbnails":[{"url":"https://images.example/avatar","width":900}]}}},
		"header":{"pageHeaderRenderer":{"content":{"pageHeaderViewModel":{"metadata":{"contentMetadataViewModel":{"metadataRows":[{"metadataParts":[{"text":{"content":"@channel"}},{"text":{"content":"1M subscribers"}}]}]}}}}}},
		"contents":{"twoColumnBrowseResultsRenderer":{"tabs":[
		{"tabRenderer":{"title":"Home","content":{"videoRenderer":{"videoId":"C5WDBA2i9nE","title":{"simpleText":"Must not appear"},"lengthText":{"simpleText":"1:00"}}}}},
		{"tabRenderer":{"title":"Videos","selected":true,"endpoint":{"browseEndpoint":{"browseId":"UC-example","params":"videos-param"}},"content":{"richGridRenderer":{"header":{"chipBarViewModel":{"chips":[
		{"chipViewModel":{"text":"Latest","tapCommand":{"innertubeCommand":{"showSheetCommand":{"panelLoadingStrategy":{"inlineContent":{"sheetViewModel":{"content":{"listViewModel":{"items":[
		{"listItemViewModel":{"title":{"content":"Latest"},"isSelected":true,"rendererContext":{"commandContext":{"onTap":{"innertubeCommand":{"commandExecutorCommand":{"commands":[{"entityUpdateCommand":{}},{"continuationCommand":{"token":"newest-token"}}]}}}}}}},
		{"listItemViewModel":{"title":{"content":"Popular"},"rendererContext":{"commandContext":{"onTap":{"innertubeCommand":{"continuationCommand":{"token":"popular-token"}}}}}}},
		{"listItemViewModel":{"title":{"content":"Oldest"},"rendererContext":{"commandContext":{"onTap":{"innertubeCommand":{"continuationCommand":{"token":"oldest-token"}}}}}}}
		]}}}}}}}}}},
		{"chipViewModel":{"text":"Members only","tapCommand":{"innertubeCommand":{"continuationCommand":{"token":"not-a-sort"}}}}}
		]}},"contents":[` +
		CHANNEL_VIDEO +
		`,{"continuationItemRenderer":{"continuationEndpoint":{"continuationCommand":{"token":"next-channel-page"}}}}]}}}},
		{"tabRenderer":{"title":"Live","endpoint":{"browseEndpoint":{"browseId":"UC-example","params":"live-param"}}}},
		{"tabRenderer":{"title":"Playlists","endpoint":{"browseEndpoint":{"browseId":"UC-example","params":"playlists-param"}}}}
		]}}}`,
		"UC-example",
	)
	defer model.catalog_destroy(&catalog)
	defer delete(visitor)
	if !testing.expect_value(t, error, .None) {return}
	testing.expect_value(t, catalog.channel.title, "A channel")
	testing.expect_value(t, catalog.channel.meta, "@channel · 1M subscribers")
	testing.expect_value(t, catalog.channel.avatar_url, "https://images.example/avatar")
	if !testing.expect_value(t, len(catalog.channel.tabs), 3) {return}
	testing.expect_value(t, catalog.channel.tabs[0].params, "videos-param")
	testing.expect(t, catalog.channel.tabs[0].selected)
	testing.expect_value(t, catalog.channel.tabs[1].params, "live-param")
	testing.expect_value(t, catalog.channel.tabs[2].params, "playlists-param")
	if !testing.expect_value(t, len(catalog.channel.sorts), 3) {return}
	for expected, i in ([]struct {
			label, token: string,
		}{{"Newest", "newest-token"}, {"Popular", "popular-token"}, {"Oldest", "oldest-token"}}) {
		testing.expect_value(t, catalog.channel.sorts[i].label, expected.label)
		testing.expect_value(t, catalog.channel.sorts[i].token, expected.token)
		testing.expect_value(t, catalog.channel.sorts[i].selected, i == 0)
	}
	if !testing.expect_value(t, len(catalog.videos), 1) {return}
	testing.expect_value(t, catalog.videos[0].id, "DN953UW8iJ8")
	testing.expect_value(t, catalog.videos[0].duration_ms, f64(951000))
	testing.expect_value(t, catalog.videos[0].thumbnail_url, "https://images.example/large")
	testing.expect_value(t, catalog.videos[0].meta, "1.2M views · 2 years ago")
	testing.expect_value(t, catalog.continuation, "next-channel-page")
}

@(test)
channel_sort_reloads_use_feed_continuation_not_a_filter_token :: proc(t: ^testing.T) {
	catalog, error, visitor := parse_channel(
		`{"onResponseReceivedActions":[
		{"reloadContinuationItemsCommand":{"targetId":"feed-filter-chip-bar","continuationItems":[{"chipBarViewModel":{"chips":[
		{"chipViewModel":{"text":"Latest","selected":false,"tapCommand":{"innertubeCommand":{"continuationCommand":{"token":"newest-token"}}}}},
		{"chipViewModel":{"text":"Popular","selected":true,"tapCommand":{"innertubeCommand":{"continuationCommand":{"token":"popular-token"}}}}},
		{"chipViewModel":{"text":"Oldest","selected":false,"tapCommand":{"innertubeCommand":{"continuationCommand":{"token":"oldest-token"}}}}}
		]}}]}},
		{"reloadContinuationItemsCommand":{"targetId":"channel-feed","continuationItems":[` +
		CHANNEL_VIDEO +
		`,{"continuationItemRenderer":{"continuationEndpoint":{"continuationCommand":{"token":"popular-next-page"}}}}]}}
		]}`,
		"UC-example",
	)
	defer model.catalog_destroy(&catalog)
	defer delete(visitor)
	if !testing.expect_value(t, error, .None) {return}
	testing.expect_value(t, len(catalog.videos), 1)
	testing.expect_value(t, catalog.continuation, "popular-next-page")
	if !testing.expect_value(t, len(catalog.channel.sorts), 3) {return}
	testing.expect(t, catalog.channel.sorts[1].selected)
	testing.expect_value(t, catalog.channel.sorts[1].token, "popular-token")
}

@(test)
channel_playlist_lockups_open_a_playlist_instead_of_playing_the_id :: proc(t: ^testing.T) {
	catalog, error, visitor := parse_channel(
		`{"onResponseReceivedActions":[{"appendContinuationItemsAction":{"continuationItems":[
		{"lockupViewModel":{"contentId":"PL-example","contentType":"LOCKUP_CONTENT_TYPE_PLAYLIST","metadata":{"lockupMetadataViewModel":{"title":{"content":"A playlist"}}},"contentImage":{"collectionThumbnailViewModel":{"primaryThumbnail":{"thumbnailViewModel":{"image":{"sources":[{"url":"https://images.example/playlist","width":480}]},"overlays":[{"thumbnailBottomOverlayViewModel":{"badges":[{"thumbnailBadgeViewModel":{"text":"12 videos"}}]}}]}}}}}}
		]}}]}`,
		"UC-example",
	)
	defer model.catalog_destroy(&catalog)
	defer delete(visitor)
	if !testing.expect_value(t, error, .None) {return}
	if !testing.expect_value(t, len(catalog.videos), 1) {return}
	testing.expect_value(t, catalog.videos[0].id, "")
	testing.expect_value(t, catalog.videos[0].browse_id, "VLPL-example")
	testing.expect_value(t, catalog.videos[0].duration_label, "12 videos")
	testing.expect_value(t, catalog.videos[0].thumbnail_url, "https://images.example/playlist")
}

@(test)
web_search_byline_exposes_channel_navigation_without_duplicate_actions :: proc(t: ^testing.T) {
	for menu in ([]string{"", `,"menu":{"menuRenderer":{"items":[{"menuNavigationItemRenderer":{"text":{"simpleText":"Go to channel"},"navigationEndpoint":{"browseEndpoint":{"browseId":"UC-example"}}}}]}}`}) {
		data := strings.concatenate(
			{
				`{"contents":{"twoColumnSearchResultsRenderer":{"primaryContents":{"items":[
			{"videoRenderer":{"videoId":"DN953UW8iJ8","title":{"simpleText":"Video"},"lengthText":{"simpleText":"1:00"},"ownerText":{"runs":[{"text":"A channel","navigationEndpoint":{"browseEndpoint":{"browseId":"UC-example"}}}]}`,
				menu,
				`}}]}}}}`,
			},
		)
		defer delete(data)
		catalog, error, visitor := parse_search(data, "query")
		defer model.catalog_destroy(&catalog)
		defer delete(visitor)
		if !testing.expect_value(t, error, .None) {return}
		if !testing.expect_value(t, len(catalog.videos), 1) {return}
		if !testing.expect_value(t, len(catalog.videos[0].actions), 1) {return}
		testing.expect_value(t, catalog.videos[0].actions[0].kind, .Browse)
		testing.expect_value(t, catalog.videos[0].actions[0].target, "UC-example")
	}
}
