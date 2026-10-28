#+test
package main

import "./model"
import "core:strings"
import "core:sync/chan"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
subscription_sort_keeps_loaded_and_pending_covers_with_their_videos :: proc(t: ^testing.T) {
	output := sdl.CreateSurface(160, 120, .RGBA32)
	if !testing.expect(t, output != nil) {return}
	defer sdl.DestroySurface(output)
	renderer := sdl.CreateSoftwareRenderer(output)
	if !testing.expect(t, renderer != nil) {return}
	defer sdl.DestroyRenderer(renderer)
	network_results, _ = chan.create(chan.Chan(Network_Result), 2, context.allocator)
	defer {
		stop_network(); clear_catalog()
		delete(browse_id); browse_id = ""
		page = 0; selected = 0; search_loading = false
	}
	page = 4
	browse_id = strings.clone("FEsubscriptions")
	first := Network_Result {
		kind = .Catalog,
		page = page,
	}
	append(
		&first.catalog.videos,
		model.Video{id = strings.clone("older"), published_age_s = 900, cover_index = 0},
		model.Video{id = strings.clone("newer"), published_age_s = 100, cover_index = 1},
	)
	chan.send(network_results, first)
	poll_network(renderer)
	testing.expect_value(t, catalog.videos[0].id, "newer")
	testing.expect_value(t, catalog.videos[1].id, "older")
	testing.expect_value(t, selected, 0)

	// The first reply belongs to the second displayed card after sorting.
	chan.send(
		network_results,
		Network_Result {
			kind = .Cover,
			page = page,
			index = 0,
			surface = sdl.CreateSurface(31, 17, .RGBA32),
		},
	)
	poll_network(renderer)
	older_texture := textures[1]
	if !testing.expect(t, older_texture != nil) {return}
	testing.expect(t, textures[0] == nil)

	// A newer continuation must move the loaded cover and preserve focus.
	selected = 1
	next := Network_Result {
		kind   = .Catalog,
		page   = page,
		append = true,
	}
	append(
		&next.catalog.videos,
		model.Video{id = strings.clone("newest"), published_age_s = 0, cover_index = 2},
	)
	chan.send(network_results, next)
	poll_network(renderer)
	testing.expect_value(t, catalog.videos[0].id, "newest")
	testing.expect_value(t, catalog.videos[1].id, "newer")
	testing.expect_value(t, catalog.videos[2].id, "older")
	testing.expect_value(t, textures[2], older_texture)
	testing.expect_value(t, selected, 2)
	testing.expect(t, textures[0] == nil && textures[1] == nil)

	// A delayed first-page cover and a new-page cover arrive out of order.
	chan.send(
		network_results,
		Network_Result {
			kind = .Cover,
			page = page,
			index = 2,
			surface = sdl.CreateSurface(53, 29, .RGBA32),
		},
	)
	chan.send(
		network_results,
		Network_Result {
			kind = .Cover,
			page = page,
			index = 1,
			surface = sdl.CreateSurface(41, 23, .RGBA32),
		},
	)
	poll_network(renderer)
	for expected, i in ([][2]f32{{53, 29}, {41, 23}, {31, 17}}) {
		width, height: f32
		if !testing.expect(t, textures[i] != nil) {return}
		testing.expect(t, sdl.GetTextureSize(textures[i], &width, &height))
		testing.expect_value(t, width, expected[0])
		testing.expect_value(t, height, expected[1])
	}
	latest_texture := textures[0]
	chan.send(
		network_results,
		Network_Result {
			kind = .Cover,
			page = page - 1,
			index = 2,
			surface = sdl.CreateSurface(10, 10, .RGBA32),
		},
	)
	chan.send(
		network_results,
		Network_Result {
			kind = .Cover,
			page = page,
			index = 99,
			surface = sdl.CreateSurface(10, 10, .RGBA32),
		},
	)
	poll_network(renderer)
	testing.expect_value(t, textures[0], latest_texture)
	testing.expect_value(t, textures[2], older_texture)
}
