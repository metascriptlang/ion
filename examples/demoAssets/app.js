// ion:// custom-protocol demo — exercises the three feature checks the
// page describes: pushState, localStorage scoping, asset MIME serving.

const $origin  = document.getElementById("origin");
const $url     = document.getElementById("url");
const $counter = document.getElementById("counter");

function renderUrl() {
	$url.textContent = location.pathname;
}

function renderOrigin() {
	$origin.textContent = location.origin || "(empty origin → file:// trap!)";
}

function renderCounter() {
	const v = parseInt(localStorage.getItem("demo.counter") || "0", 10);
	$counter.textContent = String(v);
}

document.querySelectorAll("nav button").forEach((btn) => {
	btn.addEventListener("click", () => {
		const route = btn.dataset.route;
		// This is the call that throws SecurityError on file:// (opaque origin).
		// On ion:// (proper origin), it succeeds and the URL updates without reload.
		history.pushState(null, "", route);
		renderUrl();
	});
});

document.getElementById("inc").addEventListener("click", () => {
	const v = parseInt(localStorage.getItem("demo.counter") || "0", 10) + 1;
	localStorage.setItem("demo.counter", String(v));
	renderCounter();
});

document.getElementById("reset").addEventListener("click", () => {
	localStorage.removeItem("demo.counter");
	renderCounter();
});

window.addEventListener("popstate", renderUrl);

renderOrigin();
renderUrl();
renderCounter();

// Notify native we loaded — proves the IPC bootstrap shipped via WKURLSchemeHandler
// served HTML still has window.__ion__ injected by ion's user-script bootstrap.
if (window.__ion__ && typeof window.__ion__.post === "function") {
	window.__ion__.post("demo.ready", location.origin);
}
