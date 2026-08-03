// Semantic Versioning compare — minimal subset for OTA version diffing.
//
// Accepts "v0.1.9" or "0.1.9" (leading `v` optional). Pre-release tags
// (`-beta.1`) are supported: a version with a pre-release sorts BELOW the
// same version without one (semver §11.4). Build metadata (`+sha.abc`) is
// stripped and ignored (semver §11.4 — build metadata never affects ordering).
//
// Returns:
//   negative  if a < b
//   zero      if a == b
//   positive  if a > b
//
// Designed for `currentVersion < manifest.version` updates check, NOT for
// full constraint resolution. Pre-release ordering inside the same major/
// minor/patch (e.g. `beta.1` vs `beta.10`) uses lexicographic on the
// identifier list — sufficient for v0.

// Strip leading 'v' if present. Returns the rest unchanged.
function stripV(s: string): string {
	if (s.length > 0 && (s.charCodeAt(0) === 118 || s.charCodeAt(0) === 86)) {
		return s.slice(1, s.length);
	}
	return s;
}

// Split "1.2.3-beta.1+build" → ["1.2.3", "beta.1"] (build stripped).
// Returns null when the core component isn't three dotted ASCII digit groups.
interface Parsed {
	major: int32;
	minor: int32;
	patch: int32;
	prerelease: string;  // empty when none
}

function parseSemver(raw: string): Parsed {
	const s = stripV(raw);
	// Drop build metadata first — anything after '+' is non-ordering.
	const plusIdx = s.indexOf("+");
	const noBuild = plusIdx >= 0 ? s.slice(0, plusIdx) : s;
	// Split off pre-release (everything after first '-').
	const dashIdx = noBuild.indexOf("-");
	const core = dashIdx >= 0 ? noBuild.slice(0, dashIdx) : noBuild;
	const pre  = dashIdx >= 0 ? noBuild.slice(dashIdx + 1, noBuild.length) : "";
	const parts = core.split(".");
	if (parts.length !== 3) {
		return { major: 0 as int32, minor: 0 as int32, patch: 0 as int32, prerelease: "" };
	}
	return {
		major: parseIntSafe(parts[0]),
		minor: parseIntSafe(parts[1]),
		patch: parseIntSafe(parts[2]),
		prerelease: pre,
	};
}

// parseInt without exceptions — returns 0 on any non-digit content. Caller
// treats malformed versions as "v0.0.0" which always loses any compare.
function parseIntSafe(s: string): int32 {
	if (s.length === 0) return 0 as int32;
	let n = 0;
	for (let i = 0; i < s.length; i++) {
		const c = s.charCodeAt(i);
		if (c < 48 || c > 57) return 0 as int32;
		n = n * 10 + (c - 48);
	}
	return n as int32;
}

export function compareSemver(a: string, b: string): int32 {
	const pa = parseSemver(a);
	const pb = parseSemver(b);
	if (pa.major !== pb.major) return (pa.major - pb.major) as int32;
	if (pa.minor !== pb.minor) return (pa.minor - pb.minor) as int32;
	if (pa.patch !== pb.patch) return (pa.patch - pb.patch) as int32;
	// Same core: a release version (no pre-release) > any pre-release
	// (semver §11.4.1). Within both having pre-release: lexicographic on
	// the raw tag string — covers `beta.1 < beta.2` and `alpha < beta`
	// correctly for the typical MyApp release cadence.
	if (pa.prerelease === "" && pb.prerelease === "") return 0 as int32;
	if (pa.prerelease === "") return 1 as int32;
	if (pb.prerelease === "") return -1 as int32;
	if (pa.prerelease < pb.prerelease) return -1 as int32;
	if (pa.prerelease > pb.prerelease) return 1 as int32;
	return 0 as int32;
}

// Convenience: a strictly less than b ?
export function isOlderThan(current: string, candidate: string): boolean {
	return compareSemver(current, candidate) < 0;
}
