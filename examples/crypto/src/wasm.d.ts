// Type declarations for WASM modules
declare module '*.wasm' {
  const wasmModule: WebAssembly.Module;
  export default wasmModule;
}

// JSPI type declarations for WebAssembly
declare namespace WebAssembly {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  class Suspending {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    constructor(fn: (...args: any[]) => Promise<any>);
  }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  function promising(fn: (...args: any[]) => any): (...args: any[]) => Promise<any>;
}
