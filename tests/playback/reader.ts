import { open } from "node:fs/promises";

const args = Bun.argv.slice(2);
const host = args[0] === "--host";
if (host) args.shift();
const decode = args[0] === "--decode";
if (decode) args.shift();
if (decode && host) throw Error("decoder tests require the TV");
const transport = args[0] === "--transport";
if (transport) args.shift();
const [
	playerPath,
	output,
	mode = "ffmpeg",
	secondsText = "90",
	startText = "0",
	seekAfterText = "-1",
	seekToText = "0",
] = args;
const seconds = Number(secondsText);
const start = Number(startText);
const seekAfter = Number(seekAfterText);
const seekTo = Number(seekToText);
const socketReceiveBuffer = Number(process.env.LEANTUBE_READER_RCVBUF ?? "0");
if (
	!Number.isInteger(socketReceiveBuffer) ||
	socketReceiveBuffer < 0 ||
	socketReceiveBuffer > 8388608 ||
	(socketReceiveBuffer > 0 && mode.startsWith("ffmpeg")) ||
	!playerPath ||
	!output ||
	!["ffmpeg", "curl-reuse", "curl-h3"].includes(mode) ||
	(transport &&
		(!["curl-reuse", "curl-h3"].includes(mode) ||
			seconds > 256 ||
			!Number.isSafeInteger(start) ||
			!Number.isSafeInteger(start + seconds * 1048576) ||
			seekAfter >= 0)) ||
	!Number.isInteger(seconds) ||
	seconds < 1 ||
	!Number.isFinite(start) ||
	start < 0 ||
	!Number.isFinite(seekAfter) ||
	!Number.isFinite(seekTo) ||
	(seekAfter >= 0 && (seekAfter >= seconds || seekTo < 0))
) {
	throw Error("expected PLAYER_JSON OUTPUT MODE SECONDS START [SEEK_AFTER SEEK_TO]");
}
const player = await Bun.file(playerPath).json();
const fixture = player.fixture === true;
interface Format {
	url?: string;
	mimeType?: string;
	height?: number;
	width?: number;
	itag?: number;
	fps?: number;
	bitrate?: number;
	isDrc?: boolean;
	xtags?: string;
	audioTrack?: { audioIsDefault?: boolean };
}
const formats: Format[] = player.streamingData?.adaptiveFormats ?? [];
const video = formats
	.filter(
		(f) =>
			f.url &&
			(f.height === 2160 || f.width === 3840) &&
			f.mimeType?.includes('codecs="vp9'),
	)
	.sort((a, b) => (b.bitrate ?? 0) - (a.bitrate ?? 0))[0];
const audio = formats
	.filter(
		(f) =>
			f.url &&
			f.mimeType?.includes('audio/mp4; codecs="mp4a.40.2"') &&
			!f.isDrc &&
			(f.audioTrack?.audioIsDefault ?? !f.xtags),
	)
	.sort((a, b) => (b.bitrate ?? 0) - (a.bitrate ?? 0))[0];
if (!video?.url || (!transport && !audio?.url))
	throw Error("4K VP9 and original AAC input missing");
const links = transport ? [video.url] : [video.url, audio!.url!];
for (const link of links) {
	const url = new URL(link);
	if (url.protocol !== "https:" && !(fixture && url.protocol === "http:"))
		throw Error("HTTPS input required outside explicit LAN fixtures");
	const expiry = Number(url.searchParams.get("expire"));
	if (expiry && expiry * 1000 < Date.now() + (transport ? 80 : seconds + 120) * 1000)
		throw Error("refresh the player response first");
}
async function powerState(): Promise<string> {
	const request = Bun.spawn(
		[
			"ssh",
			process.env.TV_HOST ?? "tv",
			'luna-send -n 1 -w 5000 luna://com.webos.service.tvpower/power/getPowerState "{}" </dev/null',
		],
		{ stdout: "pipe", stderr: "pipe" },
	);
	const [text] = await Promise.all([
		new Response(request.stdout).text(),
		new Response(request.stderr).text(),
	]);
	if ((await request.exited) !== 0) throw Error("could not read TV power state");
	const value = JSON.parse(text);
	if (!value.returnValue) throw Error("TV power state request rejected");
	return value.state;
}
const initialPower = host ? null : await powerState();
if (!host && initialPower !== "Active")
	throw Error("TV must be active for comparable benchmarks; wake it first");
