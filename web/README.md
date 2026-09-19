# @metascriptlang/ion

Typed JS↔MS IPC for [ion](https://github.com/metascript/ion) webview apps.

## Install

```bash
npm install @metascriptlang/ion
```

## Usage

```ts
import { call, invoke, on } from "@metascriptlang/ion";

// Tauri-style: await a typed Promise from MS native
const sum = await call<number>("addNumbers", { a: 3, b: 5 });

// Fire-and-forget
invoke("ready", "");

// Listen for MS-initiated messages
on("notification.click", (id) => {
  console.log("user tapped notification", id);
});

on("deeplink", (url) => {
  navigate(url);
});
```

## How it works

When ion's native shell creates the webview, it injects a tiny transport object
at `window.__ion__` carrying the per-launch invoke_key (a 32-byte random token).
This package wraps that transport with a typed, ergonomic API.

Wire protocol:

| API | Channel | Envelope |
|---|---|---|
| `invoke(name, payload)` | `name` | `{__key, name, payload}` |
| `on(name, handler)` | (registered) | — |
| `call<T>(name, args)` | `__call` | `{id, name, args}` |
| (Promise resolves) | `__response` (in) | `{id, value}` |
| (Promise rejects) | `__response` (in) | `{id, error}` |

The `__key` field carries the invoke_key on every JS→MS message. iframes
and content injected outside our document-start script don't see `window.__ion__`,
so they cannot reach the IPC.

## Build from source

```bash
npm install
npm run build
# → dist/index.js + dist/index.d.ts
```

## License

MIT
