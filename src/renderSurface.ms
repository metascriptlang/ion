// Render surface — host a native rendering layer (Metal / GL / a whole game
// engine view) inside a window, composited against the webview. Ion has no
// opinion on what draws into it; the renderer owns the pixels. Generic by
// design — a Godot game is just one consumer. See docs/RENDER-SURFACE.md.
//
// MS API mirrors window.ms / windowManager.ms: free functions over the pure-C
// bridge + an opaque RenderSurfaceId, taking a typed Window handle.

import {
	ionRenderSurfaceCreate,
	ionRenderSurfaceAdopt,
	ionRenderSurfaceAdoptLayer,
	ionRenderSurfaceLayer,
	ionRenderSurfaceAttachSwapChain,
	ionRenderSurfaceSetImeRect,
	ionWebviewSetFrame,
	ionWebviewSetVisible,
	ionRenderSurfaceSetVisible,
	ionRenderSurfaceSyncFrame,
	ionRenderSurfaceSetInputRegion,
	ionRenderSurfaceRelease,
} from "./platform/bridge.h";
import { Window } from "./windowManager";

// z-order relative to the window's webview (mirror bridge.h).
export const SurfaceBelow: int32 = 0 as int32;
export const SurfaceAbove: int32 = 1 as int32;

// input-region modes (mirror bridge.h).
export const InputNone: int32 = 0 as int32;
export const InputFull: int32 = 1 as int32;
export const InputRect: int32 = 2 as int32;

export type RenderSurfaceId = int32;
export const RenderSurfaceInvalid: RenderSurfaceId = -1 as int32;

// Create a surface bound to `win`, positioned below/above its webview.
// Returns RenderSurfaceInvalid if the window is closed/unknown or no slot free.
export function renderSurfaceCreate(win: Window, z: int32): RenderSurfaceId {
	return ionRenderSurfaceCreate(win.id, z) as RenderSurfaceId;
}

// Mode A — adopt a native view the renderer already owns (NSView* / HWND).
// The handle is whatever the renderer's own FFI returns (e.g. libgodot's
// window_get_native_handle(WINDOW_VIEW)).
export function renderSurfaceAdopt(surf: RenderSurfaceId, nativeView: Ptr<void>): void {
	ionRenderSurfaceAdopt(surf, nativeView);
}

// Mode A2 (macOS) — adopt a CALayer the renderer draws into (an embedded
// engine's CAMetalLayer), embedded directly into the window. In-process.
export function renderSurfaceAdoptLayer(surf: RenderSurfaceId, caLayer: int64): void {
	ionRenderSurfaceAdoptLayer(surf, caLayer);
}

// Mode B — Ion owns the surface; returns a layer to render into. Null until Phase 2.
export function renderSurfaceLayer(surf: RenderSurfaceId): Ptr<void> {
	return ionRenderSurfaceLayer(surf);
}

export function renderSurfaceAttachSwapChain(surf: RenderSurfaceId, dxgiSwapChain1: int64): boolean {
	return ionRenderSurfaceAttachSwapChain(surf, dxgiSwapChain1) !== (0 as int32);
}

export function renderSurfaceSetImeRect(surf: RenderSurfaceId, x: int32, y: int32, w: int32, h: int32): void {
	ionRenderSurfaceSetImeRect(surf, x, y, w, h);
}

export function webviewSetFrame(win: Window, x: int32, y: int32, w: int32, h: int32): void {
	ionWebviewSetFrame(win.id, x, y, w, h);
}

export function webviewSetVisible(win: Window, visible: boolean): void {
	ionWebviewSetVisible(win.id, visible ? (1 as int32) : (0 as int32));
}

export function renderSurfaceSetVisible(surf: RenderSurfaceId, visible: boolean): void {
	ionRenderSurfaceSetVisible(surf, visible ? (1 as int32) : (0 as int32));
}

export function renderSurfaceSyncFrame(surf: RenderSurfaceId): void {
	ionRenderSurfaceSyncFrame(surf);
}

// Route input to the surface (InputFull) or the webview (InputNone), driven by
// app state (in-match vs in-launcher).
export function renderSurfaceSetInputRegion(surf: RenderSurfaceId, mode: int32): void {
	ionRenderSurfaceSetInputRegion(surf, mode, 0 as int32, 0 as int32, 0 as int32, 0 as int32);
}

// Split: input inside the rect → surface, outside → webview.
export function renderSurfaceSetInputRect(surf: RenderSurfaceId, x: int32, y: int32, w: int32, h: int32): void {
	ionRenderSurfaceSetInputRegion(surf, InputRect, x, y, w, h);
}

export function renderSurfaceRelease(surf: RenderSurfaceId): void {
	ionRenderSurfaceRelease(surf);
}
