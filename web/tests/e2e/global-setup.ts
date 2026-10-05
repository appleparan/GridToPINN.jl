import { spawn } from 'node:child_process';

// 빌드한 사이트를 vite preview로 띄운다. Playwright의 webServer 옵션을 쓰지 않는 이유:
// webServer는 시작 전에 포트가 비었는지 접속해 보는데, WSL2에서는 닫힌 localhost 포트로의 접속이
// 거절되지 않고 2분 넘게 멈추는 일이 있다. 여기서는 서버가 "Local:" 줄을 찍을 때까지 기다린다.
export default async function globalSetup(): Promise<() => Promise<void>> {
	const port = process.env.E2E_PORT!;
	const server = spawn(
		process.execPath,
		['node_modules/vite/bin/vite.js', 'preview', '--strictPort', '--port', port],
		{ stdio: ['ignore', 'pipe', 'pipe'] }
	);
	let log = '';
	await new Promise<void>((resolve, reject) => {
		const timer = setTimeout(() => reject(new Error(`preview server did not start:\n${log}`)), 30_000);
		const onData = (chunk: Buffer) => {
			// CI는 색을 켜서 'Local'과 ':' 사이에 ANSI 코드가 끼므로 지우고 찾는다.
			log += chunk.toString().replace(/\x1b\[[0-9;]*m/g, '');
			if (log.includes('Local:')) {
				clearTimeout(timer);
				resolve();
			}
		};
		server.stdout.on('data', onData);
		server.stderr.on('data', onData);
		server.on('exit', (code) => {
			clearTimeout(timer);
			reject(new Error(`preview server exited with code ${code}:\n${log}`));
		});
	});
	return async () => {
		server.kill('SIGTERM');
	};
}
