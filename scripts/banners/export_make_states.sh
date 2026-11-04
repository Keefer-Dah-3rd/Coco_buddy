#!/bin/bash
# Renders the Figma Make file's own banner art (design/banners/make-source/IllustratedScene.tsx) to
# SVG for every banner × light × weather and every step of five, into design/banners/states — the
# reference BannerArtPortTests checks the Swift port against.
#
#   scripts/banners/export_make_states.sh
#
# Run it after changing the art in the Make file: copy the new src/IllustratedScene.tsx into
# design/banners/make-source/ first, then run this, then `swift test --filter BannerArtPortTests`
# in Packages/BuddyKit and update BannerArt.swift until it passes. Needs Node (npm installs React
# and esbuild into a temporary folder; nothing is added to the repo).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
npm init -y >/dev/null
npm install --silent react@19.1.0 react-dom@19.1.0 esbuild@0.23.1 >/dev/null
mkdir src
cp "$ROOT/design/banners/make-source/IllustratedScene.tsx" src/
printf 'export type TimeOfDay = "Morning" | "Daytime" | "Evening" | "Night"\nexport type WeatherCondition = "Sunny" | "Cloudy" | "Rainy" | "Snowy" | "Windy"\nexport type ConceptKey = string\n' > src/App.ts
npx esbuild src/IllustratedScene.tsx --bundle --format=esm --platform=node --external:react --jsx=automatic --outfile=scene.mjs --log-level=warning
cat > render.mjs <<'JS'
import React from "react"
import { renderToStaticMarkup } from "react-dom/server"
import fs from "fs"
const Scene = (await import("./scene.mjs")).default
const out = process.argv[2]
const ids = { atmospheric: "tidalPool", coco: "windowNook", ferry: "slowFerry", bookshop: "cornerBookshop", rooftop: "laundryInTheSky", train: "quietCarriage" }
const note = (d) => d === 0 ? "A gentle start." : d < 3 ? "Growing nicely." : d < 5 ? "Look at you go." : "All done. Lovely."
const svg = (concept, time, weather, done) => {
  const html = renderToStaticMarkup(React.createElement(Scene, { concept, done, total: 5, message: note(done), time, weather, interactive: false }))
  return html.slice(html.indexOf("<svg"), html.lastIndexOf("</svg>") + 6).replace("<svg ", '<svg xmlns="http://www.w3.org/2000/svg" ')
}
let n = 0
for (const [concept, id] of Object.entries(ids)) {
  fs.mkdirSync(`${out}/${id}/progress`, { recursive: true })
  for (const time of ["Morning", "Daytime", "Evening", "Night"]) for (const weather of ["Sunny", "Cloudy", "Rainy", "Snowy", "Windy"]) {
    fs.writeFileSync(`${out}/${id}/${time.toLowerCase()}-${weather.toLowerCase()}.svg`, svg(concept, time, weather, 2)); n++
  }
  for (let d = 0; d <= 5; d++) { fs.writeFileSync(`${out}/${id}/progress/daytime-sunny-${d}of5.svg`, svg(concept, "Daytime", "Sunny", d)); n++ }
}
console.log(`wrote ${n} reference SVGs to ${out}`)
JS
node render.mjs "$ROOT/design/banners/states"
