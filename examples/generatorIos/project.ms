import { Project, Target, plistBoolean } from "../../tooling/generator/description";
import { bundlePrefix } from "../../tooling/generator/plugins";

export const project: Project = {
	name: "IonIos",
	targets: [{
		...Target.iosApp("IonIos", "main.ms"),
		assets: ["assets/marker.txt", "bundle"],
		infoPlist: [plistBoolean("UIFileSharingEnabled", true), plistBoolean("LSSupportsOpeningDocumentsInPlace", true)],
	}],
	plugins: [bundlePrefix("dev.ion")],
};
