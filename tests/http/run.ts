import { mkdtempSync } from "node:fs";

import { $ } from "bun";

const directory = mkdtempSync("/tmp/leantube-http-");
let server: ReturnType<typeof Bun.serve> | undefined;
try {
	await $`openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 1 -subj /CN=localhost -addext subjectAltName=DNS:localhost -keyout ${directory}/key.pem -out ${directory}/cert.pem`.quiet();
	server = Bun.serve({
		hostname: "127.0.0.1",
		port: 0,
		tls: {
			key: Bun.file(`${directory}/key.pem`),
			cert: Bun.file(`${directory}/cert.pem`),
		},
		async fetch(request) {
			const path = new URL(request.url).pathname;
			if (path === "/post") {
				if (
					request.method !== "POST" ||
					request.headers.get("x-leantube-test") !== "set"
				)
					return new Response("bad request", { status: 400 });
				return new Response(await request.arrayBuffer());
			}
			if (path === "/slow") await Bun.sleep(300);
			if (path === "/redirect")
				return new Response("redirect", {
					status: 302,
					headers: { Location: "http://localhost/unsafe" },
				});
			if (
				request.method !== "GET" ||
				request.headers.has("x-leantube-test") ||
				(await request.arrayBuffer()).byteLength !== 0
			)
				return new Response("stale request", { status: 400 });
			return new Response("ready");
		},
	});
	await $`mkdir -p build/http-test`.quiet();
	await $`LEANTUBE_TEST_HTTPS=${`https://localhost:${server.port}`} LEANTUBE_TEST_CA=${directory}/cert.pem odin test tests/http -out:build/http-test/check -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false`;
} finally {
	server?.stop(true);
	await $`trash -- ${directory}`.quiet();
}
