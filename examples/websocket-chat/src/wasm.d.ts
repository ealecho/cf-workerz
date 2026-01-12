declare module '../zig-out/bin/worker.wasm' {
  const wasmModule: WebAssembly.Module;
  export default wasmModule;
}
