import { Project, Target } from "../../tooling/generator/description";
import { bundlePrefix } from "../../tooling/generator/plugins";

const studio = Target.app("IonStudio", "main.ms");

export const project: Project = {
	name: "IonStudio",
	targets: [{ ...studio, dependencies: ["IonPreview"] }, { ...studio, name: "IonPreview" }],
	plugins: [bundlePrefix("dev.ion")],
};
