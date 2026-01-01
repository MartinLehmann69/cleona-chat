import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// Linux-only bindings for storing a keyring secret through libsecret WITHOUT
/// ever putting it into a process argument list (architecture §23.10 "No
/// secret in a process argument").
///
/// Until S402-1 the Linux keyring stored via `bash -c 'echo -n BASE64 |
/// secret-tool store …'`: the secret stood in the `-c` argument of `bash` for
/// the whole call and was readable by every local user from
/// `/proc/PID/cmdline`. Dart cannot feed stdin to a synchronously started
/// process, so the fix is to spawn no child process at all and call the same
/// library that `secret-tool` wraps.
///
/// Called is `secret_password_storev_sync` (libsecret-1.so.0) with a NULL
/// schema and a `GHashTable` built from `g_hash_table_new` /
/// `g_hash_table_insert` (libglib-2.0.so.0). A NULL schema stores an item that
/// is matched by its attributes alone — the same shape `secret-tool store`
/// writes with its `org.freedesktop.Secret.Generic` schema under
/// `SECRET_SCHEMA_DONT_MATCH_NAME` (in both cases no `xdg:schema` attribute is
/// added) — so the existing `secret-tool lookup application cleona type <name>`
/// path still finds the item, and a store over the same attributes replaces it
/// instead of writing a second one.
///
/// The secret travels only in a `calloc`'d buffer that is zeroed before it is
/// released; it never appears in a process argument, an environment variable,
/// a log line or an exception text.
///
/// ── THE START QUESTION AND THE BOUND (S403, owner decision V18) ──────
///
/// V18: where the system HAS a keyring, the keyring is binding; where it has
/// none — or logs in automatically, leaving the keyring LOCKED — the file
/// variant is used and the app warns once at first start. Deciding that needs
/// two more libsecret calls, and BOTH halves of the decision have a
/// measured failure mode:
///
///   * On a LOCKED default collection the old availability probe PASSED
///     (`secret-tool lookup` answers quickly with exit 1 whether the
///     collection is locked or not), the store call
///     `secret_password_storev_sync` then waited WITHOUT LIMIT on the
///     unlock dialog (measured on the lab VMs with autologin, 02.10.2026).
///     The probe `defaultCollectionState` therefore asks the service for its
///     default collection and reads the `locked` property.
///   * Nothing in GLib's synchronous API carries a timeout of its own. Every
///     call here therefore runs with a `GCancellable` that a second thread
///     cancels after a short deadline — see [prepareCanceller]. A synchronous
///     FFI call blocks the whole Dart isolate, so neither a Dart `Timer` nor
///     a freshly spawned isolate can fire while the call is stuck: the
///     canceller isolate is spawned and confirmed BEFORE any guarded call
///     runs, and its `ReceivePort` messages are enqueued by `send`, which
///     does not need the blocked isolate to yield.

/// A `GError` from GLib, read only to surface the fixed library error text.
final class _GError extends Struct {
  @Uint32()
  external int domain;

  @Int32()
  external int code;

  external Pointer<Utf8> message;
}

/// `guint g_str_hash (gconstpointer)`.
typedef _GHashFunc = Uint32 Function(Pointer<Void>);

/// `gboolean g_str_equal (gconstpointer, gconstpointer)`.
typedef _GEqualFunc = Int32 Function(Pointer<Void>, Pointer<Void>);

/// `GHashTable* g_hash_table_new (GHashFunc, GEqualFunc)`.
typedef _GHashTableNewNative = Pointer<Opaque> Function(
    Pointer<NativeFunction<_GHashFunc>>, Pointer<NativeFunction<_GEqualFunc>>);
typedef _GHashTableNewDart = Pointer<Opaque> Function(
    Pointer<NativeFunction<_GHashFunc>>, Pointer<NativeFunction<_GEqualFunc>>);

/// `gboolean g_hash_table_insert (GHashTable*, gpointer, gpointer)`.
typedef _GHashTableInsertNative = Int32 Function(
    Pointer<Opaque>, Pointer<Void>, Pointer<Void>);
typedef _GHashTableInsertDart = int Function(
    Pointer<Opaque>, Pointer<Void>, Pointer<Void>);

/// `void g_hash_table_destroy (GHashTable*)`.
typedef _GHashTableDestroyNative = Void Function(Pointer<Opaque>);
typedef _GHashTableDestroyDart = void Function(Pointer<Opaque>);

