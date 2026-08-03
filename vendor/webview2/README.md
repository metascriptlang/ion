# WebView2 SDK (vendored)

Microsoft Edge WebView2 SDK — C/C++ COM bindings + loader DLL. Vendored here so the ion build is self-contained and offline-capable.

## Version

**1.0.2849.39** (NuGet package `Microsoft.Web.WebView2`, released 2024-10-14)

Source: <https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.2849.39>

To re-fetch from upstream:

```bash
curl -sLo /tmp/wv2.nupkg "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.2849.39"
unzip -q /tmp/wv2.nupkg "build/native/include/*" "build/native/x64/WebView2Loader.dll" -d /tmp/wv2-out
# Then copy:
#   /tmp/wv2-out/build/native/include/*.h  → vendor/webview2/include/
#   /tmp/wv2-out/build/native/x64/WebView2Loader.dll → vendor/webview2/runtime/x64/
```

## What's vendored

```
vendor/webview2/
├── include/
│   ├── WebView2.h                     # main COM interface header (2.5 MB)
│   └── WebView2EnvironmentOptions.h   # environment options interface (17 KB)
└── runtime/
    └── x64/
        └── WebView2Loader.dll         # runtime DLL (162 KB) — ships next to ion .exe
```

## What's NOT vendored (and why)

- **`WebView2Loader.dll.lib` / `WebView2LoaderStatic.lib`** — MSVC COFF import / static libs. We cross-compile with `--target=x86_64-pc-windows-gnu` (MinGW ABI) via `zig c++`, which can't natively link MSVC `.lib`. Instead we call `LoadLibraryW(L"WebView2Loader.dll")` at runtime + `GetProcAddress` for the single entry point (`CreateCoreWebView2EnvironmentWithOptions`). All other WebView2 calls go through COM interface vtables — no link-time dependency.
- **x86 / arm64 loaders** — ion targets `x86_64-pc-windows-gnu` for v0. Other arches can be added later by re-running the fetch + extract for the matching `build/native/<arch>/` directory.
- **Experimental headers** (`WebView2Experimental*.h`) — not included; we use only the stable surface.

## Distribution requirement

End users need the **WebView2 Runtime** installed system-wide. It ships preinstalled on Windows 11 and on most updated Windows 10 systems. Phase 5 NSIS installer will check + offer to install the Evergreen Runtime if missing.

`WebView2Loader.dll` (the small loader vendored above) is a stub that finds and connects to the system-installed runtime — it is NOT the runtime itself.

## License

Microsoft Edge WebView2 SDK is distributed under the [Microsoft Software License Terms](https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.2849.39/License) bundled inside the .nupkg. Redistribution permitted for "Distributable Code" purposes which include this SDK's runtime + headers when used to build apps consuming WebView2.
