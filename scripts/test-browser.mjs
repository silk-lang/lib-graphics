import { build, run } from './internal.mjs';

const wasm = build('ui_renderer/browser', { wasm: true });
run(process.execPath, ['scripts/generate-browser-exports.mjs', '--check']);
const command = [process.execPath, 'modules/ui_renderer/browser/test.mjs', '--wasm', wasm];
if (process.platform === 'linux') {
  // Linux Chromium requires a display for WebGPU presentation.
  run('xvfb-run', ['--auto-servernum', '--server-args=-screen 0 1280x720x24', ...command]);
} else run(command[0], command.slice(1));