/// `void g_error_free (GError*)`.
typedef _GErrorFreeNative = Void Function(Pointer<_GError>);
typedef _GErrorFreeDart = void Function(Pointer<_GError>);

/// `gboolean secret_password_storev_sync (const SecretSchema*, GHashTable*,
/// const gchar*, const gchar*, const gchar*, GCancellable*, GError**)`.
typedef _SecretPasswordStorevSyncNative = Int32 Function(
    Pointer<Void> schema,
    Pointer<Opaque> attributes,
    Pointer<Utf8> collection,
    Pointer<Utf8> label,
    Pointer<Utf8> password,
    Pointer<Void> cancellable,
    Pointer<Pointer<_GError>> error);
typedef _SecretPasswordStorevSyncDart = int Function(
    Pointer<Void> schema,
    Pointer<Opaque> attributes,
    Pointer<Utf8> collection,
    Pointer<Utf8> label,
    Pointer<Utf8> password,
    Pointer<Void> cancellable,
    Pointer<Pointer<_GError>> error);

/// `SecretService* secret_service_get_sync (SecretServiceFlags,
/// GCancellable*, GError**)`. Flags `SECRET_SERVICE_OPEN_SESSION | SECRET_
/// SERVICE_LOAD_COLLECTIONS` = 3: a session (cheap) and the collections
/// preloaded, so the alias lookup below cannot end up waiting on a lazy
/// D-Bus round trip the cancellable does not cover.
typedef _SecretServiceGetSyncNative = Pointer<Opaque> Function(
    Int32 flags, Pointer<Void> cancellable, Pointer<Pointer<_GError>> error);
typedef _SecretServiceGetSyncDart = Pointer<Opaque> Function(
    int flags, Pointer<Void> cancellable, Pointer<Pointer<_GError>> error);

/// `SecretCollection* secret_collection_for_alias_sync (SecretService*,
/// const gchar* alias, SecretCollectionFlags, GCancellable*, GError**)`.
typedef _SecretCollectionForAliasSyncNative = Pointer<Opaque> Function(
    Pointer<Opaque> service,
    Pointer<Utf8> alias,
    Int32 flags,
    Pointer<Void> cancellable,
    Pointer<Pointer<_GError>> error);
typedef _SecretCollectionForAliasSyncDart = Pointer<Opaque> Function(
    Pointer<Opaque> service,
    Pointer<Utf8> alias,
    int flags,
    Pointer<Void> cancellable,
    Pointer<Pointer<_GError>> error);

/// `gboolean secret_collection_get_locked (SecretCollection*)` — reads the
/// cached proxy property, no D-Bus round trip, but still part of the guarded
/// sequence for uniformity.
typedef _SecretCollectionGetLockedNative = Int32 Function(Pointer<Opaque>);
typedef _SecretCollectionGetLockedDart = int Function(Pointer<Opaque>);

/// `GCancellable* g_cancellable_new (void)` (libgio-2.0.so.0).
typedef _GCancellableNewNative = Pointer<Void> Function();
typedef _GCancellableNewDart = Pointer<Void> Function();

/// `gpointer g_object_ref (gpointer)` (libgobject-2.0.so.0). The return value
/// is the same pointer; Dart only needs the refcount to rise.
typedef _GObjectRefNative = Pointer<Void> Function(Pointer<Void>);
typedef _GObjectRefDart = Pointer<Void> Function(Pointer<Void>);

/// `void g_object_unref (gpointer)` (libgobject-2.0.so.0).
typedef _GObjectUnrefNative = Void Function(Pointer<Void>);
typedef _GObjectUnrefDart = void Function(Pointer<Void>);

/// `void g_cancellable_cancel (GCancellable*)` (libgio-2.0.so.0) — looked up
/// by the canceller isolate itself.
typedef _GCancellableCancelNative = Void Function(Pointer<Void>);
typedef _GCancellableCancelDart = void Function(Pointer<Void>);

/// libsecret's `SECRET_COLLECTION_DEFAULT` alias: the persistent default
/// collection, the one `secret-tool store` writes into when no collection is
/// given.
const String _defaultCollection = 'default';

/// How long one native call may run before the canceller cancels it.
///
/// The probe and the store are, on an answering service, single-digit
/// millisecond affairs; the deadline exists for the PATHOLOGICAL case (a
/// service that answers the lookup probe but never returns from the store,
/// as measured on the autologin VMs). Generous against the slow, short
/// against the stuck.
const int _probeTimeoutMs = 3000;
const int _storeTimeoutMs = 5000;

