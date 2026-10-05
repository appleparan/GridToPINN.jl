// Lazy Julia syntax highlighting. shiki is imported dynamically so nothing runs during SSR/prerender.
import type { HighlighterCore } from 'shiki/core';

type Highlighter = HighlighterCore;

let pending: Promise<Highlighter> | undefined;

function create(): Promise<Highlighter> {
	return (async () => {
		const [{ createHighlighterCore }, { createJavaScriptRegexEngine }, julia, light, dark] = await Promise.all([
			import('shiki/core'),
			import('shiki/engine/javascript'),
			import('shiki/langs/julia.mjs'),
			import('shiki/themes/github-light.mjs'),
			import('shiki/themes/github-dark.mjs')
		]);
		return createHighlighterCore({
			langs: [julia.default],
			themes: [light.default, dark.default],
			engine: createJavaScriptRegexEngine()
		});
	})();
}

/**
 * Returns highlighted HTML (light and dark colors as CSS variables).
 * The input only ever comes from the repository's own .jl files, so rendering it with {@html} is safe.
 */
export async function highlight(code: string): Promise<string> {
	pending ??= create();
	try {
		const hl = await pending;
		return hl.codeToHtml(code, {
			lang: 'julia',
			themes: { light: 'github-light', dark: 'github-dark' },
			defaultColor: false
		});
	} catch (e) {
		pending = undefined;
		throw e;
	}
}
