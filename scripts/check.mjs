// Internal gate: Silk owns all compilation and unit-test execution.
import { build, manifest, run, silk } from './internal.mjs';

run(process.execPath, ['scripts/embed-shaders.mjs', '--check']);
const cpu = ['atlas', 'codec', 'editor', 'geometry', 'ui_scene', 'vector'];
for (const packagePath of cpu) {
  run(silk, ['check', '--manifest-path', manifest(packagePath)]);
  run(silk, ['test', '--manifest-path', manifest(packagePath), '--root', 'src/tests.silk']);
  run(silk, ['check', '--manifest-path', manifest(packagePath), '--target', 'wasm32-unknown-unknown']);
}
run(build('ui_scene/tests'), ['graphics/ui_scene/tests/goldens']);
for (const packagePath of ['vector/bench', 'vector/filter-bench', 'gpu_scene', 'gpu_scene/tests',
  'ui_renderer', 'ui_renderer/fixtures', 'ui_renderer/tests', 'ui_renderer/bench', 'ui_renderer/browser']) {
  run(silk, ['check', '--manifest-path', manifest(packagePath)]);
}
for (const packagePath of ['gpu_scene', 'ui_renderer', 'ui_renderer/browser']) {
  run(silk, ['check', '--manifest-path', manifest(packagePath), '--target', 'wasm32-unknown-unknown']);
}
run(process.execPath, ['scripts/generate-browser-exports.mjs', '--check']);
if (!process.argv.includes('--skip-native')) {
  run(process.execPath, ['scripts/test-scene.mjs']);
  run(process.execPath, ['scripts/test-ui-renderer.mjs']);
}
