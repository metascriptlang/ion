import { Project, Target } from "../../tooling/generator/description";
import { bundlePrefix } from "../../tooling/generator/plugins";

const app = Target.app("IonGenerator", "main.ms");

export const project: Project = {
	name: "IonGenerator",
	targets: [{ ...app, dependencies: ["IonPreview"] }, { ...app, name: "IonPreview" }],
	plugins: [bundlePrefix("dev.ion")],
};
