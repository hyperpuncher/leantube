import { mkdtemp, readFile, rmdir, unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Keep FFmpeg diagnostics in memory. Errors can contain signed media URLs.
async function ffmpeg(args: string[]) {
	const child = Bun.spawn(["ffmpeg", "-hide_banner", "-loglevel", "error", ...args], {
		stdout: "ignore",
		stderr: "pipe",
	});
	await new Response(child.stderr).arrayBuffer();
	if ((await child.exited) !== 0) throw Error("FFmpeg reference command failed");
}

const [command, ...args] = Bun.argv.slice(2);
if (command === "fetch") {
	const [playerPath, startText, durationText, output, itagText] = args;
	const itag = itagText === undefined ? undefined : Number(itagText);
	const start = Number(startText);
	const duration = Number(durationText);
	if (
		!playerPath ||
		!output ||
		!Number.isFinite(start) ||
		start < 0 ||
		!(duration > 0) ||
		(itag !== undefined && (!Number.isSafeInteger(itag) || itag <= 0))
	) {
		throw Error(
			"expected: fetch PLAYER_JSON START_SECONDS DURATION_SECONDS OUTPUT_YUV [ITAG]",
		);
	}
	const player = await Bun.file(playerPath).json();
	const video = player.streamingData?.adaptiveFormats?.find(
		(format: { itag?: number; url?: string }) =>
			(itag === undefined
				? format.itag === 313 || format.itag === 315
				: format.itag === itag) && format.url,
	);
	if (!video || !video.url.startsWith("https://"))
		throw Error("reference stream missing");
	await ffmpeg([
		"-request_size",
		"1048576",
		"-initial_request_size",
		"1048576",
		"-ss",
		String(start),
		"-i",
		video.url,
		"-t",
		String(duration),
		"-map",
		"0:v:0",
		"-an",
		"-vf",
		"fps=10,scale=320:180:flags=area,format=yuv420p",
		"-f",
		"rawvideo",
		"-y",
		output,
	]);
	console.log(
		JSON.stringify({
			start_s: start,
			duration_s: duration,
			fps: 10,
			width: 320,
			height: 180,
		}),
	);
} else if (command === "match") {
	const [reference, baseText, picture] = args;
	const base = Number(baseText);
	if (!reference || !picture || !Number.isFinite(base)) {
		throw Error("expected: match REFERENCE_YUV SOURCE_START_SECONDS PICTURE_PNG");
	}
	const directory = await mkdtemp(join(tmpdir(), "leantube-match-"));
	const stats = join(directory, "stats");
	try {
		await ffmpeg([
			"-f",
			"rawvideo",
			"-pixel_format",
			"yuv420p",
			"-video_size",
			"320x180",
			"-framerate",
			"10",
			"-i",
			reference,
			"-framerate",
			"10",
			"-loop",
			"1",
			"-i",
			picture,
			"-filter_complex",
			`[1:v]scale=320:180:flags=area,format=yuv420p[shot];[0:v][shot]ssim=stats_file=${stats}:shortest=1[out]`,
			"-map",
			"[out]",
			"-an",
			"-f",
			"null",
			"-",
		]);
		let best = { source_s: base, ssim: -1 };
		for (const line of (await readFile(stats, "utf8")).split("\n")) {
			const match = line.match(/n:(\d+).*All:([0-9.]+)/);
			if (match && Number(match[2]) > best.ssim) {
				best = {
					source_s: base + (Number(match[1]) - 1) / 10,
					ssim: Number(match[2]),
				};
			}
		}
		if (best.ssim < 0) throw Error("no picture comparison results");
		console.log(JSON.stringify(best));
	} finally {
		await unlink(stats).catch(() => {});
		await rmdir(directory);
	}
} else {
	throw Error("expected fetch or match");
}
