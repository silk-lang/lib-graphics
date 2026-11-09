// Root wasm applications must own their callback/allocator exports.
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { root } from './internal.mjs';
import { nativeRoot } from './native-root.mjs';

const template = readFileSync(resolve(nativeRoot(), 'modules/gpu/webgpu/browser/generated_webgpu_exports.silk'), 'utf8');
const destination = resolve(root, 'modules/ui_renderer/browser/src/generated_webgpu_exports.silk');
if (process.argv.includes('--check')) {
  if (readFileSync(destination, 'utf8') !== template) throw new Error('Stale browser exports; run node scripts/generate-browser-exports.mjs');
} else writeFileSync(destination, template);
