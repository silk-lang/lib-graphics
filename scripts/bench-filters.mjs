import { benchmark } from './benchmark.mjs';
benchmark({ name: 'filters', packagePath: 'vector/filter-bench', reference: 'resvg',
  binaryName: 'filter-bench-resvg', iterations: 15, baseline: true,
  scenes: ['blur4', 'blur16', 'saturate', 'dilate3', 'gamma', 'sharpen', 'turbulence', 'lighting', 'displace'] });
