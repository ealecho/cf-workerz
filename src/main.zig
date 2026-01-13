const std = @import("std");
const allocator = std.heap.page_allocator;

// Re-export APIs
pub const apis = @import("apis/main.zig");
pub const Cache = apis.Cache;
pub const CacheOptions = apis.CacheOptions;
pub const CacheQueryOptions = apis.CacheQueryOptions;
pub const D1Database = apis.D1Database;
pub const BatchSQLSuccess = apis.BatchSQLSuccess;
pub const SQLSuccess = apis.SQLSuccess;
pub const PreparedStatement = apis.PreparedStatement;
pub const D1Query = apis.D1Query;
pub const D1Result = apis.D1Result;
pub const D1Rows = apis.D1Rows;
pub const CommandMeta = apis.CommandMeta;
pub const EmptyMeta = apis.EmptyMeta;
pub const DurableObject = apis.DurableObject;
pub const DurableObjectId = apis.DurableObjectId;
pub const DurableObjectStub = apis.DurableObjectStub;
pub const DurableObjectNamespace = apis.DurableObjectNamespace;
pub const DurableObjectState = apis.DurableObjectState;
pub const DurableObjectStorage = apis.DurableObjectStorage;
pub const StorageListOptions = apis.StorageListOptions;
pub const StorageListResult = apis.StorageListResult;
pub const UniqueIdOptions = apis.UniqueIdOptions;
pub const DOWebSocketIterator = apis.WebSocketIterator;
pub const fetch = apis.fetch;
pub const KVNamespace = apis.KVNamespace;
pub const GetOptions = apis.GetOptions;
pub const PutValue = apis.PutValue;
pub const PutOptions = apis.PutOptions;
pub const ListOptions = apis.ListOptions;
pub const ListResult = apis.ListResult;
pub const R2Bucket = apis.R2Bucket;
pub const R2Value = apis.R2Value;
pub const R2HTTPMetadata = apis.R2HTTPMetadata;
pub const R2Range = apis.R2Range;
pub const R2Object = apis.R2Object;
pub const R2ObjectBody = apis.R2ObjectBody;
pub const R2Objects = apis.R2Objects;
pub const R2Conditional = apis.R2Conditional;
pub const OnlyIf = apis.OnlyIf;
pub const R2GetOptions = apis.R2GetOptions;
pub const R2PutOptions = apis.R2PutOptions;
pub const R2ListOptions = apis.R2ListOptions;
pub const R2GetResponse = apis.R2GetResponse;
pub const WebSocket = apis.WebSocket;
pub const WebSocketPair = apis.WebSocketPair;
pub const WebSocketReadyState = apis.WebSocketReadyState;
pub const WebSocketCloseCode = apis.WebSocketCloseCode;
pub const WebSocketIncomingMessage = apis.WebSocketIncomingMessage;
pub const MessageEvent = apis.MessageEvent;
pub const CloseEvent = apis.CloseEvent;
pub const ErrorEvent = apis.ErrorEvent;
pub const WebSocketEvent = apis.WebSocketEvent;
pub const wsConnect = apis.wsConnect;
pub const wsConnectWithProtocols = apis.wsConnectWithProtocols;

// Durable Objects - additional exports
pub const GetAlarmOptions = apis.GetAlarmOptions;
pub const SetAlarmOptions = apis.SetAlarmOptions;
pub const ScheduledTime = apis.ScheduledTime;
pub const SqlStorage = apis.SqlStorage;
pub const SqlCursor = apis.SqlCursor;

// Queues API
pub const Queue = apis.Queue;
pub const QueueContentType = apis.QueueContentType;
pub const QueueSendOptions = apis.QueueSendOptions;
pub const QueueSendBatchOptions = apis.QueueSendBatchOptions;
pub const MessageSendRequest = apis.MessageSendRequest;
pub const Message = apis.Message;
pub const MessageBatch = apis.MessageBatch;
pub const MessageIterator = apis.MessageIterator;
pub const QueueRetryOptions = apis.QueueRetryOptions;

// Service Bindings API
pub const Fetcher = apis.Fetcher;

// Workers AI API
pub const AI = apis.AI;
pub const TextGenerationOptions = apis.TextGenerationOptions;
pub const ChatMessage = apis.ChatMessage;
pub const ImageGenerationOptions = apis.ImageGenerationOptions;
pub const AiTextResponse = apis.AiTextResponse;
pub const AiUsage = apis.AiUsage;
pub const AiEmbeddingResponse = apis.AiEmbeddingResponse;

// Crypto API
pub const getRandomValues = apis.getRandomValues;
pub const randomUUID = apis.randomUUID;
pub const DigestAlgorithm = apis.DigestAlgorithm;
pub const KeyUsage = apis.KeyUsage;
pub const KeyFormat = apis.KeyFormat;
pub const CryptoKey = apis.CryptoKey;
pub const CryptoKeyPair = apis.CryptoKeyPair;
pub const SubtleCrypto = apis.SubtleCrypto;
pub const DigestStream = apis.DigestStream;
pub const SubtleCryptoEncryptAlgorithm = apis.SubtleCryptoEncryptAlgorithm;
pub const SubtleCryptoGenerateKeyAlgorithm = apis.SubtleCryptoGenerateKeyAlgorithm;
pub const SubtleCryptoImportKeyAlgorithm = apis.SubtleCryptoImportKeyAlgorithm;
pub const SubtleCryptoSignAlgorithm = apis.SubtleCryptoSignAlgorithm;
pub const SubtleCryptoDeriveKeyAlgorithm = apis.SubtleCryptoDeriveKeyAlgorithm;
pub const sha256 = apis.sha256;
pub const sha1 = apis.sha1;
pub const sha512 = apis.sha512;
pub const md5 = apis.md5;

