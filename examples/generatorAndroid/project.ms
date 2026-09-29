import { Project, Target } from "../../tooling/generator/description";
import { bundlePrefix } from "../../tooling/generator/plugins";

export const project: Project = {
	name: "IonAndroid",
	targets: [Target.androidApp("IonAndroid", "main.ms")],
	plugins: [bundlePrefix("dev.ion")],
};
