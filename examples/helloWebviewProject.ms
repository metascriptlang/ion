import { Project, Target } from "../tooling/generator/description";
import { bundlePrefix } from "../tooling/generator/plugins";

const app = { ...Target.windowsApp("IonHello", "helloWebview.ms"), assets: ["hello.html"] };

export const project: Project = {
	name: "IonHello",
	targets: [{ ...app, dependencies: ["IonPreview"] }, { ...app, name: "IonPreview" }],
	plugins: [bundlePrefix("dev.ion")],
};
