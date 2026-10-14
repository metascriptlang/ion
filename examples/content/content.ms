when (windows) {
	@compile("./contentWin.cpp");
	@passL("-ldwrite");
}
when (macos) {
	@compile("./contentMac.m");
}
when (linux) {
	@compile("./contentLinux.c");
}
@include("./content.h");

export extern function contentAttach(parent: Ptr<void>, child: Ptr<void>, above: int32): int32;
export extern function contentDetach(parent: Ptr<void>, child: Ptr<void>): void;
export extern function contentMove(node: Ptr<void>, x: int32, y: int32, w: int32, h: int32): void;
export extern function contentPanel(device: Ptr<void>, w: int32, h: int32, text: cstring, rgb: uint32): Ptr<void>;
export extern function contentRelease(node: Ptr<void>): void;
