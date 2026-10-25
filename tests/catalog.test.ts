import { expect, test } from "bun:test";

import { searchSource, videoData } from "../scripts/catalog";

test("catalog metadata does not contain the private stream or thumbnail URL", () => {
	const data = videoData(
		{
			id: "aqz-KE-bpKQ",
			title: "Big Buck Bunny",
			channel: "Blender",
			duration: 634.578,
			url: "private-stream",
			thumbnail: "private-thumbnail",
		},
		"prototype",
	);
	expect(data?.metadata).toEqual({
		id: "aqz-KE-bpKQ",
		title: "Big Buck Bunny",
		channel: "Blender",
		duration_ms: 634578,
	});
	expect(data?.request).toEqual({
		uri: "private-stream",
		type: "media",
		payload: { option: { appId: "prototype" } },
	});
	expect(JSON.stringify(data?.metadata)).not.toContain("private-");
});

test("missing streams, invalid IDs, and live entries cannot become cards", () => {
	for (const info of [
		{},
		{ id: "../private", title: "x", url: "private-stream" },
		{ id: "aqz-KE-bpKQ", title: "x", url: "private-stream", is_live: true },
	])
		expect(videoData(info, "prototype")).toBeNull();
});

test("search text and video IDs are supported", () => {
	expect(searchSource("open films")).toBe("ytsearch6:open films");
	expect(searchSource("aqz-KE-bpKQ")).toBe(
		"https://www.youtube.com/watch?v=aqz-KE-bpKQ",
	);
});
