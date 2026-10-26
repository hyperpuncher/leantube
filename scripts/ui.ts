import { $ } from "bun";

const dev = process.argv.includes("--dev");
const buildOnly = process.argv.includes("--build-only");
const smoke = process.argv.includes("--smoke");
const directory = dev ? "build/dev" : "build/ui-test";
const binary = `${directory}/leantube`;

await $`mkdir -p ${directory}`.quiet();
// Odin selects the host entry point by its Linux x86-64 file suffix.
await $`odin build src -vet -define:UI_TEST=${!dev} -define:DEV_SMOKE=${smoke} -out:${binary}`;
if (!buildOnly) {
	if (dev) {
		const prepared = await Bun.file("build/catalog/catalog.json").exists();
		console.log(
			prepared
				? "using the prepared catalog"
				: "using 24 generated cards; just prepare fetches real covers",
		);
		// The host reads public metadata and covers, never private load requests.
		await $`${binary} ${prepared ? ["catalog"] : []}`;
	} else {
		for (const size of ["1080p", "1440p", "4k", "narrow"]) await $`${binary} ${size}`;
	}
}
