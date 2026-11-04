// Read uploaded assets from `gh release view TAG --json assets`.
const {
	assets,
}: {
	assets: {
		name: string;
		digest: string | null;
		size: number;
	}[];
} = await Bun.stdin.json();
const { version, icon } = await Bun.file("app/appinfo.json").json();
const iconBytes = await Bun.file(`app/${icon}`).arrayBuffer();
const iconUri = `data:image/png;base64,${Buffer.from(iconBytes).toString("base64")}`;
const sourceUrl = `https://github.com/${process.env.GITHUB_REPOSITORY ?? "hyperpuncher/leantube"}`;
const output = `build/release/${version}`;
const packages = [];
for (const [directory, description] of [
	[
		"build",
		"native YouTube client for rooted LG webOS TVs. tested on LG B9 with webOS 4.9.",
	],
	[
		"build/legacy",
		"native YouTube client for older LG webOS TVs. tested on LG UJ630V with webOS 3.5.",
	],
] as const) {
	const {
		id,
		version: packageVersion,
		type,
		title,
	} = await Bun.file(`${directory}/app/appinfo.json`).json();
	if (packageVersion !== version)
		throw new Error(`release version mismatch: ${directory}`);
	if (packages.some((entry) => entry.id === id))
		throw new Error(`duplicate release app ID: ${id}`);
	const filename = `${id}_${version}_arm.ipk`;
	const asset = assets.find((asset) => asset.name === filename);
	if (!asset?.digest?.startsWith("sha256:"))
		throw new Error(`missing GitHub SHA256: ${filename}`);
	const manifest = {
		id,
		version,
		type,
		title,
		appDescription: description,
		iconUri,
		sourceUrl,
		rootRequired: true,
		// Draft asset URLs use a temporary tag. The feed needs the published URL.
		ipkUrl: `${sourceUrl}/releases/download/v${version}/${asset.name}`,
		ipkHash: { sha256: asset.digest.slice(7) },
		ipkSize: asset.size,
	};
	packages.push({ id, title, shortDescription: description, iconUri, manifest });
}
await Bun.write(`${output}/repo.json`, `${JSON.stringify({ packages }, null, "\t")}\n`);

const ref = process.env.GITHUB_SHA ?? "HEAD";
const previous = Bun.spawnSync(
	["git", "describe", "--tags", "--match", "v[0-9]*", "--abbrev=0", `${ref}^`],
	{ stderr: "ignore" },
);
const previousTag = previous.success ? previous.stdout.toString().trim() : "";
const history = Bun.spawnSync([
	"git",
	"log",
	"--reverse",
	"--format=%s%x1f%H%x1f%h",
	previousTag ? `${previousTag}..${ref}` : ref,
]);
if (!history.success) throw new Error("cannot read release history");
const groups = new Map<string, string[]>();
for (const commit of history.stdout.toString().trimEnd().split("\n").filter(Boolean)) {
	const [subject, full, short] = commit.split("\x1f");
	const match = subject!.match(/^([A-Za-z]+)(?:\([^)]*\))?!?:\s*(.+)$/);
	const type = match?.[1]?.toLowerCase() ?? "other";
	const lines = groups.get(type) ?? [];
	lines.push(`- ${match?.[2] ?? subject} [\`${short}\`](${sourceUrl}/commit/${full})`);
	groups.set(type, lines);
}
const order = "feat fix perf refactor style docs build test ci chore revert".split(" ");
const types = [
	...order,
	...[...groups.keys()].filter((type) => !order.includes(type)).sort(),
];
let notes = "### what's changed\n";
for (const type of types) {
	const lines = groups.get(type);
	if (lines) notes += `\n#### ${type}\n${lines.join("\n")}\n`;
}
notes += "\n";
if (previousTag) {
	notes += `**full changelog:** [${previousTag}...v${version}](${sourceUrl}/compare/${previousTag}...v${version})\n`;
}
await Bun.write(`${output}/notes.md`, notes);
console.log(`release files: ${output}`);