/// Outcome of [LibsecretFfi.store].
class LibsecretStoreResult {
  final bool ok;

  /// The fixed library error text, or `null`. It never contains the stored
  /// secret — GLib/libsecret error messages are constant strings.
  final String? error;

  const LibsecretStoreResult(this.ok, this.error);
}

/// The answer to the V18 start question: is there a Secret Service, and is
/// its default collection unlocked?
enum LibsecretCollectionState {
  /// No service answered (headless, uninstalled, unreachable — or every
  /// probe call hit its deadline: fail closed, never fail open).
  noService,

  /// A service answered, but the default collection is locked (typical for
  /// automatic login): storing would wait on an unlock dialog.
  locked,

  /// A service answered and the default collection is unlocked: the
  /// keyring is binding (V18).
  unlocked,
}

/// Direct FFI access to libsecret + glib for the synchronous keyring store.
class LibsecretFfi {
  static LibsecretFfi? _instance;

  static LibsecretFfi get instance => _instance ??= _create();

  /// Whether both libraries load and every symbol below resolves. The Linux
  /// keyring asks this first (`keyring_service.dart`, `_isAvailable`): if it
  /// is false, the backend counts as unavailable exactly as it does today when
  /// `secret-tool` is missing, and the profile falls back to file storage.
  static bool isAvailable() => instance._loadable;

  final bool _loadable;

  /// Whether the start question can even be asked: the probe and the
  /// canceller need their own symbols (libgio, libgobject). Missing symbols
  /// count as "no service" — fail closed, the file variant answers.
  final bool _probeLoadable;

  final _SecretPasswordStorevSyncDart? _storevSync;
  final _GHashTableNewDart? _gHashTableNew;
  final _GHashTableInsertDart? _gHashTableInsert;
  final _GHashTableDestroyDart? _gHashTableDestroy;
  final _GErrorFreeDart? _gErrorFree;
  final Pointer<NativeFunction<_GHashFunc>>? _gStrHash;
  final Pointer<NativeFunction<_GEqualFunc>>? _gStrEqual;
  final _SecretServiceGetSyncDart? _serviceGetSync;
  final _SecretCollectionForAliasSyncDart? _collectionForAliasSync;
  final _SecretCollectionGetLockedDart? _collectionGetLocked;
  final _GCancellableNewDart? _gCancellableNew;
  final _GObjectRefDart? _gObjectRef;
  final _GObjectUnrefDart? _gObjectUnref;

  LibsecretFfi._(
      this._loadable,
      this._probeLoadable,
      this._storevSync,
      this._gHashTableNew,
      this._gHashTableInsert,
      this._gHashTableDestroy,
      this._gErrorFree,
      this._gStrHash,
      this._gStrEqual,
      this._serviceGetSync,
      this._collectionForAliasSync,
      this._collectionGetLocked,
      this._gCancellableNew,
      this._gObjectRef,
      this._gObjectUnref);

