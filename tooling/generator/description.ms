export enum Platform { Macos, Ios }

export struct Target {
	name: string;
	platform: Platform;
	entry: string;
	bundleId: string;
	dependencies: Vec<string>;
}

export struct BundleId {
	target: string;
	value: string;
}

export struct Plugin {
	name: string;
	contribute: (targets: Span<Target>) => Vec<BundleId>;
}

export struct Project {
	name: string;
	targets: Vec<Target>;
	plugins: Vec<Plugin>;
}

export struct BundleIdentity {
	owner: string;
	target: string;
	value: string;
}

export struct Graph {
	name: string;
	targets: Vec<Target>;
	identities: Vec<BundleIdentity>;
}

export function app(this typeof Target, name: string, entry: string): Target {
	return { name, entry, platform: Platform.Macos, bundleId: "", dependencies: [] };
}
