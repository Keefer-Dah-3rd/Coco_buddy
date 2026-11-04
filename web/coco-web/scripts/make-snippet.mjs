// Turns the built embed script into ready-to-use files for Semplice/WordPress:
//   dist/embed/coco-embed.js           host this file, then use semplice-hosted.html
//   dist/embed/semplice-snippet.html   everything in one paste (no hosting needed)
//   dist/embed/coco.html               a full page, for an <iframe> or a direct link
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const dir = join(dirname(fileURLToPath(import.meta.url)), "..", "dist", "embed");
// Pure ASCII (non-ASCII characters as \uXXXX escapes), so the script reads the same on a
// page or server that doesn't declare UTF-8.
const js = readFileSync(join(dir, "coco-embed.js"), "utf8").replace(
  /[^\x00-\x7f]/g,
  (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`,
);
writeFileSync(join(dir, "coco-embed.js"), js);
// A literal "</script" inside the bundle would end an inline <script> early.
const inline = js.replace(/<\/script/gi, "<\\/script");
const kb = (s) => `${(Buffer.byteLength(s) / 1024).toFixed(0)} KB`;

const spot = `<div data-coco data-height="460"></div>`;

writeFileSync(
  join(dir, "semplice-snippet.html"),
  `<!-- Coco the corgi: paste all of this into a Semplice "Code" module. -->\n${spot}\n<script>\n${inline}\n</script>\n`,
);

writeFileSync(
  join(dir, "semplice-hosted.html"),
  `<!-- Coco the corgi, with coco-embed.js hosted on your site (or any static host).
     Replace the src with wherever you uploaded coco-embed.js. -->
${spot}
<script src="https://YOUR-SITE.com/path/to/coco-embed.js" defer></script>
`,
);

writeFileSync(
  join(dir, "coco.html"),
  `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Coco the Corgi</title>
<style>html,body{margin:0;height:100%;background:transparent}[data-coco]{height:100%}</style>
</head>
<body>
<div data-coco data-height="100vh" data-radius="0"></div>
<script>
${inline}
</script>
</body>
</html>
`,
);

console.log(`coco-embed.js ${kb(js)} · semplice-snippet.html and coco.html written to dist/embed`);
