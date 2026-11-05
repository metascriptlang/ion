import { Project, Target } from "../../tooling/generator/description";
import { bundlePrefix } from "../../tooling/generator/plugins";

export const project: Project = {
	name: "IonAndroid",
	targets: [{
		...Target.androidApp("IonAndroid", "main.ms"),
		assets: ["assets/marker.txt", "bundle"],
		android: { ...Target.androidApp("IonAndroid", "main.ms").android, permissions: ["android.permission.CAMERA"] },
	}],
	plugins: [bundlePrefix("dev.ion")],
};
