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
const repo = process.env.GITHUB_REPOSITORY ?? "hyperpuncher/leantube";
const sourceUrl = `https://github.com/${repo}`;
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

console.log(`release files: ${output}`);
