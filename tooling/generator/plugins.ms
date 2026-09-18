import { Plugin, Target, BundleId } from "./description";

export function bundlePrefix(prefix: string): Plugin {
	return {
		name: "bundlePrefix(" + prefix + ")",
		contribute: (targets: Span<Target>): Vec<BundleId> => {
			const ids: Vec<BundleId> = [];
			for (const target of targets) ids.push({ target: target.name, value: prefix + "." + target.name });
			return ids;
		},
	};
}
