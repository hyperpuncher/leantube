const { id, version, type, title, icon } = await Bun.file(
	"build/app/appinfo.json",
).json();
const filename = `${id}_${version}_arm.ipk`;
const bytes = await Bun.file(`build/${filename}`).arrayBuffer();
const sha256 = new Bun.CryptoHasher("sha256").update(bytes).digest("hex");
const sourceUrl = `https://github.com/${process.env.GITHUB_REPOSITORY ?? "hyperpuncher/leantube"}`;
const iconBytes = await Bun.file(`build/app/${icon}`).arrayBuffer();
const iconUri = `data:image/png;base64,${Buffer.from(iconBytes).toString("base64")}`;
const description =
	"native YouTube client for rooted LG webOS TVs. tested on LG B9 with webOS 4.9.";
const manifest = {
	id,
	version,
	type,
	title,
	appDescription: description,
	iconUri,
	sourceUrl,
	rootRequired: true,
	ipkUrl: `${sourceUrl}/releases/download/v${version}/${filename}`,
	ipkHash: { sha256 },
	ipkSize: bytes.byteLength,
};
const repository = {
	packages: [{ id, title, shortDescription: description, iconUri, manifest }],
};
const output = `build/release/${version}`;
await Bun.write(`${output}/${filename}`, bytes);
await Bun.write(`${output}/repo.json`, `${JSON.stringify(repository, null, "\t")}\n`);

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
