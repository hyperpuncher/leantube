import { $ } from "bun";

// Generate a small AAC fixture in host RAM. No media is copied to the TV.
const encoder = Bun.spawn(
	[
		"ffmpeg",
		"-v",
		"error",
		"-f",
		"lavfi",
		"-i",
		"anullsrc=r=44100:cl=stereo",
		"-t",
		"22",
		"-c:a",
		"aac",
		"-movflags",
		"frag_keyframe+empty_moov",
		"-f",
		"mp4",
		"pipe:1",
	],
	{ stdout: "pipe", stderr: "pipe" },
);
const audio = await new Response(encoder.stdout).arrayBuffer();
await new Response(encoder.stderr).arrayBuffer();
if (await encoder.exited) throw Error("could not create the host AAC fixture");
const videoEncoder = Bun.spawn(
	[
		"ffmpeg",
		"-v",
		"error",
		"-f",
		"lavfi",
		"-i",
		"color=s=32x32:r=5",
		"-t",
		"22",
		"-c:v",
		"libvpx-vp9",
		"-g",
		"5",
		"-f",
		"webm",
		"pipe:1",
	],
	{ stdout: "pipe", stderr: "pipe" },
);
const video = await new Response(videoEncoder.stdout).arrayBuffer();
await new Response(videoEncoder.stderr).arrayBuffer();
if (await videoEncoder.exited) throw Error("could not create the host VP9 fixture");
const counts: Record<string, number> = {};
const server = Bun.serve({
	hostname: "127.0.0.1",
	port: 0,
	fetch(request) {
		const path = new URL(request.url).pathname;
		if (path === "/audio" || path === "/video") {
			const data = path === "/audio" ? audio : video;
			const range = request.headers.get("range");
			if (!range) return new Response(data);
			const match = /^bytes=(\d+)-(\d*)$/.exec(range);
			if (!match) return new Response(null, { status: 400 });
			const first = Number(match[1]);
			const last = Math.min(
				Number(match[2] || data.byteLength - 1),
				data.byteLength - 1,
			);
			if (first > last) return new Response(null, { status: 416 });
			return new Response(data.slice(first, last + 1), {
				status: 206,
				headers: { "Content-Range": `bytes ${first}-${last}/${data.byteLength}` },
			});
		}
		if (
			!["/once", "/always", "/redirect", "/target"].includes(path) ||
			!["bytes=0-15", "bytes=16-31"].includes(request.headers.get("range") ?? "")
		)
			return new Response(null, { status: 400 });
		counts[path] = (counts[path] ?? 0) + 1;
		if (path === "/redirect")
			return new Response(null, {
				status: 302,
				headers: { Location: new URL("/target", request.url).href },
			});
		const offset = request.headers.get("range") === "bytes=16-31" ? 16 : 0;
		const payload =
			"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_";
		const partial = path === "/always" || (path === "/once" && counts[path] === 1);
		const body = new ReadableStream({
			async start(controller) {
				controller.enqueue(
					new TextEncoder().encode(
						payload.slice(offset, offset + (partial ? 8 : 16)),
					),
				);
				await Bun.sleep(10);
				if (partial) controller.error();
				else controller.close();
			},
		});
		return new Response(body, {
			status: 206,
			headers: {
				"Content-Range": `bytes ${offset}-${offset + 15}/64`,
				"Content-Length": "16",
				Connection: "close",
			},
		});
	},
	error() {
		return new Response(null, { status: 500 });
	},
});
try {
	await $`mkdir -p build/playback-bench`;
	await $`odin test src/playback -out:build/playback-bench/reader-test -define:READER_HTTP_TEST_SERVER=${server.url.origin} -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false`;
	await $`odin test tests/playback/diagnostics -out:build/playback-bench/diagnostics-test -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false`;
	if (counts["/once"] !== 2 || counts["/always"] !== 2)
		throw Error("range recovery exceeded its retry limit");
	if (counts["/redirect"] !== 2 || counts["/target"] !== 2)
		throw Error("a temporary redirect replaced the original range source");
} finally {
	await server.stop(true);
}
