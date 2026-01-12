// Re-export all API modules explicitly (Zig 0.11+ removed usingnamespace)

// AI API
const ai = @import("ai.zig");
pub const AI = ai.AI;
pub const TextGenerationOptions = ai.TextGenerationOptions;
pub const ChatMessage = ai.ChatMessage;
pub const ImageGenerationOptions = ai.ImageGenerationOptions;
pub const AiTextResponse = ai.AiTextResponse;
pub const AiUsage = ai.AiUsage;
pub const AiEmbeddingResponse = ai.AiEmbeddingResponse;

// Cache API
const cache = @import("cache.zig");
pub const Cache = cache.Cache;
pub const CacheOptions = cache.CacheOptions;
pub const CacheQueryOptions = cache.CacheQueryOptions;

// Crypto API
const crypto = @import("crypto.zig");
pub const getRandomValues = crypto.getRandomValues;
pub const randomUUID = crypto.randomUUID;
pub const DigestAlgorithm = crypto.DigestAlgorithm;
pub const KeyUsage = crypto.KeyUsage;
pub const KeyFormat = crypto.KeyFormat;
pub const Data = crypto.Data;
pub const Hash = crypto.Hash;
pub const CryptoKeyKeyAlgorithm = crypto.CryptoKeyKeyAlgorithm;
pub const SubtleCryptoEncryptAlgorithm = crypto.SubtleCryptoEncryptAlgorithm;
pub const SubtleCryptoGenerateKeyAlgorithm = crypto.SubtleCryptoGenerateKeyAlgorithm;
pub const SubtleCryptoImportKeyAlgorithm = crypto.SubtleCryptoImportKeyAlgorithm;
pub const SubtleCryptoSignAlgorithm = crypto.SubtleCryptoSignAlgorithm;
pub const SubtleCryptoDeriveKeyAlgorithm = crypto.SubtleCryptoDeriveKeyAlgorithm;
pub const CryptoKey = crypto.CryptoKey;
pub const CryptoKeyPair = crypto.CryptoKeyPair;
pub const DigestStream = crypto.DigestStream;
pub const SubtleCrypto = crypto.SubtleCrypto;
pub const sha256 = crypto.sha256;
pub const sha1 = crypto.sha1;
pub const sha512 = crypto.sha512;
pub const md5 = crypto.md5;

// D1 Database API
const d1 = @import("d1.zig");
pub const D1Database = d1.D1Database;
pub const BatchSQLSuccess = d1.BatchSQLSuccess;
pub const SQLSuccess = d1.SQLSuccess;
pub const PreparedStatement = d1.PreparedStatement;
pub const D1Query = d1.D1Query;

// Durable Objects API
const durable = @import("durable.zig");
pub const DurableObject = durable.DurableObject;
pub const DurableObjectId = durable.DurableObjectId;
pub const DurableObjectStub = durable.DurableObjectStub;
pub const DurableObjectNamespace = durable.DurableObjectNamespace;
pub const DurableObjectState = durable.DurableObjectState;
pub const DurableObjectStorage = durable.DurableObjectStorage;
pub const StorageListOptions = durable.StorageListOptions;
pub const StorageListResult = durable.StorageListResult;
pub const UniqueIdOptions = durable.UniqueIdOptions;
pub const WebSocketIterator = durable.WebSocketIterator;
pub const GetAlarmOptions = durable.GetAlarmOptions;
pub const SetAlarmOptions = durable.SetAlarmOptions;
pub const ScheduledTime = durable.ScheduledTime;
pub const SqlStorage = durable.SqlStorage;
pub const SqlCursor = durable.SqlCursor;

// Fetch API
const fetch_api = @import("fetch.zig");
pub const fetch = fetch_api.fetch;

// KV Namespace API
const kv = @import("kv.zig");
pub const KVNamespace = kv.KVNamespace;
pub const GetOptions = kv.GetOptions;
pub const PutValue = kv.PutValue;
pub const PutOptions = kv.PutOptions;
pub const ListOptions = kv.ListOptions;
pub const ListResult = kv.ListResult;

// Queues API
const queues = @import("queues.zig");
pub const Queue = queues.Queue;
pub const QueueContentType = queues.QueueContentType;
pub const QueueSendOptions = queues.QueueSendOptions;
pub const QueueSendBatchOptions = queues.QueueSendBatchOptions;
pub const MessageSendRequest = queues.MessageSendRequest;
pub const Message = queues.Message;
pub const MessageBatch = queues.MessageBatch;
pub const MessageIterator = queues.MessageIterator;
pub const QueueRetryOptions = queues.QueueRetryOptions;

// R2 Bucket API
const r2 = @import("r2.zig");
pub const R2Bucket = r2.R2Bucket;
pub const R2Value = r2.R2Value;
pub const R2HTTPMetadata = r2.R2HTTPMetadata;
pub const R2Range = r2.R2Range;
pub const R2Object = r2.R2Object;
pub const R2ObjectBody = r2.R2ObjectBody;
pub const R2Objects = r2.R2Objects;
pub const R2Conditional = r2.R2Conditional;
pub const OnlyIf = r2.OnlyIf;
pub const R2GetOptions = r2.R2GetOptions;
pub const R2PutOptions = r2.R2PutOptions;
pub const R2ListOptions = r2.R2ListOptions;
pub const R2GetResponse = r2.R2GetResponse;

// Service Bindings API
const service = @import("service.zig");
pub const Fetcher = service.Fetcher;

// Rate Limiting API
const rate_limit = @import("rate_limit.zig");
pub const RateLimiter = rate_limit.RateLimiter;
pub const RateLimitOutcome = rate_limit.RateLimitOutcome;

// WebSocket API
const webSocket = @import("webSocket.zig");
pub const WebSocket = webSocket.WebSocket;
pub const WebSocketPair = webSocket.WebSocketPair;
pub const WebSocketReadyState = webSocket.ReadyState;
pub const WebSocketCloseCode = webSocket.CloseCode;
pub const WebSocketIncomingMessage = webSocket.WebSocketIncomingMessage;
pub const MessageEvent = webSocket.MessageEvent;
pub const CloseEvent = webSocket.CloseEvent;
pub const ErrorEvent = webSocket.ErrorEvent;
pub const WebSocketEvent = webSocket.WebSocketEvent;
pub const wsConnect = webSocket.connect;
pub const wsConnectWithProtocols = webSocket.connectWithProtocols;
