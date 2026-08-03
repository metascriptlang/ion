import { BuildConfig } from "std/build";

const config: BuildConfig = {
	entry: "./src/index.ms",
	fmt: {
		useTabs: true,
	},
	package: {
		name: "@metascript/ion",
		version: "0.0.1",
		description: "Native desktop shell for MetaScript — system webview, no Chromium bundled",
		license: "MIT",
		files: [
			"src/**/*.ms",
			"src/**/*.c",
			"src/**/*.h",
			"src/**/*.m",
			"src/**/*.cpp",
			"src/**/*.hpp",
			"vendor/webview2/**",
			"scripts/**",
			"assets/**",
		],
	},
};

export default config;
