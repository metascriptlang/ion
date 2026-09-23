export enum Platform { Macos, Ios, Android }

export struct AndroidSettings {
	minSdk: int32;
	compileSdk: int32;
	targetSdk: int32;
	ndkVersion: string;
	abi: string;
	javaVersion: int32;
}

const androidDefaults: AndroidSettings = {
	minSdk: 23, compileSdk: 36, targetSdk: 36, ndkVersion: "28.0.13004108", abi: "arm64-v8a", javaVersion: 17,
};

export struct Target {
	name: string;
	platform: Platform;
	deploymentTarget: string;
	entry: string;
	bundleId: string;
	dependencies: Vec<string>;
	android: AndroidSettings;
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
	return {
		name, entry, platform: Platform.Macos, deploymentTarget: "13.0",
		bundleId: "", dependencies: [], android: androidDefaults,
	};
}

export function iosApp(this typeof Target, name: string, entry: string): Target {
	return {
		name, entry, platform: Platform.Ios, deploymentTarget: "15.0",
		bundleId: "", dependencies: [], android: androidDefaults,
	};
}

export function androidApp(this typeof Target, name: string, entry: string): Target {
	return {
		name, entry, platform: Platform.Android, deploymentTarget: "",
		bundleId: "", dependencies: [], android: androidDefaults,
	};
}
