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

test("thumbnail fallback prefers size, then WebP, and preserves original bytes", async () => {
	const directory = mkdtempSync("/tmp/leantube-cover-");
	try {
		const originals = {
			webp: await Bun.file("tests/ui/cover.webp").bytes(),
			jpg: await Bun.file("tests/ui/cover.jpg").bytes(),
		};
		const cases = [
			{
				variant: "vi_webp/aqz-KE-bpKQ/maxresdefault.webp",
				extension: "webp",
				calls: 1,
			},
			{ variant: "vi/aqz-KE-bpKQ/maxresdefault.jpg", extension: "jpg", calls: 2 },
			{
				variant: "vi_webp/aqz-KE-bpKQ/sddefault.webp",
				extension: "webp",
				calls: 5,
			},
			{ variant: "vi/aqz-KE-bpKQ/hqdefault.jpg", extension: "jpg", calls: 8 },
		] as const;
		for (const entry of cases) {
			const prefix = `${directory}/${entry.calls}`;
			const calls: string[] = [];
			expect(
				await downloadThumbnail("aqz-KE-bpKQ", prefix, async (url) => {
					calls.push(url);
					return url === `https://i.ytimg.com/${entry.variant}`
						? new Response(originals[entry.extension])
						: new Response(null, { status: 404 });
				}),
			).toBe(true);
			expect(calls[0]).toBe(
				"https://i.ytimg.com/vi_webp/aqz-KE-bpKQ/maxresdefault.webp",
			);
			expect(calls.length).toBe(entry.calls);
			expect(await Bun.file(`${prefix}.${entry.extension}`).bytes()).toEqual(
				originals[entry.extension],
			);
		}
		expect(() => thumbnailUrl("../private")).toThrow();
	} finally {
		await $`trash -- ${directory}`.quiet();
	}
});

test("missing thumbnails use no file; server failures and invalid data do not trigger smaller fallbacks", async () => {
	const directory = mkdtempSync("/tmp/leantube-cover-");
	try {
		for (const status of [404, 503, 200]) {
			// YouTube can send valid image bytes with a 404 status.
			const body =
				status === 404
					? await Bun.file("tests/ui/cover.webp").bytes()
					: "not an image";
			let calls = 0;
			const prefix = `${directory}/${status}`;
			expect(
				await downloadThumbnail("aqz-KE-bpKQ", prefix, async () => {
					calls++;
					return new Response(body, { status });
				}),
			).toBe(false);
			expect(calls).toBe(status === 404 ? 8 : 1);
			expect(await Bun.file(`${prefix}.webp`).exists()).toBe(false);
			expect(await Bun.file(`${prefix}.jpg`).exists()).toBe(false);
		}
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
