import { existsSync, mkdtempSync } from "node:fs";

import { $ } from "bun";

export const CATALOG_LIMIT = 24;

export type VideoInfo = {
	id?: string;
	title?: string;
	channel?: string;
	uploader?: string;
	duration?: number;
	url?: string;
	thumbnail?: string;
	is_live?: boolean;
};

// Public card metadata must not include the private playback request.
export function videoData(info: VideoInfo, appId: string) {
	if (
		!info.id ||
		!/^[\w-]{11}$/.test(info.id) ||
		!info.title ||
		!info.url ||
		info.is_live
	)
		return null;
	return {
		metadata: {
			id: info.id,
			title: info.title,
			channel: info.channel || info.uploader || "unknown channel",
			duration_ms: Math.max(0, Math.round((info.duration || 0) * 1000)),
		},
		request: { uri: info.url, type: "media", payload: { option: { appId } } },
	};
}

export function searchSource(query: string) {
	return /^[\w-]{11}$/.test(query)
		? `https://www.youtube.com/watch?v=${query}`
		: `ytsearch${CATALOG_LIMIT}:${query}`;
}

export function thumbnailUrl(id: string) {
	if (!/^[\w-]{11}$/.test(id)) throw new Error("invalid video ID");
	return `https://i.ytimg.com/vi_webp/${id}/maxresdefault.webp`;
}

export async function downloadThumbnail(
	id: string,
	path: string,
	fetchImage: (url: string, options: RequestInit) => Promise<Response> = fetch,
) {
	const response = await fetchImage(thumbnailUrl(id), {
		signal: AbortSignal.timeout(15000),
	});
	if (!response.ok) return false;
	const bytes = new Uint8Array(await response.arrayBuffer());
	if (
		bytes.length < 12 ||
		new TextDecoder().decode(bytes.subarray(0, 4)) !== "RIFF" ||
		new TextDecoder().decode(bytes.subarray(8, 12)) !== "WEBP"
	)
		return false;
	await Bun.write(path, bytes);
	return true;
}

async function prepare(query: string) {
	const source = searchSource(query);
	const { id: appId } = await Bun.file("app/appinfo.json").json();
	const stage = mkdtempSync("/tmp/leantube-catalog-");
	try {
		// Quiet output is essential: extractor errors can contain signed URLs.
		const { stdout } =
			await $`yt-dlp --quiet --no-warnings --ignore-errors --skip-download --dump-json --playlist-end ${CATALOG_LIMIT} --format 18 -- ${source}`
				.quiet()
				.nothrow();
		const videos = [];
		for (const line of stdout.toString().trim().split("\n").filter(Boolean)) {
			const info: VideoInfo = JSON.parse(line);
			const data = videoData(info, appId);
			if (!data || videos.length === CATALOG_LIMIT) continue;
			const index = videos.length;
			await Bun.write(`${stage}/${index}.json`, JSON.stringify(data.request));
			try {
				await downloadThumbnail(data.metadata.id, `${stage}/${index}.webp`);
			} catch {
				/* A missing max-resolution cover uses the UI placeholder. */
			}
			videos.push(data.metadata);
		}
		if (!videos.length) throw new Error("no playable videos");
		await Bun.write(
			`${stage}/catalog.json`,
			JSON.stringify({ query, videos }, null, "\t") + "\n",
		);
		await $`mkdir -p build`.quiet();
		if (existsSync("build/catalog")) await $`trash -- build/catalog`.quiet();
		await $`cp -R ${stage} build/catalog`.quiet();
		console.log(`prepared ${videos.length} videos with private stream requests`);
	} finally {
		await $`trash -- ${stage}`.quiet();
	}
}

if (import.meta.main) {
	process.umask(0o077);
	try {
		await prepare(process.argv[2]?.trim() || "Blender open movies");
	} catch {
		console.error(
			"could not prepare videos; private request details were not logged",
		);
		process.exitCode = 1;
	}
}