const sources = [
	"src/playback/ffmpeg.odin",
	"src/playback/http.odin",
	"src/playback/reader.odin",
	"src/playback/session.odin",
	"src/playback/statistics.odin",
	"src/playback/aac.odin",
	"tests/playback/diagnostics/reader.odin",
	"tests/playback/diagnostics/transport.odin",
	...(decode
		? [
				"src/starfish_linux_arm32.odin",
				"src/bench_decoder_linux_arm32.odin",
				"src/display_linux_arm32.odin",
				"vendor/starfish/StarfishMediaAPIs_C.cpp",
			]
		: []),
];
const hasher = new Bun.CryptoHasher("sha256");
for (const path of sources) {
	hasher.update(path).update(await Bun.file(path).arrayBuffer());
}
const sourceHash = hasher.digest("hex");
const file = await open(output, "wx", 0o600);
const benchArgs = transport
	? ["--transport-bench", mode, secondsText, startText]
	: [
			decode ? "--decoder-bench" : "--reader-bench",
			mode,
			secondsText,
			startText,
			seekAfterText,
			seekToText,
		];
const command = `${decode ? "APPID=org.hyperpuncher.leantube " : ""}LEANTUBE_READER_RCVBUF=${socketReceiveBuffer} timeout -t ${transport ? 80 : seconds + 110} /media/developer/apps/usr/palm/applications/org.hyperpuncher.leantube/leantube ${benchArgs.join(" ")}`;
const child = Bun.spawn(
	host
		? [
				"build/playback-bench/reader-host",
				...(transport ? benchArgs : benchArgs.slice(1)),
			]
		: ["ssh", process.env.TV_HOST ?? "tv", command],
	{
		stdin: "pipe",
		stdout: "pipe",
		stderr: "pipe",
	},
);
child.stdin.write(`${links.join("\n")}\n`);
child.stdin.end();
const errors = new Response(child.stderr).text();
const cancel = () => child.kill();
process.once("SIGINT", cancel);
process.once("SIGTERM", cancel);
let summarySeen = false;
try {
	await file.write(
		`${JSON.stringify({
			type: transport
				? "raw_http_ranges"
				: decode
					? "hardware_decoder_test"
					: "network_demux_only",
			decoder_enabled: decode,
			requested_mib: transport ? seconds : null,
			source_byte_offset: transport ? start : null,
			demux_enabled: !transport,
			audio_enabled: !transport,
			device: host ? "host" : "TV",
			source_kind: fixture ? "LAN_fixture" : "YouTube",
			video_itag: video.itag,
			audio_itag: transport ? null : audio?.itag,
			source_width: video.width,
			source_height: video.height,
			source_fps: video.fps,
			tv_power_state: initialPower,
			scenario: transport
				? "sequential_byte_ranges"
				: seekAfter >= 0
					? "in_session_seek"
					: start > 0
						? "cold_open_at_offset"
						: "cold_open_from_start",
			seek_after_play_s: seekAfter,
			seek_target_s: seekAfter >= 0 ? seekTo : null,
			connection_reuse: true,
			range_method: "HTTP_header",
			http_protocol_required: mode === "curl-h3" ? "3" : "1.1",
			socket_rcvbuf_requested: socketReceiveBuffer,
			socket_rcvbuf_scope: "per_socket_only_no_system_change",
			single_transfer_receive_retry_limit: mode.startsWith("ffmpeg") ? null : 1,
			source_sha256: sourceHash,
			mode,
			startup_buffer_s: transport ? null : 3,
			maximum_buffer_s: transport ? null : 20,
			ffmpeg_initial_request_bytes: transport ? null : 1048576,
			ffmpeg_request_bytes: transport ? null : 1048576,
			video_block_bytes: 1048576,
			audio_block_bytes: transport ? null : 1048576,
			video_transport_parallelism: 1,
			audio_transport_parallelism: transport ? 0 : 1,
			video_transport_body_limit_bytes: mode === "ffmpeg" ? null : 1048576,
			audio_transport_body_limit_bytes:
				transport || mode.startsWith("ffmpeg") ? null : 1048576,
			userspace_transport_memory_included_in_peak_rss: true,
			kernel_socket_memory_included_in_peak_rss: false,
			source_start_s: transport ? null : start,
			requested_play_s: transport ? null : seconds,
		})}\n`,
	);
	const lines = new TextDecoderStream();
	const stream = child.stdout.pipeThrough(lines);
	let pending = "";
	for await (const text of stream) {
		pending += text;
		let newline: number;
		while ((newline = pending.indexOf("\n")) >= 0) {
			const line = pending.slice(0, newline);
			pending = pending.slice(newline + 1);
			if (!line.trim()) continue;
			let sample;
			try {
				sample = JSON.parse(line);
			} catch (error) {
				if (decode) {
					if (line.startsWith("reply kind=")) console.error(line);
					continue;
				}
				throw error;
			}
			if (
				decode &&
				!sample.summary &&
				![
					"http_transfer",
					"decoder_load",
					"decoder_progress",
					"decoder_seek",
					"decoder_pause",
					"decoder_unload",
				].includes(sample.event)
			)
				continue;
			if (sample.video_buffer_s > 20.001 || sample.audio_buffer_s > 20.001) {
				throw Error("the packet queue exceeded the 20-second limit");
			}
			if (sample.summary) {
				if (
					sample.played_s > 0 &&
					(sample.height !== video.height ||
						(video.width !== undefined && sample.width !== video.width))
				)
					throw Error(
						"reader source resolution does not match the selected format",
					);
				summarySeen = true;
			}
			await file.write(`${JSON.stringify(sample)}\n`);
			if (sample.summary) console.log(JSON.stringify(sample));
		}
	}
	const code = await child.exited;
	for (const line of (await errors).split("\n")) {
		if (line.startsWith("reader ")) console.error(line);
		if (
			decode &&
			/^(display event id=|display (bind=|metadata accepted=|playing accepted=)|display control created id:)/.test(
				line,
			)
		)
			console.error(line);
		if (decode && line.startsWith("native bus initialization failed:"))
			console.error(
				line.match(/^native bus initialization failed: -?\d+/)?.[0] ??
					"native bus initialization failed",
			);
	}
	if (!host) {
		const finalPower = await powerState();
		await file.write(`${JSON.stringify({ tv_power_state_end: finalPower })}\n`);
		if (finalPower !== initialPower)
			throw Error("TV power state changed during the benchmark");
	}
	if (code !== 0 || !summarySeen)
		throw Error(
			`reader benchmark failed (exit ${code}); inspect the numeric results`,
		);
} finally {
	process.removeListener("SIGINT", cancel);
	process.removeListener("SIGTERM", cancel);
	child.kill();
	await file.close();
	// Stop only this diagnostic command. Do not touch a normal app process.
	if (!host) {
		const cleanupScript = `var fs=require("fs");fs.readdirSync("/proc").filter(function(p){return /^\\d+$/.test(p)}).forEach(function(p){try{var a=fs.readFileSync("/proc/"+p+"/cmdline","utf8").split("\\0");if(a[0]==="/media/developer/apps/usr/palm/applications/org.hyperpuncher.leantube/leantube"&&(a[1]==="--reader-bench"||a[1]==="--transport-bench"||a[1]==="--decoder-bench"))process.kill(Number(p),"SIGTERM")}catch(e){}});`;
		const cleanup = Bun.spawn(
			["ssh", process.env.TV_HOST ?? "tv", `node -e '${cleanupScript}'`],
			{ stdout: "ignore", stderr: "pipe" },
		);
		await new Response(cleanup.stderr).arrayBuffer();
		if ((await cleanup.exited) !== 0)
			throw Error("could not verify reader process cleanup");
	}
}
