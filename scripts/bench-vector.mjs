import { benchmark } from './benchmark.mjs';
benchmark({ name: 'vector', packagePath: 'vector/bench', reference: 'tiny-skia',
  binaryName: 'vector-bench-tiny-skia', iterations: 20,
  scenes: ['fills', 'strokes', 'gradients', 'polygon', 'icons', 'images'] });
