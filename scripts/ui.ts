import { $ } from "bun";

const dev = process.argv.includes("--dev");
const buildOnly = process.argv.includes("--build-only");
const smoke = process.argv.includes("--smoke");
const screenshots = process.argv.includes("--screenshots");
const directory = dev ? "build/dev" : "build/ui-test";
const binary = `${directory}/leantube`;

await $`mkdir -p ${directory}`.quiet();
// Odin selects the host entry point by its Linux x86-64 file suffix.
await $`odin build src -vet -define:UI_TEST=${!dev} -define:DEV_SMOKE=${smoke} -define:UI_SCREENSHOTS=${screenshots} -out:${binary}`;
if (!buildOnly) {
	if (dev) {
		console.log("native YouTube search; local playback is UI-only");
		await $`${binary}`;
	} else {
		const sizes = screenshots ? ["720p", "1080p", "1440p", "4k"] : ["1080p"];
		await Promise.all(sizes.map((size) => $`${binary} ${size}`));
	}
}