// Re-export bindings
pub const bindings = @import("bindings/main.zig");
pub const Array = bindings.Array;
pub const Uint8Array = bindings.Uint8Array;
pub const ArrayBuffer = bindings.ArrayBuffer;
pub const Blob = bindings.Blob;
pub const Body = bindings.Body;
pub const BodyInit = bindings.BodyInit;
pub const BodyMixin = bindings.BodyMixin;
pub const Cf = bindings.Cf;
pub const Classes = bindings.Classes;
pub const Env = bindings.Env;
pub const ExecutionContext = bindings.ExecutionContext;
pub const FormData = bindings.FormData;
pub const FormDataIterator = bindings.FormDataIterator;
pub const FormDataEntry = bindings.FormDataEntry;
pub const FormEntry = bindings.FormEntry;
pub const File = bindings.File;
pub const FileOptions = bindings.FileOptions;
pub const Function = bindings.Function;
pub const AsyncFunction = bindings.AsyncFunction;
pub const Headers = bindings.Headers;
pub const HeadersIterator = bindings.HeadersIterator;
pub const HeaderEntry = bindings.HeaderEntry;
pub const Object = bindings.Object;
pub const Record = bindings.Record;
pub const Request = bindings.Request;
pub const RequestInit = bindings.RequestInit;
pub const RequestInfo = bindings.RequestInfo;
pub const RequestOptions = bindings.RequestOptions;
pub const Redirect = bindings.Redirect;
pub const Response = bindings.Response;
pub const ResponseInit = bindings.ResponseInit;
pub const String = bindings.String;
pub const URL = bindings.URL;
pub const URLSearchParams = bindings.URLSearchParams;
pub const URLSearchParamsIterator = bindings.URLSearchParamsIterator;
pub const URLSearchParamsEntry = bindings.URLSearchParamsEntry;
pub const jsFree = bindings.jsFree;
pub const jsLog = bindings.jsLog;
pub const jsResolve = bindings.jsResolve;
pub const Null = bindings.Null;
pub const Undefined = bindings.Undefined;
pub const True = bindings.True;
pub const False = bindings.False;

// Streams API
pub const ReadableStream = bindings.ReadableStream;
pub const WritableStream = bindings.WritableStream;
pub const TransformStream = bindings.TransformStream;
pub const CompressionStream = bindings.CompressionStream;
pub const DecompressionStream = bindings.DecompressionStream;
pub const CompressionFormat = bindings.CompressionFormat;
pub const ReadableStreamDefaultReader = bindings.ReadableStreamDefaultReader;
pub const WritableStreamDefaultWriter = bindings.WritableStreamDefaultWriter;
pub const PipeToOptions = bindings.PipeToOptions;
pub const PipeThroughOptions = bindings.PipeThroughOptions;
pub const ReadResult = bindings.ReadResult;
pub const Date = bindings.Date;

// Re-export HTTP types
pub const http = @import("http/main.zig");
pub const StatusCode = http.StatusCode;
pub const Method = http.Method;
pub const Version = http.Version;

// Re-export worker types
pub const worker = @import("worker/main.zig");
pub const FetchContext = worker.FetchContext;
pub const ScheduledContext = worker.ScheduledContext;
pub const ScheduledEvent = worker.ScheduledEvent;
pub const HandlerFn = worker.HandlerFn;
pub const ScheduleFn = worker.ScheduleFn;
pub const Route = worker.Route;

// JSON body helper for ergonomic request parsing
pub const JsonBody = worker.JsonBody;

// Re-export Router
pub const router = @import("router.zig");
pub const Router = router.Route; // Main router entry point
pub const Params = router.Params;
pub const matchPath = router.matchPath;
pub const MAX_PARAMS = router.MAX_PARAMS;
pub const Middleware = router.Middleware;
pub const MiddlewareFn = router.MiddlewareFn;
pub const MAX_MIDDLEWARE = router.MAX_MIDDLEWARE;

// Re-export auth module
pub const auth = @import("auth/main.zig");

// Re-export base64 utilities
pub const base64 = @import("utils/base64.zig");

// ** EXPORTS **

// ALLOCATION
// NOTE: These allocation exports are for JavaScript interop.
// The JS side tracks allocation sizes and passes them back for deallocation.
export fn alloc(size: usize) ?[*]u8 {
    const data = allocator.alloc(u8, size) catch return null;
    return data.ptr;
}

export fn allocSentinel(size: usize) ?[*:0]u8 {
    const data = allocator.allocSentinel(u8, size, 0) catch return null;
    return data.ptr;
}

// Free memory allocated by alloc()
// The JS side must track the size and pass it here
export fn freeSize(ptr: [*]u8, size: usize) void {
    const slice = ptr[0..size];
    allocator.free(slice);
}

// Legacy free - kept for compatibility but size tracking may be required
// For page_allocator, we can free using the rawFree with null length
// This will work for page-aligned allocations
export fn free(ptr: [*]u8, size: usize) void {
    const slice = ptr[0..size];
    allocator.free(slice);
}
