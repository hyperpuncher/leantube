import { existsSync, mkdtempSync } from "node:fs";

import { $ } from "bun";

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
		: `ytsearch6:${query}`;
}

async function prepare(query: string) {
	const source = searchSource(query);
	const { id: appId } = await Bun.file("app/appinfo.json").json();
	const stage = mkdtempSync("/tmp/leantube-catalog-");
	try {
		// Quiet output is essential: extractor errors can contain signed URLs.
		const { stdout } =
			await $`yt-dlp --quiet --no-warnings --ignore-errors --skip-download --dump-json --playlist-end 6 --format 18 -- ${source}`
				.quiet()
				.nothrow();
		const videos = [];
		for (const line of stdout.toString().trim().split("\n").filter(Boolean)) {
			const info: VideoInfo = JSON.parse(line);
			const data = videoData(info, appId);
			if (!data || videos.length === 6) continue;
			const index = videos.length;
			await Bun.write(`${stage}/${index}.json`, JSON.stringify(data.request));
			if (info.thumbnail) {
				try {
					const image = await fetch(info.thumbnail, {
						signal: AbortSignal.timeout(15000),
					});
					if (image.ok) {
						const bytes = await image.arrayBuffer();
						await $`ffmpeg -hide_banner -loglevel error -y -i pipe:0 -vf scale=256:144:force_original_aspect_ratio=increase,crop=256:144 -frames:v 1 -pix_fmt bgr24 ${stage}/${index}.bmp < ${bytes}`
							.quiet()
							.nothrow();
					}
				} catch {
					/* A missing thumbnail does not prevent playback. */
				}
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
