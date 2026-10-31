import { mkdir, rename, writeFile } from "node:fs/promises";

const playerPath = Bun.argv[2];
if (!playerPath) throw Error("expected a private player response");
const directory = "build/playback-bench/fixture";
await mkdir(directory, { recursive: true, mode: 0o700 });
const videoPath = `${directory}/video.webm`;
const audioPath = `${directory}/audio.m4a`;
interface Probe {
	format: { duration: string };
	streams: { width?: number; height?: number; r_frame_rate?: string }[];
}
async function probe(path: string): Promise<Probe | undefined> {
	if (!(await Bun.file(path).exists())) return undefined;
	const child = Bun.spawn(
		["ffprobe", "-v", "quiet", "-show_streams", "-show_format", "-of", "json", path],
		{ stdout: "pipe", stderr: "ignore" },
	);
	const text = await new Response(child.stdout).text();
	if ((await child.exited) !== 0) return undefined;
	return JSON.parse(text) as Probe;
}
const p = await Bun.file(playerPath).json();
const formats = p.streamingData.adaptiveFormats;
const video = formats
	.filter((f: any) => f.url && f.height === 2160 && f.mimeType.includes('codecs="vp9'))
	.sort((a: any, b: any) => b.bitrate - a.bitrate)[0];
const audio = formats.find((f: any) => f.url && f.itag === 140 && !f.isDrc && !f.xtags);
if (!video || !audio) throw Error("fixture sources missing");
for (const [format, path, map] of [
	[video, videoPath, "0:v:0"],
	[audio, audioPath, "0:a:0"],
] as const) {
	const existing = await probe(path);
	if (existing && Number(existing.format.duration) >= 59.8) continue;
	const partial = path.endsWith(".webm")
		? `${directory}/video.part.webm`
		: `${directory}/audio.part.m4a`;
	const child = Bun.spawn(
		[
			"ffmpeg",
			"-hide_banner",
			"-loglevel",
			"error",
			"-request_size",
			"1048576",
			"-initial_request_size",
			"1048576",
			"-i",
			format.url,
			"-t",
			"60",
			"-map",
			map,
			"-c",
			"copy",
			...(map === "0:a:0" ? ["-movflags", "+faststart"] : []),
			"-y",
			partial,
		],
		{ stdout: "ignore", stderr: "pipe" },
	);
	// Errors can contain signed URLs. Validate output before publishing it.
	await new Response(child.stderr).arrayBuffer();
	const result = await child.exited;
	const metadata = await probe(partial);
	if (result !== 0 || !metadata || !(Number(metadata.format.duration) >= 59.8))
		throw Error("fixture remux did not produce 60 seconds");
	if (await Bun.file(path).exists())
		await rename(path, `${path}.invalid-${Date.now()}`);
	await rename(partial, path);
}
const data = await probe(videoPath);
const stream = data?.streams[0];
if (!stream?.width || !stream.height) throw Error("fixture has no video stream");
const connection = Bun.spawn(
	["ssh", process.env.TV_HOST ?? "tv", 'printf "%s" "$SSH_CONNECTION"'],
	{ stdout: "pipe", stderr: "pipe" },
);
const address = (await new Response(connection.stdout).text()).trim().split(/\s+/)[0];
await new Response(connection.stderr).arrayBuffer();
if ((await connection.exited) !== 0 || !address)
	throw Error("fixture interface unavailable");
const key = crypto.randomUUID();
const files = new Map([
	["video.webm", videoPath],
	["audio.m4a", audioPath],
]);
const server = Bun.serve({
	hostname: address,
	port: 0,
	fetch(request) {
		const prefix = `/${key}/`;
		const path = new URL(request.url).pathname;
		const filePath = path.startsWith(prefix)
			? files.get(path.slice(prefix.length))
			: undefined;
		if (!filePath) return new Response(null, { status: 404 });
		const file = Bun.file(filePath);
		const range = request.headers.get("range");
		let start = 0,
			end = file.size - 1,
			status = 200;
		const headers: Record<string, string> = {
			"content-type": filePath.endsWith(".webm") ? "video/webm" : "audio/mp4",
			"accept-ranges": "bytes",
			"cache-control": "no-store",
		};
		if (range) {
			const match = range.match(/^bytes=(\d+)-(\d*)$/);
			if (!match) return new Response(null, { status: 416 });
			start = Number(match[1]);
			end = match[2] ? Math.min(Number(match[2]), end) : end;
			if (start > end)
				return new Response(null, {
					status: 416,
					headers: { "content-range": `bytes */${file.size}` },
				});
			status = 206;
			headers["content-range"] = `bytes ${start}-${end}/${file.size}`;
		}
		headers["content-length"] = String(end - start + 1);
		return new Response(
			request.method === "HEAD" ? null : file.slice(start, end + 1),
			{ status, headers },
		);
	},
});
const base = `http://${address}:${server.port}/${key}/`;
await writeFile(
	`${directory}/player.json`,
	JSON.stringify({
		fixture: true,
		streamingData: {
			adaptiveFormats: [
				{
					url: base + "video.webm",
					height: stream.height,
					bitrate: 1,
					mimeType: 'video/webm; codecs="vp9"',
				},
				{
					url: base + "audio.m4a",
					bitrate: 1,
					mimeType: 'audio/mp4; codecs="mp4a.40.2"',
				},
			],
		},
	}),
	{ mode: 0o600 },
);
await writeFile(`${directory}/server.pid`, String(process.pid), { mode: 0o600 });
console.log(
	JSON.stringify({
		fixture_ready: true,
		width: stream.width,
		height: stream.height,
		frame_rate: stream.r_frame_rate,
		transcoding: false,
	}),
);
for (const signal of ["SIGINT", "SIGTERM"] as const)
	process.once(signal, () => {
		server.stop(true);
		process.exit(0);
	});
