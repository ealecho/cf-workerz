/**
 * TypeScript runtime for cf-workerz WebSocket Chat example
 * 
 * This includes the ChatRoom Durable Object that handles:
 * - WebSocket connections and message broadcasting
 * - Message persistence in DO storage
 * - Chat history retrieval
 * 
 * Based on Upstash's cloudflare-websockets example.
 */

import wasmModule from '../zig-out/bin/worker.wasm';

// ============================================================================
// Type Definitions
// ============================================================================

const enum ReservedHeapPtr {
  NULL = 1,
  UNDEFINED = 2,
  TRUE = 3,
  FALSE = 4,
  INFINITY = 5,
  NAN = 6,
}

const DEFAULT_HEAP_SIZE = 6;
type HeapPtr = number;

interface WASMExports {
  memory: WebAssembly.Memory;
  alloc: (size: number) => number;
  allocSentinel: (size: number) => number;
  handleFetch: (ctxPtr: HeapPtr) => void;
}

interface WorkerContext {
  path: string;
  req: Request;
  env: Env;
  ctx: ExecutionContext;
  resolved: boolean;
  resolve?: (response: Response) => void;
}

interface Env {
  CHAT_ROOM: DurableObjectNamespace;
  [key: string]: unknown;
}

interface ChatMessage {
  userId: string;
  message: string;
  timestamp: number;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type ClassConstructor = new (...args: any[]) => any;

const CLASSES: ClassConstructor[] = [
  Array, Object, Date, Map, Set, WeakMap, WeakSet,
  Int8Array, Uint8Array, Uint8ClampedArray, Int16Array, Uint16Array,
  Int32Array, Uint32Array, BigInt64Array, BigUint64Array,
  ArrayBuffer, SharedArrayBuffer, DataView,
  Request, Response, Headers, FormData, File, Blob,
  URL, URLPattern, URLSearchParams,
  ReadableStream, WritableStream, TransformStream,
  CompressionStream, DecompressionStream,
  FixedLengthStream, WebSocketPair,
];

// ============================================================================
// Text Encoding
// ============================================================================

const textDecoder = new TextDecoder();
const textEncoder = new TextEncoder();

// ============================================================================
// CORS Headers Helper
// ============================================================================

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

// ============================================================================
// ChatRoom Durable Object
// ============================================================================

export class ChatRoom implements DurableObject {
  private state: DurableObjectState;
  private sessions: Map<WebSocket, string> = new Map();
  private messages: ChatMessage[] = [];

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    
    // Load stored messages on initialization
    this.state.blockConcurrencyWhile(async () => {
      const stored = await this.state.storage.get<ChatMessage[]>('messages');
      this.messages = stored ?? [];
    });
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // Handle HTTP endpoints
    if (path === '/history') {
      return this.handleHistory();
    }

    if (path === '/message' && request.method === 'POST') {
      return this.handleHttpMessage(request);
    }

    // Handle WebSocket upgrade
    const upgradeHeader = request.headers.get('Upgrade');
    if (!upgradeHeader || upgradeHeader !== 'websocket') {
      return new Response('Expected WebSocket', { status: 426 });
    }

    const webSocketPair = new WebSocketPair();
    const [client, server] = Object.values(webSocketPair);

    server.accept();

    // Handle WebSocket messages
    server.addEventListener('message', async (event) => {
      try {
        const data = JSON.parse(event.data as string);

        if (data.type === 'init') {
          // Store the client's userId
          this.sessions.set(server, data.userId);

          // Send message history
          if (this.messages.length > 0) {
            const history = this.messages.slice(-20); // Last 20 messages
            server.send(JSON.stringify({
              type: 'history',
              messages: history,
            }));
          }

          // Broadcast join notification
          this.broadcast({
            type: 'system',
            message: `${data.userId} joined the chat`,
            timestamp: Date.now(),
          }, server);

          return;
        }

        if (data.type === 'message') {
          const userId = this.sessions.get(server);
          if (!userId) return;

          const message: ChatMessage = {
            userId,
            message: data.content,
            timestamp: Date.now(),
          };

          // Store message
          this.messages.push(message);
          
          // Keep only last 100 messages
          if (this.messages.length > 100) {
            this.messages = this.messages.slice(-100);
          }
          
          // Persist to storage
          await this.state.storage.put('messages', this.messages);

          // Broadcast to all connected clients
          this.broadcast(message);
        }
      } catch (error) {
        console.error('Error handling message:', error);
      }
    });

