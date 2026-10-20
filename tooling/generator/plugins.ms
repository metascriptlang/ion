import {
	Plugin,
	Target,
	BundleId,
	FileContribution,
	Platform,
	Arch,
	Slot,
	Artifact,
} from "./description";
import { normalize, dirname } from "std/fs/path";
import { expansionFile } from "std/meta";

const ionRoot = @comptime { return normalize(dirname(expansionFile()) + "/../.."); };

const webview2Loader: Artifact = {
	name: "webview2Loader",
	license: "Microsoft Software License Terms (WebView2 SDK)",
	slices: [{
		platform: Platform.Windows,
		arch: Arch.X64,
		files: [ionRoot + "/vendor/webview2/runtime/x64/WebView2Loader.dll"],
	}],
};

export function bundlePrefix(prefix: string): Plugin {
	return {
		name: "bundlePrefix(" + prefix + ")",
		contribute: (targets: Span<Target>): Vec<BundleId> => {
			let ids: Vec<BundleId> = [];
			for (const target of targets) ids.push({ target: target.name, value: prefix + "." + target.name });
			return ids;
		},
		files: (targets: Span<Target>): Vec<FileContribution> => [],
	};
}

export function webview(): Plugin {
	return {
		name: "webview()",
		contribute: (targets: Span<Target>): Vec<BundleId> => [],
		files: (targets: Span<Target>): Vec<FileContribution> => {
			let contributions: Vec<FileContribution> = [];
			for (const target of targets) {
				if (target.platform != Platform.Windows) continue;
				contributions.push({
					target: target.name,
					placement: { artifact: webview2Loader, slot: Slot.Libraries, directory: "" },
				});
			}
			return contributions;
		},
	};
}
