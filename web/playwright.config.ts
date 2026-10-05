import { defineConfig } from '@playwright/test';

// 같은 시험을 루트 경로(기본)와 BASE_PATH=/sub 두 번 돌린다: `bun run test:e2e`
const BASE = process.env.BASE_PATH ?? '';
const PORT = BASE ? 4174 : 4173;
process.env.E2E_PORT = String(PORT);

export default defineConfig({
	testDir: 'tests/e2e',
	outputDir: 'test-results/pw',
	reporter: [['list'], ['html', { open: 'never' }]],
	timeout: 60_000,
	use: {
		baseURL: `http://localhost:${PORT}`,
		channel: 'chrome' // 시스템에 설치된 Chrome (실행 파일 경로를 적지 않음)
	},
	// 서버는 global-setup이 띄운다 (빌드는 package.json의 test:e2e 스크립트가 먼저 한다).
	globalSetup: './tests/e2e/global-setup.ts'
});
