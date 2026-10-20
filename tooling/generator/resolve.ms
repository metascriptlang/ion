import {
	Project,
	Graph,
	Target,
	BundleIdentity,
	Platform,
	Placement,
	PlacedFile,
	Slot,
	platformName,
	archName,
	slotName,
} from "./description";
import { basename } from "std/fs/path";

function targetIndex(targets: Span<Target>, name: string): int32 {
	for (let i = 0; i < targets.length; i += 1) {
		if (targets[i].name == name) return i;
	}
	return -1;
}

function validName(value: string): boolean {
	if (value == "") return false;
	for (let i = 0; i < value.byteLength; i += 1) {
		const c = value.byteAt(i);
		if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 45 || c == 95) continue;
		return false;
	}
	return true;
}

function validDeploymentTarget(value: string): boolean {
	const parts = value.split(".");
	if (parts.length < 2 || parts.length > 3) return false;
	for (const part of parts) {
		if (part == "") return false;
		for (let i = 0; i < part.byteLength; i += 1) {
			const c = part.byteAt(i);
			if (c < 48 || c > 57) return false;
		}
	}
	return true;
}

function quoted(value: string): string {
	return "'" + value + "'";
}

function validRelativePath(path: string): boolean {
	if (path == "" || path.startsWith("/") || path.startsWith("\\") || path.includes(":")) return false;
	for (const segment of path.replaceAll("\\", "/").split("/")) {
		if (segment == "" || segment == "." || segment == "..") return false;
	}
	return true;
}

function claim(identity: BundleIdentity): string {
	return identity.owner + " sets " + quoted(identity.value);
}

function cyclePath(targets: Span<Target>, ready: Vec<string>): string {
	let current = "";
	for (const target of targets) {
		if (!ready.includes(target.name)) {
			current = target.name;
			break;
		}
	}
	let path: Vec<string> = [];
	while (!path.includes(current)) {
		path.push(current);
		for (const dependency of targets[targetIndex(targets, current)].dependencies) {
			if (!ready.includes(dependency)) {
				current = dependency;
				break;
			}
		}
	}
	let cycle = "";
	let inCycle = false;
	for (const name of path) {
		if (name == current) inCycle = true;
		if (inCycle) cycle += name + " -> ";
	}
	return cycle + current;
}

function record(ref graph: Graph, identity: BundleIdentity): Result<void, string> {
	for (const previous of graph.identities) {
		if (previous.target == identity.target && previous.value != identity.value) {
			return Result.err("bundle identity conflict for " + quoted(identity.target) + ": " + claim(previous) + ", " + claim(identity));
		}
	}
	graph.targets[targetIndex(graph.targets, identity.target)].bundleId = identity.value;
	graph.identities.push(identity);
	return Result.ok(null);
}

function describe(placed: PlacedFile): string {
	return placed.owner + " places " + quoted(placed.source) + " at " + slotName(placed.slot) + " " +
		quoted(placed.destination);
}

function recordFile(ref graph: Graph, placed: PlacedFile): Result<void, string> {
	for (const previous of graph.files) {
		if (previous.target != placed.target || previous.slot != placed.slot) continue;
		if (previous.destination != placed.destination) continue;
		if (previous.source == placed.source) return Result.ok(null);
		return Result.err(
			"file conflict for " + quoted(placed.target) + ": " + describe(previous) + ", " + describe(placed),
		);
	}
	graph.files.push(placed);
	return Result.ok(null);
}

function refuseAndroid(owner: string, name: string, target: Target): Result<void, string> {
	if (target.platform != Platform.Android) return Result.ok(null);
	return Result.err(
		"files are not placed for Android targets yet; " + owner + " places " + quoted(name) +
		" into " + quoted(target.name),
	);
}

