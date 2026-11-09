import { build, run } from './internal.mjs';
run(build('ui_renderer/tests'), [], { timeout: 300000 });
