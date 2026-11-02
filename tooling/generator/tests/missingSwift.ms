import { Project, Target } from "../description";
import { bundlePrefix } from "../plugins";

export const project: Project = {
	name: "MissingSwift",
	targets: [{ ...Target.iosApp("MissingSwift", "missingSwift.ms"), swiftSources: ["native/missing.swift"] }],
	plugins: [bundlePrefix("dev.ion")],
};