  static LibsecretFfi _create() {
    final libsecret = _open('libsecret-1.so.0');
    final glib = _open('libglib-2.0.so.0');
    if (libsecret == null || glib == null) return _empty();
    try {
      final storevSync = libsecret.lookupFunction<
          _SecretPasswordStorevSyncNative,
          _SecretPasswordStorevSyncDart>('secret_password_storev_sync');
      final htNew = glib.lookupFunction<_GHashTableNewNative,
          _GHashTableNewDart>('g_hash_table_new');
      final htInsert = glib.lookupFunction<_GHashTableInsertNative,
          _GHashTableInsertDart>('g_hash_table_insert');
      final htDestroy = glib.lookupFunction<_GHashTableDestroyNative,
          _GHashTableDestroyDart>('g_hash_table_destroy');
      final errFree = glib
          .lookupFunction<_GErrorFreeNative, _GErrorFreeDart>('g_error_free');
      final strHash = glib.lookup<NativeFunction<_GHashFunc>>('g_str_hash');
      final strEqual = glib.lookup<NativeFunction<_GEqualFunc>>('g_str_equal');

      // The start question (V18) and its bound. libgio/libgobject ship with
      // glib everywhere that libsecret does; if they do not resolve anyway,
      // the probe answers "no service" (fail closed) and the store refuses
      // an unbounded call (see [store]).
      _SecretServiceGetSyncDart? serviceGetSync;
      _SecretCollectionForAliasSyncDart? collectionForAliasSync;
      _SecretCollectionGetLockedDart? collectionGetLocked;
      _GCancellableNewDart? cancellableNew;
      _GObjectRefDart? objectRef;
      _GObjectUnrefDart? objectUnref;
      var probeLoadable = false;
      try {
        serviceGetSync = libsecret.lookupFunction<_SecretServiceGetSyncNative,
            _SecretServiceGetSyncDart>('secret_service_get_sync');
        collectionForAliasSync = libsecret.lookupFunction<
            _SecretCollectionForAliasSyncNative,
            _SecretCollectionForAliasSyncDart>('secret_collection_for_alias_sync');
        collectionGetLocked = libsecret.lookupFunction<
            _SecretCollectionGetLockedNative,
            _SecretCollectionGetLockedDart>('secret_collection_get_locked');
        final gio = _open('libgio-2.0.so.0');
        final gobject = _open('libgobject-2.0.so.0');
        cancellableNew = gio?.lookupFunction<_GCancellableNewNative,
            _GCancellableNewDart>('g_cancellable_new');
        objectRef = gobject
            ?.lookupFunction<_GObjectRefNative, _GObjectRefDart>('g_object_ref');
        objectUnref = gobject?.lookupFunction<_GObjectUnrefNative,
            _GObjectUnrefDart>('g_object_unref');
        probeLoadable = gio != null &&
            gobject != null &&
            cancellableNew != null &&
            objectRef != null &&
            objectUnref != null;
      } catch (_) {
        probeLoadable = false;
      }

      return LibsecretFfi._(
          true,
          probeLoadable,
          storevSync,
          htNew,
          htInsert,
          htDestroy,
          errFree,
          strHash,
          strEqual,
          serviceGetSync,
          collectionForAliasSync,
          collectionGetLocked,
          cancellableNew,
          objectRef,
          objectUnref);
    } catch (_) {
      return _empty();
    }
  }

  static LibsecretFfi _empty() => LibsecretFfi._(
      false, false, null, null, null, null, null, null, null, null, null, null,
      null, null, null);

  static DynamicLibrary? _open(String name) {
    try {
      return DynamicLibrary.open(name);
    } catch (_) {
      return null;
    }
  }

  // ── The canceller (V18: no native call may hang) ─────────────────────

  /// The port the canceller isolate listens on, `null` until
  /// [prepareCanceller] confirmed it.
  SendPort? _cancellerPort;

  /// Keeps the reply channel of the handshake alive for the life of this
  /// process — a `ReceivePort` nobody holds is closed and GC'd.
  RawReceivePort? _cancellerReply;

  /// Spawns the canceller isolate and confirms it is listening. MUST be
  /// awaited before the first guarded native call — a synchronous FFI call
  /// blocks the calling isolate, and nothing spawned at that moment can be
  /// relied upon to start.
  ///
  /// The canceller receives `[Pointer.address, timeoutMs]` pairs, sleeps,
  /// cancels the `GCancellable` and drops the reference the sending side
  /// took for it. `SendPort.send` is a non-blocking enqueue into the
  /// receiver's queue, so a blocked sender loses nothing.
  Future<void> prepareCanceller() async {
    if (_cancellerPort != null || !_probeLoadable) return;
    final completer = Completer<void>();
    final reply = RawReceivePort();
    _cancellerReply = reply;
    reply.handler = (Object? message) {
      if (completer.isCompleted) return;
      if (message is SendPort) {
        _cancellerPort = message;
      }
      // Everything else is the onError answer of a canceller isolate that
      // died on startup — the port stays null, the callers fail closed.
      completer.complete();
    };
    try {
      await Isolate.spawn(
          _cancellerEntry, reply.sendPort, onError: reply.sendPort);
      await completer.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Fail closed: without a confirmed canceller no guarded call runs.
      // The store refuses with a fixed message, the probe reports "no
      // service" — the file variant answers (V18).
      if (!completer.isCompleted) completer.complete();
    } finally {
      if (_cancellerPort == null) {
        _cancellerReply?.close();
        _cancellerReply = null;
      }
    }
  }

