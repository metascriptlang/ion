export enum Platform { Macos, Ios, Android, Windows }

export function platformName(platform: Platform): string {
	return match (platform) {
		Platform.Macos => "macOS",
		Platform.Ios => "iOS",
		Platform.Android => "Android",
		Platform.Windows => "Windows",
	};
}

export enum Arch { X64, Arm64 }

export function archName(arch: Arch): string {
	return match (arch) {
		Arch.X64 => "x64",
		Arch.Arm64 => "arm64",
	};
}

export enum Slot { Executables, Libraries, Resources }

export function slotName(slot: Slot): string {
	return match (slot) {
		Slot.Executables => "Executables",
		Slot.Libraries => "Libraries",
		Slot.Resources => "Resources",
	};
}

export struct Slice {
	platform: Platform;
	arch: Arch;
	files: Vec<string>;
}

export struct Artifact {
	name: string;
	license: string;
	slices: Vec<Slice>;
}

export struct Placement {
	artifact: Artifact;
	slot: Slot;
	directory: string;
}

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

export enum InfoPlistKind { Boolean, String }

export struct InfoPlistEntry {
	key: string;
	kind: InfoPlistKind;
	value: string;
}

export function plistBoolean(key: string, value: boolean): InfoPlistEntry {
	return { key, kind: InfoPlistKind.Boolean, value: value ? "true" : "false" };
}

export function plistString(key: string, value: string): InfoPlistEntry {
	return { key, kind: InfoPlistKind.String, value };
}

export struct Target {
	name: string;
	platform: Platform;
	arch: Arch;
	deploymentTarget: string;
	entry: string;
	bundleId: string;
	dependencies: Vec<string>;
	assets: Vec<string>;
	files: Vec<Placement>;
	developmentTeam: string;
	infoPlist: Vec<InfoPlistEntry>;
	android: AndroidSettings;
}

export struct BundleId {
	target: string;
	value: string;
}

export struct FileContribution {
	target: string;
	placement: Placement;
}

export struct Plugin {
	name: string;
	contribute: (targets: Span<Target>) => Vec<BundleId>;
	files: (targets: Span<Target>) => Vec<FileContribution>;
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

export struct PlacedFile {
	owner: string;
	target: string;
	slot: Slot;
	source: string;
	destination: string;
}

export struct Graph {
	name: string;
	targets: Vec<Target>;
	identities: Vec<BundleIdentity>;
	files: Vec<PlacedFile>;
}

export function app(this typeof Target, name: string, entry: string): Target {
	return {
		name, entry, platform: Platform.Macos, arch: Arch.Arm64, deploymentTarget: "13.0",
		bundleId: "", dependencies: [], assets: [], files: [], developmentTeam: "", infoPlist: [], android: androidDefaults,
	};
}

export function iosApp(this typeof Target, name: string, entry: string): Target {
	return {
		name, entry, platform: Platform.Ios, arch: Arch.Arm64, deploymentTarget: "15.0",
		bundleId: "", dependencies: [], assets: [], files: [], developmentTeam: "", infoPlist: [], android: androidDefaults,
	};
}

export function androidApp(this typeof Target, name: string, entry: string): Target {
	return {
		name, entry, platform: Platform.Android, arch: Arch.Arm64, deploymentTarget: "",
		bundleId: "", dependencies: [], assets: [], files: [], developmentTeam: "", infoPlist: [], android: androidDefaults,
	};
}

export function windowsApp(this typeof Target, name: string, entry: string): Target {
	return {
		name, entry, platform: Platform.Windows, arch: Arch.X64, deploymentTarget: "",
		bundleId: "", dependencies: [], assets: [], files: [], developmentTeam: "", infoPlist: [], android: androidDefaults,
	};
}