function place(ref graph: Graph, owner: string, target: Target, placement: Placement): Result<void, string> {
	const artifact = placement.artifact;
	const by = owner + " into " + quoted(target.name);
	try refuseAndroid(owner, artifact.name, target);
	if (placement.directory != "" && !validRelativePath(placement.directory)) {
		return Result.err(
			"directory " + quoted(placement.directory) + " of " + quoted(artifact.name) +
			" must be a relative path inside the slot, placed by " + by,
		);
	}
	for (const slice of artifact.slices) {
		if (slice.platform != target.platform || slice.arch != target.arch) continue;
		for (const source of slice.files) {
			const name = basename(source);
			const destination = placement.directory == "" ? name : placement.directory + "/" + name;
			try recordFile(graph, { owner, target: target.name, slot: placement.slot, source, destination });
		}
		return Result.ok(null);
	}
	return Result.err(
		"artifact " + quoted(artifact.name) + " has no slice for " + platformName(target.platform) + " " +
		archName(target.arch) + ", placed by " + by,
	);
}

export function resolve(this project: Project): Result<Graph, string> {
	if (!validName(project.name)) return Result.err("invalid project name: " + quoted(project.name));
	if (project.targets.length == 0) return Result.err("project " + quoted(project.name) + " has no targets");
	let graph: Graph = { name: project.name, targets: project.targets, identities: [], files: [] };
	for (let i = 0; i < graph.targets.length; i += 1) {
		const target = graph.targets[i];
		if (!validName(target.name)) return Result.err("invalid target name: " + quoted(target.name));
		if (target.entry == "") return Result.err("target " + quoted(target.name) + " has no entry");
		const appleTarget = target.platform == Platform.Macos || target.platform == Platform.Ios;
		if (appleTarget && !validDeploymentTarget(target.deploymentTarget)) {
			return Result.err(
				"invalid deployment target for " + quoted(target.name) + ": " +
				quoted(target.deploymentTarget) + " (expected major.minor or major.minor.patch)",
			);
		}
		if (targetIndex(graph.targets, target.name) != i) return Result.err("the target " + quoted(target.name) + " is declared multiple times");
		for (const dependency of target.dependencies) {
			if (targetIndex(graph.targets, dependency) < 0) {
				return Result.err("couldn't find target " + quoted(dependency) + " required by " + quoted(target.name));
			}
		}
	}
	let ready: Vec<string> = [];
	while (ready.length < graph.targets.length) {
		const before = ready.length;
		for (const target of graph.targets) {
			if (ready.includes(target.name)) continue;
			let satisfied = true;
			for (const dependency of target.dependencies) {
				if (!ready.includes(dependency)) satisfied = false;
			}
			if (satisfied) ready.push(target.name);
		}
		if (before == ready.length) return Result.err("circular dependency between targets: " + cyclePath(graph.targets, ready));
	}
	for (const target of graph.targets) {
		for (const placement of target.files) try place(graph, "manifest", target, placement);
	}
	for (const target of graph.targets) {
		for (const asset of target.assets) {
			try refuseAndroid("manifest", asset, target);
			if (!validRelativePath(asset)) {
				return Result.err("asset of " + quoted(target.name) + " must be a relative path inside the source directory: " + asset);
			}
			try recordFile(graph, { owner: "manifest", target: target.name, slot: Slot.Resources, source: asset, destination: asset });
		}
	}
	for (const target of project.targets) {
		if (target.bundleId != "") try record(graph, { owner: "manifest", target: target.name, value: target.bundleId });
	}
	for (const plugin of project.plugins) {
		const owner = "plugin " + plugin.name;
		let input: Vec<Target> = graph.targets;
		for (const id of plugin.contribute(input)) {
			if (targetIndex(graph.targets, id.target) < 0) return Result.err(owner + " contributes to missing target " + quoted(id.target));
			if (id.value == "") return Result.err(owner + " contributes an empty bundle identity to " + quoted(id.target));
			try record(graph, { owner, target: id.target, value: id.value });
		}
		let filesInput: Vec<Target> = graph.targets;
		for (const contribution of plugin.files(filesInput)) {
			const index = targetIndex(graph.targets, contribution.target);
			if (index < 0) return Result.err(owner + " contributes to missing target " + quoted(contribution.target));
			try place(graph, owner, graph.targets[index], contribution.placement);
		}
	}
	for (const target of graph.targets) {
		if (target.bundleId == "") return Result.err("missing bundle identity for " + quoted(target.name));
	}
	return Result.ok(graph);
}
