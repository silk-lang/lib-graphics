// Internal comparison harness shared by the two independent CPU benchmarks.
import { mkdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { build, root, run } from './internal.mjs';

function timings(command, args, cwd, names) {
  const result = run(command, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8', timeout: 900000 });
  const measured = {};
  for (const line of result.stderr.split('\n')) {
    const [name, value, extra] = line.trim().split(/\s+/);
    if (names.includes(name) && extra === undefined) measured[name] = Number(value);
  }
  for (const name of names) if (!Number.isFinite(measured[name])) throw new Error(`Missing timing ${name} from ${command}`);
  return measured;
}
function difference(first, second) {
  const a = readFileSync(first), b = readFileSync(second);
  if (!a.length || a.length !== b.length || a.length % 4) throw new Error(`Incompatible RGBA images: ${first}, ${second}`);
  let sum = 0, worst = 0, over = 0;
  for (let pixel = 0; pixel < a.length; pixel += 4) {
    let maximum = 0;
    for (let channel = 0; channel < 4; channel++) {
      const delta = Math.abs(a[pixel + channel] - b[pixel + channel]);
      sum += delta;
      maximum = Math.max(maximum, delta);
    }
    worst = Math.max(worst, maximum);
    if (maximum > 8) over++;
  }
  return { mean: sum / a.length, worst, share: over / (a.length / 4) };
}
export function benchmark({ name, packagePath, reference, binaryName, iterations, scenes, baseline = false }) {
  const out = resolve(root, '.cache/bench', name);
  const target = resolve(root, '.cache/bench', name + '-rust');
  mkdirSync(out, { recursive: true });
  const binary = build(packagePath, { release: true });
  run('cargo', ['build', '--release', '--locked', '--quiet', '--manifest-path',
    resolve(root, 'modules', packagePath, reference, 'Cargo.toml'), '--target-dir', target]);
  const other = resolve(target, 'release', binaryName + (process.platform === 'win32' ? '.exe' : ''));
  const ours = timings(binary, [], out, scenes);
  const theirs = timings(other, [String(iterations)], out, [...scenes, ...(baseline ? ['baseline'] : [])]);
  console.log(`scene       vector ms  ${reference} ms  ratio   mean |d|  max |d|  pixels > 8`);
  for (const scene of scenes) {
    const d = difference(resolve(out, `vector-${scene}.rgba`), resolve(out, `${reference}-${scene}.rgba`));
    console.log(`${scene.padEnd(12)} ${ours[scene].toFixed(3)}  ${theirs[scene].toFixed(3)}  ${(ours[scene] / theirs[scene]).toFixed(2)}x  ${d.mean.toFixed(3)}  ${d.worst}  ${(d.share * 100).toFixed(2)}%`);
  }
  if (baseline) console.log(`(${reference} times exclude its ${theirs.baseline.toFixed(3)} ms baseline draw)`);
}
