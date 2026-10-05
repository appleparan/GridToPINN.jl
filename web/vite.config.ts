import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vitest/config';

export default defineConfig({
	plugins: [sveltekit()],
	server: {
		// 커널 .jl 소스는 저장소 루트(src/)에 있다 (sources.ts가 ?raw로 불러옴)
		fs: { allow: ['..'] }
	},
	test: { include: ['tests/unit/**/*.test.ts'], environment: 'node' }
});
