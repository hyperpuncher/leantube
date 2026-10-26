import { expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";

import { $ } from "bun";

import {
	downloadThumbnail,
	searchSource,
	thumbnailUrl,
	videoData,
} from "../scripts/catalog";

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

test("max-resolution WebP covers are saved unchanged, with no smaller fallback", async () => {
	const directory = mkdtempSync("/tmp/leantube-cover-");
	try {
		const original = await Bun.file("tests/ui/cover.webp").bytes();
		const path = `${directory}/cover.webp`;
		let calls = 0;
		expect(
			await downloadThumbnail("aqz-KE-bpKQ", path, async (url) => {
				calls++;
				expect(url).toBe(
					"https://i.ytimg.com/vi_webp/aqz-KE-bpKQ/maxresdefault.webp",
				);
				return new Response(original);
			}),
		).toBe(true);
		expect(await Bun.file(path).bytes()).toEqual(original);
		for (const response of [
			new Response(null, { status: 404 }),
			new Response("not a WebP"),
		]) {
			expect(
				await downloadThumbnail(
					"aqz-KE-bpKQ",
					`${directory}/missing.webp`,
					async () => {
						calls++;
						return response;
					},
				),
			).toBe(false);
		}
		expect(calls).toBe(3);
		expect(await Bun.file(`${directory}/missing.webp`).exists()).toBe(false);
		expect(() => thumbnailUrl("../private")).toThrow();
	} finally {
		await $`trash -- ${directory}`.quiet();
	}
});

test("search text and video IDs are supported", () => {
	expect(searchSource("open films")).toBe("ytsearch24:open films");
	expect(searchSource("aqz-KE-bpKQ")).toBe(
		"https://www.youtube.com/watch?v=aqz-KE-bpKQ",
	);
});
