// Re-wires the clickable prototype on the Figma “Prototype” page.
//
// Run it through the Figma MCP `use_figma` tool (or a development plugin) after a screen's
// layout changes: hotspots sit over the real controls inside the screen instances, so they
// must move when the controls do. It removes this script's own hotspots (layers named
// “hotspot · …” on the Prototype page) and recreates every interaction from the FLOW table.
//
// Scenes are found by their number prefix (“07 · Today”), controls by their visible text
// inside the scene, so renaming a scene or a button label means updating the table below.

const page = figma.root.children.find(p => p.name === 'Prototype');
if (!page) throw new Error('No “Prototype” page');
await figma.setCurrentPageAsync(page);

const scenes = {};
for (const f of page.children) if (f.type === 'FRAME' && /^\d\d · /.test(f.name)) scenes[f.name.slice(0, 2)] = f;

// Remove previous wiring (only this script's own layers and reactions).
for (const s of Object.values(scenes)) {
  for (const h of s.findAll(n => n.name.startsWith('hotspot · '))) h.remove();
  await s.setReactionsAsync([]);
  for (const close of s.findAll(n => n.name === 'close')) await close.setReactionsAsync([]);
}

const fade = { type: 'DISSOLVE', easing: { type: 'EASE_OUT' }, duration: 0.18 };
const go = to => ({ type: 'NODE', destinationId: scenes[to].id, navigation: 'NAVIGATE', transition: fade, resetScrollPosition: true });
const action = to => (to === 'BACK' ? { type: 'BACK' } : go(to));
const missing = [];
const findText = (root, chars) => root && root.findOne(n => n.type === 'TEXT' && n.characters === chars);
const instanceAbove = n => { let p = n && n.parent; while (p && p.type !== 'INSTANCE') p = p.parent; return p; };

async function hotspot(sceneKey, target, to, label) {
  const scene = scenes[sceneKey];
  if (!target) { missing.push(`${scene.name}: ${label}`); return; }
  // A control inside a window gets its hotspot in the window, so it scrolls with the content
  // and stays below the fixed title-bar controls.
  const win = scene.findChild(n => n.name === 'window');
  let inWindow = false;
  for (let p = target; p && p !== scene; p = p.parent) if (p === win) inWindow = true;
  const host = inWindow ? win : scene;
  const hb = host.absoluteBoundingBox, tb = target.absoluteBoundingBox;
  const h = figma.createFrame(); h.name = `hotspot · ${label}`; h.fills = []; h.resize(Math.max(8, tb.width), Math.max(8, tb.height));
  if (host.numberOfFixedChildren) host.insertChild(host.children.length - host.numberOfFixedChildren, h); else host.appendChild(h);
  h.x = tb.x - hb.x; h.y = tb.y - hb.y;
  await h.setReactionsAsync([{ trigger: { type: 'ON_CLICK' }, actions: [action(to)] }]);
}

// Targets: { text } = the control showing that text (inside `within`, a layer name, if given);
// { layer } = a named layer; 'coco' = Coco on the desktop.
function target(sceneKey, spec) {
  const s = scenes[sceneKey];
  if (spec === 'coco') return s.findChild(n => n.name === 'Coco');
  if (spec.layer) return s.findOne(n => n.name === spec.layer);
  const root = spec.within ? s.findOne(n => n.name === spec.within) : s;
  const text = findText(root, spec.text);
  if (spec.row) { let p = text; while (p && p.name !== 'Task Row') p = p.parent; return p && p.findOne(n => n.name === 'content'); }
  return spec.menuItem ? (root.findOne(n => n.type === 'FRAME' && n.name === spec.text)) : instanceAbove(text);
}

