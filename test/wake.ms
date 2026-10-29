import { onWake, dispatchWake } from "../src/wake";

test "a wake handler registered during dispatch runs from the next wake" {
	let added = false;
	let late = 0;
	onWake((): void => {
		if (added) return;
		added = true;
		onWake((): void => { late += 1; });
	});
	dispatchWake();
	assert late === 0;
	dispatchWake();
	assert late === 1;
}
