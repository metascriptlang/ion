import { Project, Target } from "../../tooling/generator/description";
import { bundlePrefix } from "../../tooling/generator/plugins";

export const project: Project = {
	name: "IonAndroid",
	targets: [{ ...Target.androidApp("IonAndroid", "main.ms"), assets: ["assets/marker.txt", "bundle"] }],
	plugins: [bundlePrefix("dev.ion")],
};
