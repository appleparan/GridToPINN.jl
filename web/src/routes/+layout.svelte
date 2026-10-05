<script lang="ts">
	import { base } from '$app/paths';
	import '../app.css';
	let { children } = $props();
</script>

<nav><a href="{base}/">처음</a> · <a href="{base}/verify">검증</a></nav>
<main>{@render children()}</main>