  /// Entry point of the canceller isolate. Opens gio/gobject itself (an
  /// isolate does not inherit its parent's `DynamicLibrary` handles), then
  /// serves one `sleep -> cancel -> unref` per message for the rest of the
  /// process's life. A startup failure propagates to the spawner's `onError`
  /// port — fail closed, never a silent no-op canceller.
  static void _cancellerEntry(SendPort replyTo) {
    final gio = DynamicLibrary.open('libgio-2.0.so.0');
    final gobject = DynamicLibrary.open('libgobject-2.0.so.0');
    final cancel = gio.lookupFunction<_GCancellableCancelNative,
        _GCancellableCancelDart>('g_cancellable_cancel');
    final unref = gobject.lookupFunction<_GObjectUnrefNative,
        _GObjectUnrefDart>('g_object_unref');
    final port = RawReceivePort();
    port.handler = (Object? message) {
      if (message is List<Object?> && message.length == 2) {
        final address = message[0] as int;
        final timeoutMs = message[1] as int;
        sleep(Duration(milliseconds: timeoutMs));
        final p = Pointer<Void>.fromAddress(address);
        cancel(p);
        unref(p);
      }
    };
    replyTo.send(port.sendPort);
  }

  /// Hands [cancellable] to the canceller for cancellation after
  /// [timeoutMs]. Takes the reference the canceller will drop again —
  /// without it, the canceller could unref an object the guarded call has
  /// already released (use-after-free).
  void _armCanceller(Pointer<Void> cancellable, int timeoutMs) {
    _gObjectRef!(cancellable);
    _cancellerPort!.send(<Object?>[cancellable.address, timeoutMs]);
  }

  /// Reads a `GError*` out of [errOut] (freeing it) — `null` if none was set.
  String? _drainError(Pointer<Pointer<_GError>> errOut, _GErrorFreeDart errFree) {
    if (errOut.value == nullptr) return null;
    final msg = errOut.value.ref.message.toDartString();
    errFree(errOut.value);
    errOut.value = nullptr;
    return msg;
  }

  /// The V18 start question: is a Secret Service reachable, and is its
  /// default collection unlocked?
  ///
  /// Synchronous and bounded: every call runs under the canceller prepared
  /// by [prepareCanceller]. Without a confirmed canceller the answer is
  /// `noService` — an unbounded call is never risked for a nicer answer.
  LibsecretCollectionState defaultCollectionState() {
    final serviceGet = _serviceGetSync;
    final forAlias = _collectionForAliasSync;
    final getLocked = _collectionGetLocked;
    final cancellableNew = _gCancellableNew;
    final objectUnref = _gObjectUnref;
    final errFree = _gErrorFree;
    if (!_probeLoadable ||
        serviceGet == null ||
        forAlias == null ||
        getLocked == null ||
        cancellableNew == null ||
        objectUnref == null ||
        errFree == null ||
        _cancellerPort == null) {
      return LibsecretCollectionState.noService;
    }

    final cancellable = cancellableNew();
    final errOut = calloc<Pointer<_GError>>();
    errOut.value = nullptr;
    try {
      _armCanceller(cancellable, _probeTimeoutMs);
      final service = serviceGet(3 /* OPEN_SESSION | LOAD_COLLECTIONS */,
          cancellable, errOut);
      if (service == nullptr) {
        // Unreachable service, missing D-Bus session, or the deadline hit:
        // all three mean the same thing for the decision.
        _drainError(errOut, errFree);
        return LibsecretCollectionState.noService;
      }
      try {
        final alias = _cString(_defaultCollection);
        try {
          final collection = forAlias(service, alias.cast<Utf8>(), 0, cancellable, errOut);
          if (collection == nullptr) {
            _drainError(errOut, errFree);
            return LibsecretCollectionState.noService;
          }
          try {
            return getLocked(collection) != 0
                ? LibsecretCollectionState.locked
                : LibsecretCollectionState.unlocked;
          } finally {
            objectUnref(collection.cast<Void>());
          }
        } finally {
          calloc.free(alias);
        }
      } finally {
        objectUnref(service.cast<Void>());
      }
    } catch (_) {
      return LibsecretCollectionState.noService;
    } finally {
      _drainError(errOut, errFree);
      objectUnref(cancellable);
      calloc.free(errOut);
    }
  }

  /// A NUL-terminated C string allocated with `calloc`. The caller must release
  /// it with [calloc.free] once the native side no longer reads it.
  static Pointer<Uint8> _cString(String s) {
    final bytes = utf8.encode(s);
    final p = calloc<Uint8>(bytes.length + 1);
    for (var i = 0; i < bytes.length; i++) {
      p[i] = bytes[i];
    }
    p[bytes.length] = 0;
    return p;
  }

