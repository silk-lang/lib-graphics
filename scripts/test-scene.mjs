import { build, run } from './internal.mjs';
run(build('gpu_scene/tests'), [], { timeout: 120000 });