    // Handle WebSocket close
    server.addEventListener('close', () => {
      const userId = this.sessions.get(server);
      this.sessions.delete(server);

      if (userId) {
        this.broadcast({
          type: 'system',
          message: `${userId} left the chat`,
          timestamp: Date.now(),
        });
      }
    });

    // Handle WebSocket error
    server.addEventListener('error', (event) => {
      console.error('WebSocket error:', event);
      this.sessions.delete(server);
    });

    return new Response(null, {
      status: 101,
      webSocket: client,
    });
  }

  private broadcast(message: unknown, excludeSocket?: WebSocket): void {
    const messageStr = JSON.stringify(message);
    
    this.sessions.forEach((_, socket) => {
      if (socket !== excludeSocket && socket.readyState === WebSocket.READY_STATE_OPEN) {
        try {
          socket.send(messageStr);
        } catch (error) {
          console.error('Error sending to socket:', error);
        }
      }
    });
  }

  private handleHistory(): Response {
    const history = this.messages.slice(-20);
    return new Response(JSON.stringify({
      type: 'history',
      messages: history,
      count: history.length,
    }), {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  private async handleHttpMessage(request: Request): Promise<Response> {
    try {
      const data = await request.json() as { userId: string; content: string };
      
      if (!data.userId || !data.content) {
        return new Response(JSON.stringify({ error: 'Missing userId or content' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }

      const message: ChatMessage = {
        userId: data.userId,
        message: data.content,
        timestamp: Date.now(),
      };

      // Store message
      this.messages.push(message);
      if (this.messages.length > 100) {
        this.messages = this.messages.slice(-100);
      }
      await this.state.storage.put('messages', this.messages);

      // Broadcast to all WebSocket clients
      this.broadcast(message);

      return new Response(JSON.stringify({
        success: true,
        message,
        connectedClients: this.sessions.size,
      }), {
        headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
      });
    } catch (error) {
      return new Response(JSON.stringify({ error: 'Invalid JSON' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
      });
    }
  }
}

// ============================================================================
// Heap
// ============================================================================

class Heap extends Map<HeapPtr, unknown> {
  private counter = 7;

  constructor() {
    super();
    this.set(ReservedHeapPtr.NULL, null);
    this.set(ReservedHeapPtr.UNDEFINED, undefined);
    this.set(ReservedHeapPtr.TRUE, true);
    this.set(ReservedHeapPtr.FALSE, false);
    this.set(ReservedHeapPtr.INFINITY, Infinity);
    this.set(ReservedHeapPtr.NAN, NaN);
  }

  put(value: unknown): HeapPtr {
    if (value === null) return ReservedHeapPtr.NULL;
    if (value === undefined) return ReservedHeapPtr.UNDEFINED;
    if (value === true) return ReservedHeapPtr.TRUE;
    if (value === false) return ReservedHeapPtr.FALSE;
    if (value === Infinity) return ReservedHeapPtr.INFINITY;
    if (typeof value === 'number' && Number.isNaN(value)) return ReservedHeapPtr.NAN;

    const key = this.counter++;
    if (this.counter >= 100_000) this.counter = 7;
    this.set(key, value);
    return key;
  }
}

// ============================================================================
// WASM Runtime
// ============================================================================

class WASMRuntime {
  private heap = new Heap();
  private instance: WebAssembly.Instance | null = null;
  private wasmMemory: Uint8Array | null = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private handleFetchPromising: ((ctxPtr: HeapPtr) => Promise<any>) | null = null;

  private buildEnvFunctions(): Record<string, unknown> {
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    const self = this;

    return {
      jsFree(ptr: HeapPtr): void {
        if (ptr <= DEFAULT_HEAP_SIZE) return;
        self.heap.delete(ptr);
      },

      jsHeapGetNum(ptr: HeapPtr): number {
        return self.heap.get(ptr) as number;
      },

      jsStringSet(ptr: number, len: number): HeapPtr {
        const string = self.getString(ptr, len);
        return self.heap.put(string);
      },

      jsStringGet(stringPtr: HeapPtr): number {
        const string = self.heap.get(stringPtr) as string;
        return self.putString(string);
      },

      jsStringThrow(stringPtr: HeapPtr): never {
        throw new Error(self.heap.get(stringPtr) as string);
      },

      jsArrayPush(arrayPtr: HeapPtr, itemPtr: HeapPtr): void {
        const array = self.heap.get(arrayPtr) as unknown[];
        const item = self.heap.get(itemPtr);
        array.push(item);
      },

      jsArrayPushNum(arrayPtr: HeapPtr, num: number): void {
        const array = self.heap.get(arrayPtr) as unknown[];
        array.push(num);
      },

      jsArrayGet(arrayPtr: HeapPtr, pos: number): HeapPtr {
        const array = self.heap.get(arrayPtr) as unknown[];
        return self.heap.put(array[pos]);
      },

      jsArrayGetNum(arrayPtr: HeapPtr, pos: number): number {
        const array = self.heap.get(arrayPtr) as unknown[];
        return array[pos] as number;
      },

      jsObjectHas(objPtr: HeapPtr, keyPtr: HeapPtr): HeapPtr {
        const obj = self.heap.get(objPtr) as Record<string, unknown>;
        const key = self.heap.get(keyPtr) as string;
        return self.heap.put(obj[key] !== undefined);
      },

      jsObjectSet(objPtr: HeapPtr, keyPtr: HeapPtr, valuePtr: HeapPtr): void {
        const obj = self.heap.get(objPtr) as Record<string, unknown>;
        const key = self.heap.get(keyPtr) as string;
        const value = self.heap.get(valuePtr);
        obj[key] = value;
      },

      jsObjectSetNum(objPtr: HeapPtr, keyPtr: HeapPtr, value: number): void {
        const obj = self.heap.get(objPtr) as Record<string, unknown>;
        const key = self.heap.get(keyPtr) as string;
        obj[key] = value;
      },

      jsObjectGet(objPtr: HeapPtr, keyPtr: HeapPtr): HeapPtr {
        const obj = self.heap.get(objPtr) as Record<string, unknown>;
        const key = self.heap.get(keyPtr) as string;
        const value = obj[key];
        return self.heap.put(typeof value === 'function' ? value.bind(obj) : value);
      },

      jsObjectGetNum(objPtr: HeapPtr, keyPtr: HeapPtr): number {
        const obj = self.heap.get(objPtr) as Record<string, unknown>;
        const key = self.heap.get(keyPtr) as string;
        const val = Number(obj[key]);
        return isNaN(val) ? 0 : val;
      },

      jsStringify(objPtr: HeapPtr): HeapPtr {
        const obj = self.heap.get(objPtr);
        return self.heap.put(JSON.stringify(obj));
      },

      jsParse(strPtr: HeapPtr): HeapPtr {
        const str = self.heap.get(strPtr) as string;
        return self.heap.put(JSON.parse(str));
      },

      jsFnCall(funcPtr: HeapPtr, argsPtr: HeapPtr): HeapPtr {
        const func = self.heap.get(funcPtr) as (...args: unknown[]) => unknown;
        const args = self.heap.get(argsPtr);
        let res: unknown;
        if (args === undefined || args === null) {
          res = func();
        } else if (Array.isArray(args)) {
          res = func(...args);
        } else {
          res = func(args);
        }
        return self.heap.put(res);
      },

      jsAsyncFnCall: null, // Will be replaced

      jsResolve(ctxPtr: HeapPtr, resPtr: HeapPtr): void {
        const ctx = self.heap.get(ctxPtr) as WorkerContext;
        const res = self.heap.get(resPtr) as Response;
        ctx.resolve?.(res);
      },

      jsLog(stringPtr: HeapPtr): void {
        console.log(self.heap.get(stringPtr));
      },

      jsSize(ptr: HeapPtr): number {
        const data = self.heap.get(ptr);
        if (data === null || data === undefined) return 0;
        if (typeof data === 'object' && 'byteLength' in data) {
          return (data as ArrayBufferLike).byteLength;
        }
        if (typeof data === 'string' || Array.isArray(data)) {
          return data.length;
        }
        return 0;
      },

      jsToBytes(ptr: HeapPtr): HeapPtr {
        const data = self.heap.get(ptr);
        let bytes: Uint8Array;
        if (data instanceof ArrayBuffer) {
          bytes = new Uint8Array(data);
        } else if (data instanceof Uint8Array) {
          bytes = data;
        } else if (typeof data === 'string') {
          bytes = textEncoder.encode(data);
        } else {
          throw new Error('jsToBytes: unsupported data type');
        }
        return self.putBytes(bytes);
      },

      jsToBuffer(ptr: number, len: number): HeapPtr {
        const data = self.getBytes(ptr, len);
        return self.heap.put(data.buffer);
      },

      jsGetClass(classPos: number): HeapPtr {
        return self.heap.put(CLASSES[classPos]);
      },

      jsCreateClass(classPos: number, argsPtr: HeapPtr): HeapPtr {
        const ClassCtor = CLASSES[classPos];
        const args = self.heap.get(argsPtr);
        let instance: unknown;
        if (args === undefined || args === null) {
          instance = new ClassCtor();
        } else if (Array.isArray(args)) {
          instance = new ClassCtor(...args);
        } else {
          instance = new ClassCtor(args);
        }
        return self.heap.put(instance);
      },

      jsEqual(aPtr: HeapPtr, bPtr: HeapPtr): HeapPtr {
        const a = self.heap.get(aPtr);
        const b = self.heap.get(bPtr);
        return self.heap.put(a === b);
      },

      jsDeepEqual(aPtr: HeapPtr, bPtr: HeapPtr): HeapPtr {
        const a = self.heap.get(aPtr);
        const b = self.heap.get(bPtr);
        try {
          return self.heap.put(JSON.stringify(a) === JSON.stringify(b));
        } catch {
          return self.heap.put(false);
        }
      },

      jsInstanceOf(classPos: number, objPtr: HeapPtr): HeapPtr {
        const ClassCtor = CLASSES[classPos];
        const obj = self.heap.get(objPtr);
        return self.heap.put(obj instanceof ClassCtor);
      },

      jsWaitUntil(ctxPtr: HeapPtr): HeapPtr {
        const ctx = self.heap.get(ctxPtr) as WorkerContext;
        const resolver: { resolve: (value?: unknown) => void } = { resolve: () => {} };
        ctx.ctx.waitUntil(
          new Promise((resolve) => {
            resolver.resolve = resolve;
          })
        );
        return self.heap.put(resolver.resolve);
      },

      jsWaitUntilResolve(resolverPtr: HeapPtr, valuePtr: HeapPtr): void {
        const resolver = self.heap.get(resolverPtr) as (value?: unknown) => void;
        const value = self.heap.get(valuePtr);
        resolver(value);
      },

      jsPassThroughOnException(ctxPtr: HeapPtr): void {
        const ctx = self.heap.get(ctxPtr) as WorkerContext;
        ctx.ctx.passThroughOnException();
      },

      jsCacheGet(keyPtr: HeapPtr): HeapPtr {
        const key = self.heap.get(keyPtr) as string | undefined;
        const cache = key !== undefined ? caches.open(key) : caches.default;
        return self.heap.put(cache);
      },

      jsFetch: null, // Will be replaced

      jsRandomUUID(): number {
        const uuid = crypto.randomUUID();
        return self.putString(uuid);
      },

      jsGetRandomValues(bufPtr: HeapPtr): void {
        const buffer = self.heap.get(bufPtr) as Uint8Array;
        crypto.getRandomValues(buffer);
      },

      jsGetSubtleCrypto(): HeapPtr {
        return self.heap.put(crypto.subtle);
      },
    };
  }

  private createAsyncImports(): Record<string, WebAssembly.Suspending> {
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    const self = this;

    const jsAsyncFnCallImpl = async (funcPtr: HeapPtr, argsPtr: HeapPtr): Promise<HeapPtr> => {
      const func = self.heap.get(funcPtr) as (...args: unknown[]) => Promise<unknown>;
      const args = self.heap.get(argsPtr);

      let result: unknown;
      if (args === undefined || args === null) {
        result = await func();
      } else if (Array.isArray(args)) {
        result = await func(...args);
      } else {
        result = await func(args);
      }

      return self.heap.put(result);
    };

    const jsFetchImpl = async (urlPtr: HeapPtr, initPtr: HeapPtr): Promise<HeapPtr> => {
      const url = self.heap.get(urlPtr) as string | Request;
      const init = self.heap.get(initPtr) as RequestInit | undefined;

      try {
        const response = await fetch(url, init);
        return self.heap.put(response);
      } catch (err) {
        console.error('Fetch failed:', err);
        return self.heap.put(new Response(null, { status: 502 }));
      }
    };

    // Rate Limiting: Call limiter.limit({ key }) and return 1 for success, 0 for failure
    const jsRateLimiterLimitImpl = async (
      limiterPtr: HeapPtr,
      keyPtr: number,
      keyLen: number
    ): Promise<number> => {
      const limiter = self.heap.get(limiterPtr) as { limit: (opts: { key: string }) => Promise<{ success: boolean }> };
      const key = self.getString(keyPtr, keyLen);
      
      try {
        const result = await limiter.limit({ key });
        return result.success ? 1 : 0;
      } catch (err) {
        console.error('Rate limiter error:', err);
        return 0; // Fail closed on error
      }
    };

    return {
      jsAsyncFnCall: new WebAssembly.Suspending(jsAsyncFnCallImpl),
      jsFetch: new WebAssembly.Suspending(jsFetchImpl),
      js_rate_limiter_limit: new WebAssembly.Suspending(jsRateLimiterLimitImpl),
    };
  }

  private init(): void {
    if (this.instance) return;

    const envFunctions = this.buildEnvFunctions();
    const asyncImports = this.createAsyncImports();
    Object.assign(envFunctions, asyncImports);

    this.instance = new WebAssembly.Instance(wasmModule, {
      env: {
        memoryBase: 0,
        tableBase: 0,
        memory: new WebAssembly.Memory({ initial: 512 }),
        ...envFunctions,
      },
    });

    const exports = this.instance.exports as unknown as WASMExports;
    if (exports.handleFetch) {
      this.handleFetchPromising = WebAssembly.promising(exports.handleFetch);
    }
  }

  private get exports(): WASMExports {
    return this.instance!.exports as unknown as WASMExports;
  }

  private alloc(size: number): number {
    return this.exports.alloc(size);
  }

  private allocSentinel(size: number): number {
    return this.exports.allocSentinel(size);
  }

  private getBytes(ptr: number, len: number): Uint8Array {
    const view = this.getMemory();
    const slice = view.subarray(ptr, ptr + len);
    const copy = new Uint8Array(slice.byteLength);
    copy.set(slice);
    return copy;
  }

  private putBytes(buf: Uint8Array, ptr?: number): HeapPtr {
    const len = buf.byteLength;
    if (ptr === undefined) ptr = this.alloc(len);
    const view = this.getMemory();
    view.subarray(ptr, ptr + len).set(buf);
    return ptr;
  }

  private getString(ptr: number, len: number): string {
    return textDecoder.decode(this.getBytes(ptr, len));
  }

  private putString(str: string): number {
    const buf = textEncoder.encode(str);
    const len = buf.byteLength;
    const ptr = this.allocSentinel(len);
    const view = this.getMemory();
    view.subarray(ptr, ptr + len).set(buf);
    return ptr;
  }

  private getMemory(): Uint8Array {
    const memory = this.exports.memory;
    if (!this.wasmMemory || this.wasmMemory.buffer !== memory.buffer) {
      this.wasmMemory = new Uint8Array(memory.buffer);
    }
    return this.wasmMemory;
  }

  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    this.init();

    const url = new URL(request.url);
    const context: WorkerContext = {
      path: url.pathname,
      req: request,
      env: env,
      ctx: ctx,
      resolved: false,
    };

    return new Promise(async (resolve) => {
      context.resolve = (response: Response) => {
        context.resolved = true;
        resolve(response);
      };

      if (!this.handleFetchPromising) {
        resolve(new Response('handleFetch not exported from WASM', { status: 500 }));
        return;
      }

      const ctxId = this.heap.put(context);

      try {
        await this.handleFetchPromising(ctxId);
      } catch (err) {
        console.error('WASM execution error:', err);
        if (!context.resolved) {
          const message = err instanceof Error ? err.message : String(err);
          resolve(new Response(`WASM error: ${message}`, { status: 500 }));
        }
        return;
      }

      if (!context.resolved) {
        resolve(new Response('No response from handler', { status: 500 }));
      }
    });
  }
}

// ============================================================================
// Export Worker and Durable Object
// ============================================================================

const runtime = new WASMRuntime();

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return runtime.fetch(request, env, ctx);
  },
};
