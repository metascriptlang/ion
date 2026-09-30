// Compile/link smoke for the render-surface bridge — build-only (runLoop blocks).
// Exercises every MS wrapper so the externs must resolve against renderSurface.m.
import {
	createWindow, defaultOptions,
	renderSurfaceCreate, renderSurfaceAdopt, renderSurfaceLayer,
	renderSurfaceSetVisible, renderSurfaceSyncFrame,
	renderSurfaceSetInputRegion, renderSurfaceSetInputRect, renderSurfaceRelease,
	renderSurfaceSetFramePolicy, renderSurfaceSetFrameWhenInactive, renderSurfaceRequestFrame,
	onSurfaceFrame, runLoop,
	SurfaceBelow, InputNone, InputFull, RenderSurfaceInvalid, FrameContinuous,
} from "../src/index";

function tick(surface: int32, timeMs: float64): void {}

export function main(): int32 {
	const win = createWindow("main", defaultOptions("RenderSurface Smoke",
		1024 as int32, 768 as int32, "data:text/html,<h1>smoke</h1>"));
	if (win === null) return 1;

	const surf = renderSurfaceCreate(win, SurfaceBelow);
	if (surf === RenderSurfaceInvalid) return 2;

	const layer = renderSurfaceLayer(surf);
	renderSurfaceAdopt(surf, layer);
	renderSurfaceSetVisible(surf, true);
	renderSurfaceSyncFrame(surf);
	renderSurfaceSetInputRegion(surf, InputNone);
	renderSurfaceSetInputRect(surf, 0 as int32, 0 as int32, 512 as int32, 512 as int32);
	renderSurfaceSetInputRegion(surf, InputFull);

	renderSurfaceSetFramePolicy(surf, FrameContinuous);
	renderSurfaceSetFrameWhenInactive(surf, false);
	renderSurfaceRequestFrame(surf);
	onSurfaceFrame(tick);
	runLoop();
	renderSurfaceRelease(surf);
	return 0;
}
