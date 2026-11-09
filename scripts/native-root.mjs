// Resolve runtime payloads from the same exact Git pin as the Silk dependency.
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { manifest } from './internal.mjs';

export function nativeRoot() {
  const source = readFileSync(manifest('ui_renderer/browser'), 'utf8');
  const dependency = source.match(/^webgpu\s*=\s*\{([^\n]+)\}/m)?.[1];
  const revision = dependency?.match(/\brev\s*=\s*"([0-9a-f]{40})"/)?.[1];
  const git = dependency?.match(/\bgit\s*=\s*"([^"]+)"/)?.[1];
  if (!revision || !git || !/^https:\/\/github\.com\/silk-lang\/lib-native(?:\.git)?$/.test(git)) {
    throw new Error('The browser webgpu dependency must pin silk-lang/lib-native to an exact 40-character Git revision');
  }
  const home = process.env.SILK_HOME || resolve(homedir(), '.silk');
  const directory = resolve(home, 'git', revision);
  if (!existsSync(resolve(directory, 'native/gpu/webgpu/browser/runner.ts'))) {
    throw new Error(`Pinned native payload missing: ${directory}. First run silk check --manifest-path graphics/ui_renderer/browser/silk.toml --target wasm32-unknown-unknown`);
  }
  return directory;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  console.log(nativeRoot());
}
