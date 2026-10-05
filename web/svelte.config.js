import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
export default {
	preprocess: vitePreprocess(),
	kit: {
		adapter: adapter({ pages: 'build', assets: 'build', fallback: undefined, strict: true }),
		// 하위 경로 배포: BASE_PATH=/sub bun run build
		paths: { base: process.env.BASE_PATH ?? '' }
	}
};
