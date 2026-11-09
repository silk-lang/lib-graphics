import { manifest, run, silk } from './internal.mjs';

run(process.execPath, ['scripts/embed-shaders.mjs', '--check']);
for (const packagePath of ['vector', 'vector/bench', 'vector/filter-bench', 'gpu_scene', 'gpu_scene/tests']) {
  run(silk, ['check', '--manifest-path', manifest(packagePath)]);
}
run(silk, ['test', '--manifest-path', manifest('vector'), '--root', 'src/tests.silk']);
if (!process.argv.includes('--skip-native')) run(process.execPath, ['scripts/test-scene.mjs']);
