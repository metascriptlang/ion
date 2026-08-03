// Internal: escape an MS string for safe interpolation into a JS source
// literal (between double-quotes). Used by IPC eval-based dispatch.

export function jsEscape(s: string): string {
	return s
		.replaceAll("\\", "\\\\")
		.replaceAll("\"", "\\\"")
		.replaceAll("\n", "\\n")
		.replaceAll("\r", "\\r");
}
