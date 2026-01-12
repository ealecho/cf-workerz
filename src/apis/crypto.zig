const std = @import("std");
const common = @import("../bindings/common.zig");
const Classes = common.Classes;
const jsFree = common.jsFree;
const jsCreateClass = common.jsCreateClass;
const toJSBool = common.toJSBool;
const function = @import("../bindings/function.zig");
const jsAsyncFnCall = function.jsAsyncFnCall;
const jsFnCall = function.jsFnCall;
const Array = @import("../bindings/array.zig").Array;
const ArrayBuffer = @import("../bindings/arraybuffer.zig").ArrayBuffer;
const object = @import("../bindings/object.zig");
const Object = object.Object;
const getObjectValue = object.getObjectValue;
const getObjectValueNum = object.getObjectValueNum;
const string = @import("../bindings/string.zig");
const String = string.String;
const getStringFree = string.getStringFree;

// ============================================================================
// External JS Bindings
// ============================================================================

pub extern fn jsGetRandomValues(bufPtr: u32) void;
pub extern fn jsRandomUUID() [*:0]const u8;
pub extern fn jsGetSubtleCrypto() u32;

// ============================================================================
// Basic Crypto Functions
// ============================================================================

/// Fill a buffer with cryptographically secure random values.
/// The buffer must be pre-allocated.
pub fn getRandomValues(buf: []u8) void {
    const ab = ArrayBuffer.new(buf);
    defer ab.free();
    const uint8 = jsCreateClass(@intFromEnum(Classes.Uint8Array), ab.id);
    defer jsFree(uint8);
    jsGetRandomValues(uint8);
    // Copy back the random values
    const result = ab.bytes();
    @memcpy(buf, result);
}

/// Generate a random UUID v4 string.
/// Returns a slice that is valid until the next call.
pub fn randomUUID() []const u8 {
    const rand = jsRandomUUID();
    return std.mem.span(rand);
}

// ============================================================================
// Digest Algorithm Enum
// ============================================================================

/// Supported hash algorithms for digest operations.
pub const DigestAlgorithm = enum {
    @"SHA-1",
    @"SHA-256",
    @"SHA-384",
    @"SHA-512",
    MD5,

    pub fn toString(self: DigestAlgorithm) []const u8 {
        return switch (self) {
            .@"SHA-1" => "SHA-1",
            .@"SHA-256" => "SHA-256",
            .@"SHA-384" => "SHA-384",
            .@"SHA-512" => "SHA-512",
            .MD5 => "MD5",
        };
    }
};

// ============================================================================
// Key Usages
// ============================================================================

/// Possible usages for a CryptoKey.
pub const KeyUsage = enum {
    encrypt,
    decrypt,
    sign,
    verify,
    deriveKey,
    deriveBits,
    wrapKey,
    unwrapKey,

    pub fn toString(self: KeyUsage) []const u8 {
        return switch (self) {
            .encrypt => "encrypt",
            .decrypt => "decrypt",
            .sign => "sign",
            .verify => "verify",
            .deriveKey => "deriveKey",
            .deriveBits => "deriveBits",
            .wrapKey => "wrapKey",
            .unwrapKey => "unwrapKey",
        };
    }
};

/// Key format for import/export operations.
pub const KeyFormat = enum {
    raw,
    pkcs8,
    spki,
    jwk,

    pub fn toString(self: KeyFormat) []const u8 {
        return switch (self) {
            .raw => "raw",
            .pkcs8 => "pkcs8",
            .spki => "spki",
            .jwk => "jwk",
        };
    }
};

// ============================================================================
// Data Union (bytes or ArrayBuffer)
// ============================================================================

pub const Data = union(enum) {
    bytes: []const u8,
    arrayBuffer: *const ArrayBuffer,

    pub fn toID(self: *const Data) u32 {
        switch (self.*) {
            .bytes => |b| return ArrayBuffer.new(b).id,
            .arrayBuffer => |ab| return ab.id,
        }
    }

    pub fn freeIfOwned(self: *const Data, id: u32) void {
        switch (self.*) {
            .bytes => jsFree(id),
            else => {},
        }
    }
};

// ============================================================================
// Hash Union (string name or algorithm object)
// ============================================================================

