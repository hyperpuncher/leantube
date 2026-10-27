package model

Channel_Option :: struct {
	label, params, token: string,
	selected:             bool,
}

Channel :: struct {
	id, title, meta, avatar_url: string,
	tabs, sorts:                 [dynamic]Channel_Option,
}

channel_options_destroy :: proc(options: ^[dynamic]Channel_Option) {
	for option in options^ {delete(option.label); delete(option.params); delete(option.token)}
	delete(options^)
	options^ = nil
}

channel_destroy :: proc(channel: ^Channel) {
	delete(channel.id); delete(channel.title); delete(channel.meta); delete(channel.avatar_url)
	channel_options_destroy(&channel.tabs)
	channel_options_destroy(&channel.sorts)
	channel^ = {}
}
