import { notify, windowCount } from "../src/index";

test "notify returns in a process outside an app bundle" {
	notify("title", "body", "ion-test");
	notify("again", "body", "ion-test");
	assert windowCount() === (0 as int32);
}