pub const Hash = union(enum) {
    name: []const u8,
    algorithm: DigestAlgorithm,

    pub fn toID(self: *const Hash) u32 {
        switch (self.*) {
            .name => |str| return String.new(str).id,
            .algorithm => |algo| return String.new(algo.toString()).id,
        }
    }
};

// ============================================================================
// Algorithm Structs
// ============================================================================

pub const CryptoKeyKeyAlgorithm = struct {
    name: []const u8,

    pub fn toObject(self: *const CryptoKeyKeyAlgorithm) Object {
        const obj = Object.new();
        obj.setText("name", self.name);
        return obj;
    }
};

pub const SubtleCryptoEncryptAlgorithm = struct {
    name: []const u8,
    iv: ?[]const u8 = null,
    additionalData: ?[]const u8 = null,
    tagLength: ?u32 = null,
    counter: ?[]const u8 = null,
    length: ?u32 = null,
    label: ?[]const u8 = null,

    pub fn toObject(self: *const SubtleCryptoEncryptAlgorithm) Object {
        const obj = Object.new();
        obj.setText("name", self.name);
        if (self.iv) |iv| {
            const ab = ArrayBuffer.new(iv);
            obj.setID("iv", ab.id);
        }
        if (self.additionalData) |ad| {
            const ab = ArrayBuffer.new(ad);
            obj.setID("additionalData", ab.id);
        }
        if (self.tagLength) |tl| obj.setNum("tagLength", u32, tl);
        if (self.counter) |c| {
            const ab = ArrayBuffer.new(c);
            obj.setID("counter", ab.id);
        }
        if (self.length) |l| obj.setNum("length", u32, l);
        if (self.label) |lbl| {
            const ab = ArrayBuffer.new(lbl);
            obj.setID("label", ab.id);
        }
        return obj;
    }
};

pub const SubtleCryptoGenerateKeyAlgorithm = struct {
    name: []const u8,
    hash: ?[]const u8 = null,
    modulusLength: ?u32 = null,
    publicExponent: ?[]const u8 = null,
    length: ?u32 = null,
    namedCurve: ?[]const u8 = null,

    pub fn toObject(self: *const SubtleCryptoGenerateKeyAlgorithm) Object {
        const obj = Object.new();
        obj.setText("name", self.name);
        if (self.hash) |h| obj.setText("hash", h);
        if (self.modulusLength) |ml| obj.setNum("modulusLength", u32, ml);
        if (self.publicExponent) |pe| {
            const ab = ArrayBuffer.new(pe);
            const uint8 = jsCreateClass(@intFromEnum(Classes.Uint8Array), ab.id);
            obj.setID("publicExponent", uint8);
        }
        if (self.length) |l| obj.setNum("length", u32, l);
        if (self.namedCurve) |nc| obj.setText("namedCurve", nc);
        return obj;
    }
};

pub const SubtleCryptoImportKeyAlgorithm = struct {
    name: []const u8,
    hash: ?[]const u8 = null,
    length: ?u32 = null,
    namedCurve: ?[]const u8 = null,

    pub fn toObject(self: *const SubtleCryptoImportKeyAlgorithm) Object {
        const obj = Object.new();
        obj.setText("name", self.name);
        if (self.hash) |h| obj.setText("hash", h);
        if (self.length) |l| obj.setNum("length", u32, l);
        if (self.namedCurve) |nc| obj.setText("namedCurve", nc);
        return obj;
    }
};

pub const SubtleCryptoSignAlgorithm = struct {
    name: []const u8,
    hash: ?[]const u8 = null,
    saltLength: ?u32 = null,

    pub fn toObject(self: *const SubtleCryptoSignAlgorithm) Object {
        const obj = Object.new();
        obj.setText("name", self.name);
        if (self.hash) |h| obj.setText("hash", h);
        if (self.saltLength) |sl| obj.setNum("saltLength", u32, sl);
        return obj;
    }
};

pub const SubtleCryptoDeriveKeyAlgorithm = struct {
    name: []const u8,
    salt: ?[]const u8 = null,
    iterations: ?u32 = null,
    hash: ?[]const u8 = null,
    public: ?*const CryptoKey = null,
    info: ?[]const u8 = null,

    pub fn toObject(self: *const SubtleCryptoDeriveKeyAlgorithm) Object {
        const obj = Object.new();
        obj.setText("name", self.name);
        if (self.salt) |s| {
            const ab = ArrayBuffer.new(s);
            obj.setID("salt", ab.id);
        }
        if (self.iterations) |i| obj.setNum("iterations", u32, i);
        if (self.hash) |h| obj.setText("hash", h);
        if (self.public) |p| obj.setID("public", p.id);
        if (self.info) |i| {
            const ab = ArrayBuffer.new(i);
            obj.setID("info", ab.id);
        }
        return obj;
    }
};

