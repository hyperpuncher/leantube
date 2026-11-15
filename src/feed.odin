package main

import clay "../vendor/clay"
import "./model"
import "core:strings"
import sdl "vendor:sdl3"

// Keep image slot IDs stable for replies that are still in flight.
remove_catalog_card :: proc(cover: int) {
	for &video, index in catalog.videos {
		if video.cover_index != cover {continue}
		model.video_destroy(&video)
		ordered_remove(&catalog.videos, index)
		if selected > index {selected -= 1}
		selected = clamp(selected, 0, max(0, len(catalog.videos) - 1))
		if cover < len(textures) {sdl.DestroyTexture(textures[cover]); textures[cover] = nil}
		if cover <
		   len(card_avatars) {sdl.DestroyTexture(card_avatars[cover]); card_avatars[cover] = nil}
		if cover < len(card_labels) {
			label := &card_labels[cover]
			delete(label.title); delete(label.channel); delete(label.meta)
			label^ = {}
		}
		catalog_revision += 1
		dirty = true
		return
	}
}

clear_catalog :: proc(keep_channel: bool = false) {
	labels_release()
	clear_player_channel()
	close_card_menu()
	catalog_revision += 1
	for &texture in textures {
		if texture != nil {sdl.DestroyTexture(texture); texture = nil}
	}
	delete(textures); textures = nil
	for texture in card_avatars {if texture != nil {sdl.DestroyTexture(texture)}}
	delete(card_avatars); card_avatars = nil
	channel: model.Channel
	if keep_channel {channel = catalog.channel; catalog.channel = {}}
	model.catalog_destroy(&catalog)
	catalog.channel = channel
	if !keep_channel &&
	   channel_avatar != nil {sdl.DestroyTexture(channel_avatar); channel_avatar = nil}
}
// A new feed starts at its first card, with no stale focus or notice.
begin_feed :: proc() {
	channel_focus, rail_focus = false, false
	restore_selected = -1
	page += 1
	selected = 0
	library_focus_pending = true
	if scroll := clay.GetScrollContainerData(clay.ID("library-scroll")); scroll.found {
		scroll.scrollPosition^ = {}
	}
	notice = ""
}

request_feed :: proc(request: Network_Request) {
	search_loading = true
	dirty = true
	if !submit_network(request) {
		search_loading = false
		show_notice("Network unavailable")
	}
}

start_browse :: proc(id: string, params: string = "", filter: string = "", remember: bool = true) {
	owned, owned_params, owned_filter :=
		strings.clone(id), strings.clone(params), strings.clone(filter)
	if remember && id != browse_id && (browse_id != "" || catalog.query != "") {remember_browse()}
	keep_channel := id == browse_id && catalog.channel.id == id
	delete(browse_id); delete(browse_params); delete(browse_filter)
	browse_id, browse_params, browse_filter = owned, owned_params, owned_filter
	clear_catalog(keep_channel)
	begin_feed()
	request_feed(
		{
			kind = .Browse,
			page = page,
			text = strings.clone(browse_id),
			params = strings.clone(browse_params),
			filter = strings.clone(browse_filter),
		},
	)
}

load_more :: proc() {
	if search_loading ||
	   catalog.continuation == "" ||
	   (browse_id == "" && catalog.query == "") {return}
	request_feed(
		{
			kind = browse_id == "" ? .Search : .Browse,
			page = page,
			text = strings.clone(browse_id == "" ? catalog.query : browse_id),
			continuation = strings.clone(catalog.continuation),
		},
	)
}

open_selected :: proc() {
	if selected < 0 || selected >= len(catalog.videos) {return}
	card := catalog.videos[selected]
	if card.browse_id != "" {
		start_browse(card.browse_id)
	} else {start_video()}
}

start_search :: proc(query: string = "Linus Tech Tips", keep_history: bool = false) {
	clean_query := strings.trim_space(query)
	if clean_query == "" || len(clean_query) > 512 {return}
	// Clone before clearing the old page; query may point into its text.
	owned := strings.clone(clean_query)
	if !keep_history {clear_browse_history()}
	delete(browse_id); browse_id = ""
	delete(browse_params); browse_params = ""
	delete(browse_filter); browse_filter = ""
	clear_catalog()
	catalog.query = strings.clone(owned)
	rail_active = .Search
	begin_feed()
	request_feed({kind = .Search, page = page, text = owned})
}
// Cover replies use the original feed position, not the sorted grid position.
sort_subscriptions :: proc(preserve_selection: bool) {
	if len(catalog.videos) == 0 {return}
	selected_cover := preserve_selection ? catalog.videos[selected].cover_index : -1
	model.sort_latest(catalog.videos[:])
	for video, i in catalog.videos {
		if video.cover_index == selected_cover {selected = i}
	}
}

apply_catalog :: proc(result: ^Network_Result) {
	first_cover := result.append ? len(textures) : 0
	next_cover := first_cover
	search_loading = false
	if result.error != .None {show_notice("Could not load this page"); return}
	if browse_id == "VLWL" {
		for &video in result.catalog.videos {video.watch_later = .Present}
	}
	if result.append {
		seen := make(map[[2]string]bool, len(catalog.videos) + len(result.catalog.videos))
		defer delete(seen)
		for video in catalog.videos {seen[{video.id, video.browse_id}] = true}
		for &video in result.catalog.videos {
			key := [2]string{video.id, video.browse_id}
			if key != ([2]string{}) && seen[key] {model.video_destroy(&video); continue}
			seen[key] = true
			video.cover_index = next_cover
			next_cover += 1
			append(&catalog.videos, video)
		}
		clear(&result.catalog.videos)
		delete(catalog.continuation)
		catalog.continuation = result.catalog.continuation
		result.catalog.continuation = ""
	} else {
		next_cover = len(result.catalog.videos)
		same_channel :=
			result.catalog.channel.id != "" && result.catalog.channel.id == catalog.channel.id
		if same_channel &&
		   channel_avatar != nil &&
		   result.catalog.channel.avatar_url != "" &&
		   result.catalog.channel.avatar_url != catalog.channel.avatar_url {
			sdl.DestroyTexture(channel_avatar)
			channel_avatar = nil
		}
		if same_channel && result.catalog.channel.title == "" {
			sorts := result.catalog.channel.sorts
			result.catalog.channel.sorts = nil
			model.channel_destroy(&result.catalog.channel)
			result.catalog.channel = catalog.channel
			catalog.channel = {}
			if len(sorts) > 0 {
				model.channel_options_destroy(&result.catalog.channel.sorts)
				result.catalog.channel.sorts = sorts
			}
		}
		clear_catalog(same_channel)
		model.channel_destroy(&catalog.channel)
		catalog = result.catalog; result.catalog = {}
		if restore_selected >= 0 {
			selected = clamp(restore_selected, 0, max(0, len(catalog.videos) - 1))
			restore_selected = -1
		}
	}
	resize(&textures, next_cover)
	resize(&card_avatars, next_cover)
	if browse_id == "FEsubscriptions" {sort_subscriptions(result.append)}
	queue_catalog_images(first_cover)
	catalog_revision += 1
	notice = ""
	if !result.append {library_focus_pending = true}
	dirty = true
}
