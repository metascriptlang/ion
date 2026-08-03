// Compile/link smoke for the render-surface bridge — build-only (runLoop blocks).
// Exercises every MS wrapper so the externs must resolve against renderSurface.m.
import {
	createWindow, defaultOptions,
	renderSurfaceCreate, renderSurfaceAdopt, renderSurfaceLayer,
	renderSurfaceSetVisible, renderSurfaceSyncFrame,
	renderSurfaceSetInputRegion, renderSurfaceSetInputRect, renderSurfaceRelease,
	onFrame, runLoop,
	SurfaceBelow, InputNone, InputFull, RenderSurfaceInvalid,
} from "../src/index";

function tick(): void {}

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

	onFrame(tick);
	runLoop();
	renderSurfaceRelease(surf);
	return 0;
}