// ============================================================================
// CryptoKey
// ============================================================================

pub const CryptoKey = struct {
    id: u32,

    pub fn init(jsPtr: u32) CryptoKey {
        return CryptoKey{ .id = jsPtr };
    }

    pub fn free(self: *const CryptoKey) void {
        jsFree(self.id);
    }

    /// Get the key type: "public", "private", or "secret".
    pub fn getType(self: *const CryptoKey) []const u8 {
        return getStringFree(getObjectValue(self.id, "type"));
    }

    /// Whether the key can be exported.
    pub fn extractable(self: *const CryptoKey) bool {
        const val = getObjectValue(self.id, "extractable");
        return val == common.True;
    }

    /// Get the algorithm name.
    pub fn algorithmName(self: *const CryptoKey) []const u8 {
        const algo = getObjectValue(self.id, "algorithm");
        if (algo > common.DefaultValueSize) {
            const name = getObjectValue(algo, "name");
            if (name > common.DefaultValueSize) {
                return getStringFree(name);
            }
        }
        return "";
    }
};

// ============================================================================
// CryptoKeyPair
// ============================================================================

pub const CryptoKeyPair = struct {
    publicKey: CryptoKey,
    privateKey: CryptoKey,

    pub fn init(jsPtr: u32) CryptoKeyPair {
        return CryptoKeyPair{
            .publicKey = CryptoKey.init(getObjectValue(jsPtr, "publicKey")),
            .privateKey = CryptoKey.init(getObjectValue(jsPtr, "privateKey")),
        };
    }

    pub fn free(self: *const CryptoKeyPair) void {
        self.publicKey.free();
        self.privateKey.free();
    }
};

// ============================================================================
// DigestStream (Cloudflare-specific streaming hash)
// Note: DigestStream requires a custom JS binding to instantiate.
// For now, use SubtleCrypto.digest() for hashing needs.
// ============================================================================

pub const DigestStream = struct {
    id: u32,

    /// Create a new DigestStream - requires JS runtime support.
    /// Most workers should use SubtleCrypto.digest() instead.
    pub fn init(jsPtr: u32) DigestStream {
        return DigestStream{ .id = jsPtr };
    }

    pub fn free(self: *const DigestStream) void {
        if (self.id > common.DefaultValueSize) {
            jsFree(self.id);
        }
    }

    /// Check if the DigestStream is valid.
    pub fn isValid(self: *const DigestStream) bool {
        return self.id > common.DefaultValueSize;
    }

    /// Get the underlying WritableStream for piping.
    pub fn asWritableStream(self: *const DigestStream) u32 {
        return self.id;
    }

    /// Get the digest result (call after the stream is closed).
    /// Returns the hash as bytes.
    pub fn getDigest(self: *const DigestStream) ?[]const u8 {
        if (self.id <= common.DefaultValueSize) return null;

        const digestPromise = getObjectValue(self.id, "digest");
        if (digestPromise <= common.DefaultValueSize) return null;

        // Await the promise
        const result = jsAsyncFnCall(digestPromise, 0);
        if (result <= common.DefaultValueSize) return null;

        // Convert ArrayBuffer to bytes
        const ab = ArrayBuffer.init(result);
        defer ab.free();
        return ab.bytes();
    }
};

// ============================================================================
// SubtleCrypto
// ============================================================================

