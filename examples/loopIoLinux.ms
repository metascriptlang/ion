// msc's I/O and timers under Ion's loop on Linux: reads per second from a local socket a
// spawned writer keeps full, setTimeout(2 ms) runs per second, and idle CPU. Run under Xvfb.
import { createWindow, defaultOptions, runLoop } from "../src/index";
import { createSocket, bind, listen, connect, send, acceptAsync, recvAsync, close } from "std/net";
import { readFile } from "std/fs";
import { exit } from "std/process";

const PORT: int32 = 47613 as int32;
let failures = 0;

function check(ok: boolean, what: string): void {
	console.log(`${ok ? "PASS" : "FAIL"} ${what}`);
	if (!ok) failures++;
}

function cpuTicks(): int32 {
	const stat = readFile("/proc/self/stat");
	if (!stat.ok) return -1 as int32;
	const fields = stat.value.split(") ")[1].split(" ");
	return (parseInt(fields[11]) + parseInt(fields[12])) as int32;
}

function writer(): int32 {
	const fd = createSocket();
	if (connect(fd, "127.0.0.1", PORT) < (0 as int32)) return -1 as int32;
	const chunk = "x".repeat(65536);
	let sent = 0;
	for (let i = 0; i < 4000; i++) {
		const n = send(fd, chunk);
		if (n <= (0 as int32)) break;
		sent = sent + 1;
	}
	close(fd);
	return sent as int32;
}

async function readFor(fd: int32, ms: float64): Promise<int32> {
	const end = Date.now() + ms;
	let reads = 0;
	while (Date.now() < end) {
		const b = await recvAsync(fd, 65536 as int32);
		if (b.length === 0) break;
		reads++;
	}
	return reads as int32;
}

async function timersFor(ms: float64): Promise<int32> {
	const end = Date.now() + ms;
	let runs = 0;
	while (Date.now() < end) {
		await new Promise<void>((resolve): void => { setTimeout(resolve, 2); });
		runs++;
	}
	return runs as int32;
}

async function probe(): Promise<void> {
	const timerRuns = await timersFor(1000);
	console.log(`setTimeout(2 ms) runs in 1 s: ${timerRuns}`);
	check(timerRuns > 200, "msc timers fire at their deadline, not on a 16 ms step (more than 200 runs of 2 ms in 1 s)");

	const listenFd = createSocket();
	bind(listenFd, "127.0.0.1", PORT);
	listen(listenFd, 1 as int32);
	const writing = spawn(() => writer());
	const fd = await acceptAsync(listenFd);
	const reads = await readFor(fd, 1000);
	console.log(`recvAsync reads in 1 s: ${reads}`);
	check(reads > 200, "socket reads are not paced by a 16 ms step (more than 200 reads in 1 s)");
	close(fd);
	close(listenFd);
	await writing;

	const before = cpuTicks();
	await new Promise<void>((resolve): void => { setTimeout(resolve, 2000); });
	const idle = cpuTicks() - before;
	console.log(`CPU ticks (1/100 s) over 2 s idle: ${idle}`);
	check(idle >= (0 as int32) && idle <= (10 as int32), "idle CPU stays under 5% (at most 10 ticks in 2 s)");
	console.log(failures === 0 ? "loopIoLinux: all PASS" : `loopIoLinux: ${failures} FAIL`);
	exit(failures === 0 ? 0 as int32 : 1 as int32);
}

const win = createWindow("main", defaultOptions("loopIoLinux", 320 as int32, 200 as int32));
if (win === null) {
	console.log("loopIoLinux: no window");
	exit(1 as int32);
}
probe();
runLoop();
