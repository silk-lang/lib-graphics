// Repository-internal process helpers; no library code imports this module.
import { spawnSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const silk = process.env.SILK || 'silk';
export function run(command, args = [], options = {}) {
  console.error('+', command, ...args);
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit', timeout: 600000, ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    throw new Error(`${command} failed (${result.signal || result.status})`);
  }
  return result;
}
export function manifest(packagePath) {
  return resolve(root, 'graphics', packagePath, 'silk.toml');
}
export function build(packagePath, { release = false, wasm = false } = {}) {
  const path = manifest(packagePath);
  const windowsGPU = process.platform === 'win32' && !wasm && /^(gpu_scene|ui_renderer)\//.test(packagePath);
  if (windowsGPU) {
    run(silk, ['check', '--manifest-path', path]);
    run(process.execPath, ['scripts/prepare-windows.mjs']);
  }
  run(silk, ['build', '--manifest-path', path, ...(release ? ['--release'] : []),
    ...(wasm ? ['--target', 'wasm32-unknown-unknown'] : [])]);
  const name = readFileSync(path, 'utf8').match(/^name\s*=\s*"([^"]+)"/m)?.[1];
  if (!name) throw new Error(`Package name missing: ${path}`);
  const filename = name + (!wasm && process.platform === 'win32' ? '.exe' : '');
  const candidates = [];
  for (const base of [resolve(root, 'build/llvm'), resolve(dirname(path), 'build/llvm')]) {
    if (!existsSync(base)) continue;
    for (const target of readdirSync(base)) {
      if (wasm !== (target === 'wasm32-unknown-unknown')) continue;
      const binary = resolve(base, target, release ? 'release' : 'debug', filename);
      if (existsSync(binary)) candidates.push(binary);
    }
  }
  if (candidates.length !== 1) throw new Error(`Expected one ${filename}, found: ${candidates.join(', ')}`);
  if (windowsGPU) run(process.execPath, ['scripts/prepare-windows.mjs', '-RuntimeDirectory', dirname(candidates[0])]);
  return candidates[0];
}
