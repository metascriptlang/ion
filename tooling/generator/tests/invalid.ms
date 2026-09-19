import { Project, Target } from "../description";
import { bundlePrefix } from "../plugins";

const target = Target.app("Duplicate", "main.ms");
export const project: Project = {
	name: "Invalid",
	targets: [target, target],
	plugins: [bundlePrefix("dev.ion")],
};
