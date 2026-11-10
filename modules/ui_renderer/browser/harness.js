// Browser runtime only. Silk owns Chromium, process failures and pixel comparisons.
// The exact manifest-pinned native sources are modules, not host automation scripts.
globalThis.graphicsInitialize = async ({ schema, host, runner, wasm }) => {
  const moduleURL = source => URL.createObjectURL(new Blob([source], { type: 'text/javascript' }));
  const schemaURL = moduleURL(schema);
  const hostURL = moduleURL(host.replaceAll("'./generated_schema.ts'", JSON.stringify(schemaURL)));
  const runnerURL = moduleURL(runner.replaceAll("'./host.ts'", JSON.stringify(hostURL)));
  const { runSamples } = await import(runnerURL);
  globalThis.graphicsSample = async index => (await runSamples(wasm, [index], 60000))[0];
  return true;
};
