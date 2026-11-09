import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { build, root, run } from './internal.mjs';

const budget = JSON.parse(readFileSync(resolve(root, 'graphics/ui_renderer/bench/budget.json'), 'utf8'));
const binary = build('ui_renderer/bench', { release: true });
const result = run(binary, [], { stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8' });
process.stderr.write(result.stderr);
const measured = {};
for (const line of result.stderr.split('\n')) {
  const [name, value, extra] = line.trim().split(/\s+/);
  if (['primitives', 'build', 'encode', 'frame'].includes(name) && extra === undefined) measured[name] = Number(value);
}
for (const name of ['primitives', 'build', 'encode', 'frame']) {
  if (!Number.isFinite(measured[name])) throw new Error(`Missing benchmark metric: ${name}`);
}
console.log(`dense scene: ${measured.primitives} primitives, 1280 x 800 BGRA8`);
const over = [];
for (const stage of ['build', 'encode', 'frame']) {
  console.log(`${stage}: ${measured[stage].toFixed(2)} ms (budget ${budget[stage].toFixed(2)} ms)`);
  if (measured[stage] > budget[stage]) over.push(stage);
}
if (over.length) throw new Error(`Over budget: ${over.join(', ')}`);
