import { Project, Target } from "../../tooling/generator/description";
import { bundlePrefix } from "../../tooling/generator/plugins";

export const project: Project = {
	name: "IonIos",
	targets: [Target.iosApp("IonIos", "main.ms")],
	plugins: [bundlePrefix("dev.ion")],
};
