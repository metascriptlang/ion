// Tests for src/permissionCode.ms: the bridge's state-and-flag encoding.

import { micAccessFromCode } from "../src/permissionCode";

test "granted, denied and undetermined decode without the flag" {
	const granted = micAccessFromCode(0);
	const denied = micAccessFromCode(1);
	const undetermined = micAccessFromCode(2);
	if (granted.ok) { assert granted.value.status === "granted"; assert !granted.value.canAskAgain; } else { assert false; }
	if (denied.ok) { assert denied.value.status === "denied"; assert !denied.value.canAskAgain; } else { assert false; }
	if (undetermined.ok) { assert undetermined.value.status === "undetermined"; assert !undetermined.value.canAskAgain; } else { assert false; }
}

test "the can-ask flag rides on the state" {
	const r = micAccessFromCode(0x102);
	if (r.ok) { assert r.value.status === "undetermined"; assert r.value.canAskAgain; } else { assert false; }
}

test "an unknown state is an error that names it" {
	const r = micAccessFromCode(7);
	if (r.ok) { assert false; } else { assert r.error.includes("7"); }
}
