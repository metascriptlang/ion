import { Node, NodeKind, stringValue, expansionFile, define } from "std/meta";
import { isFile, readFile, writeFile } from "std/fs";
import { dirname, join } from "std/fs/path";

export macro androidLibrary(path: Node): Node {
	const library = join(dirname(expansionFile()), stringValue(path));
	if (!isFile(join(library, "build.gradle")) && !isFile(join(library, "build.gradle.kts"))) {
		error(library + " has no build.gradle", path);
	}
	const declarations = define("ionAndroidLibraries");
	if (declarations != "") {
		const previous = readFile(declarations);
		if (!writeFile(declarations, (previous.ok ? previous.value : "") + library + "\n").ok) {
			error("cannot record " + library + " in " + declarations, path);
		}
	}
	return { kind: NodeKind.StringLiteral, line: path.line, column: path.column, value: library };
}