/// The SubtleCrypto interface provides cryptographic functions.
/// Access via `SubtleCrypto.get()` which returns the global crypto.subtle object.
pub const SubtleCrypto = struct {
    id: u32,

    /// Get the global crypto.subtle object.
    pub fn get() SubtleCrypto {
        return SubtleCrypto{ .id = jsGetSubtleCrypto() };
    }

    pub fn free(self: *const SubtleCrypto) void {
        jsFree(self.id);
    }

    // ========================================================================
    // digest - Hash data
    // ========================================================================

    /// Compute a digest (hash) of the given data.
    /// Returns the hash as bytes, or null on error.
    pub fn digest(self: *const SubtleCrypto, algorithm: DigestAlgorithm, data: []const u8) ?[]const u8 {
        const algoStr = String.new(algorithm.toString());
        defer algoStr.free();

        const dataAb = ArrayBuffer.new(data);
        defer dataAb.free();

        const args = Array.new();
        defer args.free();
        args.push(&algoStr);
        args.pushID(dataAb.id);

        const digestFn = getObjectValue(self.id, "digest");
        if (digestFn <= common.DefaultValueSize) return null;

        const resultPromise = jsAsyncFnCall(digestFn, args.id);
        if (resultPromise <= common.DefaultValueSize) return null;

        const resultAb = ArrayBuffer.init(resultPromise);
        defer resultAb.free();
        return resultAb.bytes();
    }

    // ========================================================================
    // generateKey - Generate a new key or key pair
    // ========================================================================

    /// Generate a symmetric key.
    pub fn generateKey(
        self: *const SubtleCrypto,
        algorithm: *const SubtleCryptoGenerateKeyAlgorithm,
        extractable_param: bool,
        keyUsages: []const KeyUsage,
    ) ?CryptoKey {
        const algoObj = algorithm.toObject();
        defer algoObj.free();

        const usagesArr = Array.new();
        defer usagesArr.free();
        for (keyUsages) |usage| {
            const usageStr = String.new(usage.toString());
            usagesArr.push(&usageStr);
        }

        const args = Array.new();
        defer args.free();
        args.pushID(algoObj.id);
        args.pushID(toJSBool(extractable_param));
        args.pushID(usagesArr.id);

        const generateKeyFn = getObjectValue(self.id, "generateKey");
        if (generateKeyFn <= common.DefaultValueSize) return null;

        const resultPromise = jsAsyncFnCall(generateKeyFn, args.id);
        if (resultPromise <= common.DefaultValueSize) return null;

        return CryptoKey.init(resultPromise);
    }

    /// Generate an asymmetric key pair.
    pub fn generateKeyPair(
        self: *const SubtleCrypto,
        algorithm: *const SubtleCryptoGenerateKeyAlgorithm,
        extractable_param: bool,
        keyUsages: []const KeyUsage,
    ) ?CryptoKeyPair {
        const algoObj = algorithm.toObject();
        defer algoObj.free();

        const usagesArr = Array.new();
        defer usagesArr.free();
        for (keyUsages) |usage| {
            const usageStr = String.new(usage.toString());
            usagesArr.push(&usageStr);
        }

        const args = Array.new();
        defer args.free();
        args.pushID(algoObj.id);
        args.pushID(toJSBool(extractable_param));
        args.pushID(usagesArr.id);

        const generateKeyFn = getObjectValue(self.id, "generateKey");
        if (generateKeyFn <= common.DefaultValueSize) return null;

        const resultPromise = jsAsyncFnCall(generateKeyFn, args.id);
        if (resultPromise <= common.DefaultValueSize) return null;

        return CryptoKeyPair.init(resultPromise);
    }

    // ========================================================================
    // importKey - Import a key from external format
    // ========================================================================

    /// Import a key from raw bytes or other format.
    pub fn importKey(
        self: *const SubtleCrypto,
        format: KeyFormat,
        keyData: []const u8,
        algorithm: *const SubtleCryptoImportKeyAlgorithm,
        extractable_param: bool,
        keyUsages: []const KeyUsage,
    ) ?CryptoKey {
        const formatStr = String.new(format.toString());
        defer formatStr.free();

        const keyDataAb = ArrayBuffer.new(keyData);
        defer keyDataAb.free();

        const algoObj = algorithm.toObject();
        defer algoObj.free();

        const usagesArr = Array.new();
        defer usagesArr.free();
        for (keyUsages) |usage| {
            const usageStr = String.new(usage.toString());
            usagesArr.push(&usageStr);
        }

        const args = Array.new();
        defer args.free();
        args.push(&formatStr);
        args.pushID(keyDataAb.id);
        args.pushID(algoObj.id);
        args.pushID(toJSBool(extractable_param));
        args.pushID(usagesArr.id);

        const importKeyFn = getObjectValue(self.id, "importKey");
        if (importKeyFn <= common.DefaultValueSize) return null;

        const resultPromise = jsAsyncFnCall(importKeyFn, args.id);
        if (resultPromise <= common.DefaultValueSize) return null;

        return CryptoKey.init(resultPromise);
    }

    // ========================================================================
    // exportKey - Export a key to external format
    // ========================================================================

    /// Export a key to the specified format.
    /// Returns the key data as bytes, or null on error.
    pub fn exportKey(self: *const SubtleCrypto, format: KeyFormat, key: *const CryptoKey) ?[]const u8 {
        const formatStr = String.new(format.toString());
        defer formatStr.free();

        const args = Array.new();
        defer args.free();
        args.push(&formatStr);
        args.pushID(key.id);

        const exportKeyFn = getObjectValue(self.id, "exportKey");
        if (exportKeyFn <= common.DefaultValueSize) return null;

        const resultPromise = jsAsyncFnCall(exportKeyFn, args.id);
        if (resultPromise <= common.DefaultValueSize) return null;

        const resultAb = ArrayBuffer.init(resultPromise);
        defer resultAb.free();
        return resultAb.bytes();
    }

    // ========================================================================
    // encrypt - Encrypt data
    // ========================================================================

    /// Encrypt data using the specified algorithm and key.
    /// Returns the ciphertext as bytes, or null on error.
    pub fn encrypt(
        self: *const SubtleCrypto,
        algorithm: *const SubtleCryptoEncryptAlgorithm,
        key: *const CryptoKey,
        data: []const u8,
    ) ?[]const u8 {
        const algoObj = algorithm.toObject();
        defer algoObj.free();

        const dataAb = ArrayBuffer.new(data);
        defer dataAb.free();

        const args = Array.new();
        defer args.free();
        args.pushID(algoObj.id);
        args.pushID(key.id);
        args.pushID(dataAb.id);

        const encryptFn = getObjectValue(self.id, "encrypt");
        if (encryptFn <= common.DefaultValueSize) return null;

        const resultPromise = jsAsyncFnCall(encryptFn, args.id);
        if (resultPromise <= common.DefaultValueSize) return null;

        const resultAb = ArrayBuffer.init(resultPromise);
        defer resultAb.free();
        return resultAb.bytes();
    }

    // ========================================================================
    // decrypt - Decrypt data
    // ========================================================================

    /// Decrypt data using the specified algorithm and key.
    /// Returns the plaintext as bytes, or null on error.
    pub fn decrypt(
        self: *const SubtleCrypto,
        algorithm: *const SubtleCryptoEncryptAlgorithm,
        key: *const CryptoKey,
        data: []const u8,
    ) ?[]const u8 {
        const algoObj = algorithm.toObject();
        defer algoObj.free();

        const dataAb = ArrayBuffer.new(data);
        defer dataAb.free();

        const args = Array.new();
        defer args.free();
        args.pushID(algoObj.id);
        args.pushID(key.id);
        args.pushID(dataAb.id);

        const decryptFn = getObjectValue(self.id, "decrypt");
        if (decryptFn <= common.DefaultValueSize) return null;

        const resultPromise = jsAsyncFnCall(decryptFn, args.id);
        if (resultPromise <= common.DefaultValueSize) return null;

        const resultAb = ArrayBuffer.init(resultPromise);
        defer resultAb.free();
        return resultAb.bytes();
    }

    // ========================================================================
    // sign - Sign data
    // ========================================================================

    /// Sign data using the specified algorithm and key.
    /// Returns the signature as bytes, or null on error.
    pub fn sign(
        self: *const SubtleCrypto,
        algorithm: *const SubtleCryptoSignAlgorithm,
        key: *const CryptoKey,
        data: []const u8,
    ) ?[]const u8 {
        const algoObj = algorithm.toObject();
        defer algoObj.free();

        const dataAb = ArrayBuffer.new(data);
        defer dataAb.free();

        const args = Array.new();
        defer args.free();
        args.pushID(algoObj.id);
        args.pushID(key.id);
        args.pushID(dataAb.id);

        const signFn = getObjectValue(self.id, "sign");
        if (signFn <= common.DefaultValueSize) return null;

        const resultPromise = jsAsyncFnCall(signFn, args.id);
        if (resultPromise <= common.DefaultValueSize) return null;

        const resultAb = ArrayBuffer.init(resultPromise);
        defer resultAb.free();
        return resultAb.bytes();
    }

    // ========================================================================
    // verify - Verify signature
    // ========================================================================

    /// Verify a signature against data.
    /// Returns true if the signature is valid, false otherwise.
    pub fn verify(
        self: *const SubtleCrypto,
        algorithm: *const SubtleCryptoSignAlgorithm,
        key: *const CryptoKey,
        signature: []const u8,
        data: []const u8,
    ) bool {
        const algoObj = algorithm.toObject();
        defer algoObj.free();

        const sigAb = ArrayBuffer.new(signature);
        defer sigAb.free();

        const dataAb = ArrayBuffer.new(data);
        defer dataAb.free();

        const args = Array.new();
        defer args.free();
        args.pushID(algoObj.id);
        args.pushID(key.id);
        args.pushID(sigAb.id);
        args.pushID(dataAb.id);

        const verifyFn = getObjectValue(self.id, "verify");
        if (verifyFn <= common.DefaultValueSize) return false;

        const resultPromise = jsAsyncFnCall(verifyFn, args.id);
        return resultPromise == common.True;
    }

    // ========================================================================
    // deriveKey - Derive a new key from a base key
    // ========================================================================

    /// Derive a new key from a base key.
    pub fn deriveKey(
        self: *const SubtleCrypto,
        algorithm: *const SubtleCryptoDeriveKeyAlgorithm,
        baseKey: *const CryptoKey,
        derivedKeyAlgorithm: *const SubtleCryptoImportKeyAlgorithm,
        extractable_param: bool,
        keyUsages: []const KeyUsage,
    ) ?CryptoKey {
        const algoObj = algorithm.toObject();
        defer algoObj.free();

        const derivedAlgoObj = derivedKeyAlgorithm.toObject();
        defer derivedAlgoObj.free();

        const usagesArr = Array.new();
        defer usagesArr.free();
        for (keyUsages) |usage| {
            const usageStr = String.new(usage.toString());
            usagesArr.push(&usageStr);
        }

        const args = Array.new();
        defer args.free();
        args.pushID(algoObj.id);
        args.pushID(baseKey.id);
        args.pushID(derivedAlgoObj.id);
        args.pushID(toJSBool(extractable_param));
        args.pushID(usagesArr.id);

        const deriveKeyFn = getObjectValue(self.id, "deriveKey");
        if (deriveKeyFn <= common.DefaultValueSize) return null;

        const resultPromise = jsAsyncFnCall(deriveKeyFn, args.id);
        if (resultPromise <= common.DefaultValueSize) return null;

        return CryptoKey.init(resultPromise);
    }

    // ========================================================================
    // deriveBits - Derive bits from a base key
    // ========================================================================

    /// Derive raw bits from a base key.
    /// Returns the derived bits as bytes, or null on error.
    pub fn deriveBits(
        self: *const SubtleCrypto,
        algorithm: *const SubtleCryptoDeriveKeyAlgorithm,
        baseKey: *const CryptoKey,
        length: u32,
    ) ?[]const u8 {
        const algoObj = algorithm.toObject();
        defer algoObj.free();

        const args = Array.new();
        defer args.free();
        args.pushID(algoObj.id);
        args.pushID(baseKey.id);
        args.pushNum(u32, length);

        const deriveBitsFn = getObjectValue(self.id, "deriveBits");
        if (deriveBitsFn <= common.DefaultValueSize) return null;

        const resultPromise = jsAsyncFnCall(deriveBitsFn, args.id);
        if (resultPromise <= common.DefaultValueSize) return null;

        const resultAb = ArrayBuffer.init(resultPromise);
        defer resultAb.free();
        return resultAb.bytes();
    }

    // ========================================================================
    // wrapKey - Wrap a key for secure storage/transmission
    // ========================================================================

    /// Wrap a key for secure storage or transmission.
    /// Returns the wrapped key as bytes, or null on error.
    pub fn wrapKey(
        self: *const SubtleCrypto,
        format: KeyFormat,
        key: *const CryptoKey,
        wrappingKey: *const CryptoKey,
        wrapAlgorithm: *const SubtleCryptoEncryptAlgorithm,
    ) ?[]const u8 {
        const formatStr = String.new(format.toString());
        defer formatStr.free();

        const algoObj = wrapAlgorithm.toObject();
        defer algoObj.free();

        const args = Array.new();
        defer args.free();
        args.push(&formatStr);
        args.pushID(key.id);
        args.pushID(wrappingKey.id);
        args.pushID(algoObj.id);

        const wrapKeyFn = getObjectValue(self.id, "wrapKey");
        if (wrapKeyFn <= common.DefaultValueSize) return null;

        const resultPromise = jsAsyncFnCall(wrapKeyFn, args.id);
        if (resultPromise <= common.DefaultValueSize) return null;

        const resultAb = ArrayBuffer.init(resultPromise);
        defer resultAb.free();
        return resultAb.bytes();
    }

    // ========================================================================
    // unwrapKey - Unwrap a wrapped key
    // ========================================================================

    /// Unwrap a previously wrapped key.
    pub fn unwrapKey(
        self: *const SubtleCrypto,
        format: KeyFormat,
        wrappedKey: []const u8,
        unwrappingKey: *const CryptoKey,
        unwrapAlgorithm: *const SubtleCryptoEncryptAlgorithm,
        unwrappedKeyAlgorithm: *const SubtleCryptoImportKeyAlgorithm,
        extractable_param: bool,
        keyUsages: []const KeyUsage,
    ) ?CryptoKey {
        const formatStr = String.new(format.toString());
        defer formatStr.free();

        const wrappedKeyAb = ArrayBuffer.new(wrappedKey);
        defer wrappedKeyAb.free();

        const unwrapAlgoObj = unwrapAlgorithm.toObject();
        defer unwrapAlgoObj.free();

        const unwrappedAlgoObj = unwrappedKeyAlgorithm.toObject();
        defer unwrappedAlgoObj.free();

        const usagesArr = Array.new();
        defer usagesArr.free();
        for (keyUsages) |usage| {
            const usageStr = String.new(usage.toString());
            usagesArr.push(&usageStr);
        }

        const args = Array.new();
        defer args.free();
        args.push(&formatStr);
        args.pushID(wrappedKeyAb.id);
        args.pushID(unwrappingKey.id);
        args.pushID(unwrapAlgoObj.id);
        args.pushID(unwrappedAlgoObj.id);
        args.pushID(toJSBool(extractable_param));
        args.pushID(usagesArr.id);

        const unwrapKeyFn = getObjectValue(self.id, "unwrapKey");
        if (unwrapKeyFn <= common.DefaultValueSize) return null;

        const resultPromise = jsAsyncFnCall(unwrapKeyFn, args.id);
        if (resultPromise <= common.DefaultValueSize) return null;

        return CryptoKey.init(resultPromise);
    }

    // ========================================================================
    // timingSafeEqual - Compare two buffers in constant time
    // ========================================================================

    /// Compare two buffers in constant time (timing-safe).
    /// This is a Cloudflare extension to the Web Crypto API.
    pub fn timingSafeEqual(self: *const SubtleCrypto, a: []const u8, b: []const u8) bool {
        const aAb = ArrayBuffer.new(a);
        defer aAb.free();

        const bAb = ArrayBuffer.new(b);
        defer bAb.free();

        const args = Array.new();
        defer args.free();
        args.pushID(aAb.id);
        args.pushID(bAb.id);

        const timingSafeEqualFn = getObjectValue(self.id, "timingSafeEqual");
        if (timingSafeEqualFn <= common.DefaultValueSize) return false;

        const result = jsFnCall(timingSafeEqualFn, args.id);
        return result == common.True;
    }
};

// ============================================================================
// Convenience functions
// ============================================================================

/// Convenience function to compute a SHA-256 hash.
pub fn sha256(data: []const u8) ?[]const u8 {
    const subtle = SubtleCrypto.get();
    defer subtle.free();
    return subtle.digest(.@"SHA-256", data);
}

/// Convenience function to compute a SHA-1 hash.
pub fn sha1(data: []const u8) ?[]const u8 {
    const subtle = SubtleCrypto.get();
    defer subtle.free();
    return subtle.digest(.@"SHA-1", data);
}

/// Convenience function to compute a SHA-512 hash.
pub fn sha512(data: []const u8) ?[]const u8 {
    const subtle = SubtleCrypto.get();
    defer subtle.free();
    return subtle.digest(.@"SHA-512", data);
}

/// Convenience function to compute an MD5 hash (not for security!).
pub fn md5(data: []const u8) ?[]const u8 {
    const subtle = SubtleCrypto.get();
    defer subtle.free();
    return subtle.digest(.MD5, data);
}