const FLOW = {
  '01': [[{ text: 'Next' }, '02']],
  '02': [[{ text: 'Back' }, '01'], [{ text: 'Next' }, '03']],
  '03': [[{ text: 'Back' }, '02'], [{ text: 'Next' }, '04'], [{ text: 'Set up…' }, '16'], [{ text: 'Add key…' }, '16']],
  '04': [[{ text: 'Back' }, '03'], [{ text: 'Start' }, '05']],
  '05': [['coco', '07'], [{ layer: 'Coco menu bar item' }, '06']],
  '06': [['Open Coco', '07'], ['Talk to Coco', '09'], ['Start Focus (25 min)', '11'], ['Settings…', '15'], ['Connections…', '16']].map(([t, to]) => [{ text: t, within: 'menu', menuItem: true }, to]),
  '07': [[{ text: 'Take Coco to the park', row: true }, '08'], [{ layer: 'mic' }, '09'], [{ text: 'Focus', within: 'Up Next Card' }, '11'], [{ layer: 'connections' }, '16']],
  '08': [[{ text: 'Done' }, '07'], [{ text: 'Remove' }, '07']],
  '09': [[{ text: 'Add 3 tasks' }, '07'], [{ text: 'Discard' }, '07']],
  '10': [[{ text: 'Start focus' }, '11']],
  '12': [['coco', '13']],
  '13': [[{ text: 'Yes, done' }, '07'], [{ text: 'Not yet' }, '07'], [{ text: 'Take short break · 5m' }, '05'], [{ text: 'Skip' }, '07']],
  '15': [[{ text: 'Connections…' }, '16'], [{ text: 'Show welcome again' }, '01']],
};
// Panel scenes: tabs, ESC, clicking Coco closes, the menu-bar item, and the Esc key.
const PANELS = { '07': ['Focus', 'Chat'], '08': ['Focus', 'Chat'], '09': ['Focus', 'Chat'], '10': ['Today', 'Chat'], '13': ['Today', 'Chat'], '14': ['Today', 'Focus'] };
const TAB_TARGET = { Today: '07', Focus: '10', Chat: '14' };

for (const [k, links] of Object.entries(FLOW)) for (const [spec, to] of links) await hotspot(k, target(k, spec), to, typeof spec === 'string' ? spec : spec.text || spec.layer);
for (const [k, tabs] of Object.entries(PANELS)) {
  for (const t of tabs) await hotspot(k, instanceAbove(findText(scenes[k].findOne(n => n.name === 'tabs'), t)), TAB_TARGET[t], `${t} tab`);
  await hotspot(k, target(k, { layer: 'esc' }), '05', 'ESC');
  await hotspot(k, target(k, 'coco'), '05', 'Coco (close panel)');
  await hotspot(k, target(k, { layer: 'Coco menu bar item' }), '06', 'menu bar item');
  await scenes[k].setReactionsAsync([{ trigger: { type: 'ON_KEY_DOWN', device: 'KEYBOARD', keyCodes: [27] }, actions: [go('05')] }]);
}
// The open menu closes when you click anywhere else.
{ const s = scenes['06']; const bg = figma.createFrame(); bg.name = 'hotspot · click outside closes the menu'; bg.fills = []; bg.resize(s.width, s.height); s.insertChild(1, bg); bg.x = 0; bg.y = 0;
  await bg.setReactionsAsync([{ trigger: { type: 'ON_CLICK' }, actions: [{ type: 'BACK' }] }]); }
// A focus session “ends” after 2.5 s (Figma timeouts are milliseconds).
await scenes['11'].setReactionsAsync([{ trigger: { type: 'AFTER_TIMEOUT', timeout: 2500 }, actions: [go('12')] }]);
// Windows close with their red button or Esc.
for (const k of ['15', '16']) {
  await scenes[k].findOne(n => n.name === 'close').setReactionsAsync([{ trigger: { type: 'ON_CLICK' }, actions: [{ type: 'BACK' }] }]);
  await scenes[k].setReactionsAsync([{ trigger: { type: 'ON_KEY_DOWN', device: 'KEYBOARD', keyCodes: [27] }, actions: [{ type: 'BACK' }] }]);
}
page.flowStartingPoints = [{ nodeId: scenes['01'].id, name: 'Onboarding' }, { nodeId: scenes['05'].id, name: 'Daily use' }];
return { missing, hotspots: page.findAll(n => n.name.startsWith('hotspot · ')).length };