  /// Store [password] (base64) under [name] with the attributes and label that
  /// `secret-tool store --label='Cleona: [name]' application cleona type
  /// [name]` used to write: attributes `application=cleona`, `type=[name]`,
  /// label `Cleona: [name]`. The existing `secret-tool lookup application
  /// cleona type [name]` path keeps finding the item, and an existing item with
  /// the same attributes is replaced, not duplicated.
  ///
  /// Fails closed: when the libraries are not loaded (or the store itself
  /// fails) a failed result is returned and the secret is never logged.
  ///
  /// Since V18 the call runs under the canceller prepared by
  /// [prepareCanceller] and is refused without one — a store that can wait
  /// without limit is exactly the failure that was measured on the autologin
  /// lab VMs, and "maybe nobody notices" is not a bound.
  LibsecretStoreResult store(String name, String password) {
    final storev = _storevSync;
    final htNew = _gHashTableNew;
    final htInsert = _gHashTableInsert;
    final htDestroy = _gHashTableDestroy;
    final errFree = _gErrorFree;
    final strHash = _gStrHash;
    final strEqual = _gStrEqual;
    final cancellableNew = _gCancellableNew;
    final objectRef = _gObjectRef;
    final objectUnref = _gObjectUnref;
    if (!_loadable ||
        storev == null ||
        htNew == null ||
        htInsert == null ||
        htDestroy == null ||
        errFree == null ||
        strHash == null ||
        strEqual == null) {
      return const LibsecretStoreResult(false, 'libsecret or glib not loaded');
    }
    if (cancellableNew == null ||
        objectRef == null ||
        objectUnref == null) {
      return const LibsecretStoreResult(
          false, 'libgio or libgobject not loaded');
    }
    if (_cancellerPort == null) {
      return const LibsecretStoreResult(
          false,
          'canceller not prepared — refusing an unbounded native call '
          '(V18: nothing may hang)');
    }

    final appKey = _cString('application');
    final appValue = _cString('cleona');
    final typeKey = _cString('type');
    final typeValue = _cString(name);
    final label = _cString('Cleona: $name');
    final collection = _cString(_defaultCollection);

    // The secret itself: a separate, zeroed-then-freed native buffer — never a
    // Dart string handed to a child process, and never in an argument list.
    final pwdBytes = utf8.encode(password);
    final pwd = calloc<Uint8>(pwdBytes.length + 1);
    for (var i = 0; i < pwdBytes.length; i++) {
      pwd[i] = pwdBytes[i];
    }
    pwd[pwdBytes.length] = 0;

    // The hash table keeps the raw key/value pointers (g_hash_table_new, not
    // _full), so the strings above must outlive the store call and are released
    // after the table is destroyed.
    final table = htNew(strHash, strEqual);
    htInsert(table, appKey.cast<Void>(), appValue.cast<Void>());
    htInsert(table, typeKey.cast<Void>(), typeValue.cast<Void>());

    final errOut = calloc<Pointer<_GError>>();
    errOut.value = nullptr;
    final cancellable = cancellableNew();

    var ok = false;
    String? error;
    try {
      _armCanceller(cancellable, _storeTimeoutMs);
      final rc = storev(
        nullptr, // schema: NULL — match by attributes only (§23.10)
        table,
        collection.cast<Utf8>(),
        label.cast<Utf8>(),
        pwd.cast<Utf8>(),
        cancellable,
        errOut,
      );
      ok = rc != 0;
      if (!ok && errOut.value != nullptr) {
        error = errOut.value.ref.message.toDartString();
      }
    } finally {
      htDestroy(table);
      _drainError(errOut, errFree);
      objectUnref(cancellable);
      // Zero the secret buffer before releasing it. The other buffers carry no
      // secret (attribute names/values, label, collection) and are released
      // as-is.
      for (var i = 0; i <= pwdBytes.length; i++) {
        pwd[i] = 0;
      }
      calloc.free(pwd);
      calloc.free(errOut);
      calloc.free(appKey);
      calloc.free(appValue);
      calloc.free(typeKey);
      calloc.free(typeValue);
      calloc.free(label);
      calloc.free(collection);
    }
    return LibsecretStoreResult(ok, error);
  }
}