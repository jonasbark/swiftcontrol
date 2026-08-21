/// Seam over Apple Bonjour's `dnssd.dll` (Windows only).
///
/// Spec §12: MyWhoosh on Windows resolves our hostname via Apple Bonjour's
/// Winsock provider (mdnsNSP/mdnsResponder). Only a registration *owned by
/// that same daemon* answers the lookup locally — one held by our own
/// in-process responder, or by the OS's native `nsd` responder, does not. The
/// only way to get a registration owned by Bonjour's daemon is to ask it
/// directly via `DNSServiceRegister` in dnssd.dll — hence this FFI seam.
///
/// The FFI call itself cannot be exercised on non-Windows machines, so every
/// piece of logic that *can* be pure lives in top-level functions
/// ([encodeTxtRecord], [toNetworkByteOrder]) that are unit-tested directly;
/// [RealBonjourApi] is a thin wrapper around them plus the two native calls.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:bike_control/main.dart';
import 'package:ffi/ffi.dart';
import 'package:prop/utils/shared.dart';

/// Encodes a DNS-SD TXT record: wire format is a sequence of
/// length-prefixed `key=value` segments — one length byte (the byte length
/// of `key=value`) followed by the ASCII key, `=`, and the raw value bytes
/// verbatim (no escaping). An empty map encodes to an empty record.
///
/// Throws [ArgumentError] if any single `key=value` segment would exceed 255
/// bytes — DNS-SD's length byte cannot represent more.
Uint8List encodeTxtRecord(Map<String, Uint8List> txt) {
  final builder = BytesBuilder(copy: false);
  for (final entry in txt.entries) {
    final keyBytes = ascii.encode(entry.key);
    final segmentLength = keyBytes.length + 1 + entry.value.length; // +1 for '='
    if (segmentLength > 255) {
      throw ArgumentError(
        'TXT segment for "${entry.key}" is $segmentLength bytes; DNS-SD allows at most 255',
      );
    }
    builder.addByte(segmentLength);
    builder.add(keyBytes);
    builder.addByte(0x3d); // '='
    builder.add(entry.value);
  }
  return builder.toBytes();
}

/// Swaps the two bytes of a 16-bit value — host <-> network byte order for a
/// port number. Its own inverse, so the same function converts both ways:
/// `toNetworkByteOrder(hostPort)` before the FFI call, and (if ever needed)
/// `toNetworkByteOrder(networkPort)` to convert back.
int toNetworkByteOrder(int port) => ((port & 0xff) << 8) | ((port >> 8) & 0xff);

/// Thin seam over dnssd.dll so [BonjourServiceAdvertiser] is testable off
/// Windows: tests use a fake, [RealBonjourApi] is the dart:ffi
/// implementation used at runtime.
abstract class BonjourApi {
  bool get isAvailable;

  /// Registers `name`.`type` on `port` with `txtRecord` (already
  /// wire-encoded via [encodeTxtRecord]). Returns an opaque handle to pass to
  /// [deallocate]. Throws [BonjourException] (message includes the
  /// kDNSServiceErr code) on a non-zero `DNSServiceRegister` return.
  Object register({required String name, required String type, required int port, required Uint8List txtRecord});

  /// Unregisters a handle previously returned by [register].
  void deallocate(Object handle);
}

class BonjourException implements Exception {
  final String message;

  BonjourException(this.message);

  @override
  String toString() => 'BonjourException: $message';
}

// The subset of dnssd.h used here. See
// https://opensource.apple.com/source/mDNSResponder/mDNSResponder-1310.140.1/dnssd_clientlib/dnssd_ipc.c
// and dns_sd.h for the full C signatures this mirrors.
typedef _DnsServiceRegisterNative =
    Int32 Function(
      Pointer<Pointer<Void>> sdRef,
      Uint32 flags,
      Uint32 interfaceIndex,
      Pointer<Utf8> name,
      Pointer<Utf8> regtype,
      Pointer<Utf8> domain,
      Pointer<Utf8> host,
      Uint16 portInNetworkByteOrder,
      Uint16 txtLen,
      Pointer<Uint8> txtRecord,
      Pointer<Void> callBack,
      Pointer<Void> context,
    );
typedef _DnsServiceRegisterDart =
    int Function(
      Pointer<Pointer<Void>> sdRef,
      int flags,
      int interfaceIndex,
      Pointer<Utf8> name,
      Pointer<Utf8> regtype,
      Pointer<Utf8> domain,
      Pointer<Utf8> host,
      int portInNetworkByteOrder,
      int txtLen,
      Pointer<Uint8> txtRecord,
      Pointer<Void> callBack,
      Pointer<Void> context,
    );

typedef _DnsServiceRefDeallocateNative = Void Function(Pointer<Void> sdRef);
typedef _DnsServiceRefDeallocateDart = void Function(Pointer<Void> sdRef);

/// dart:ffi implementation, backed by Apple Bonjour's `dnssd.dll` (installed
/// with iTunes, Apple's Bonjour Print Services, or our own installer — not
/// present on every Windows machine).
class RealBonjourApi implements BonjourApi {
  DynamicLibrary? _library;
  bool _openAttempted = false;

  /// Opens dnssd.dll once and memoises the result (including failure) for
  /// the lifetime of this instance.
  DynamicLibrary? _open() {
    if (_openAttempted) return _library;
    _openAttempted = true;
    try {
      _library = DynamicLibrary.open('dnssd.dll');
    } on ArgumentError catch (e) {
      // DynamicLibrary.open throws ArgumentError when the library cannot be
      // located. dnssd.dll not being installed is the normal state on most
      // Windows machines (it ships with iTunes / Bonjour Print Services /
      // our own installer, not Windows itself) — an expected condition, not
      // a bug in this app. This is the documented exception to "every catch
      // forwards to recordError": that would flag every non-Bonjour machine
      // as an error. Logged via Logger.info instead.
      Logger.info('RealBonjourApi: dnssd.dll not available: $e');
      _library = null;
    } catch (e, s) {
      // Anything else (e.g. the library loads but is corrupt) is not the
      // expected "not installed" case — record it.
      recordError(e, s, context: 'RealBonjourApi.open');
      _library = null;
    }
    return _library;
  }

  @override
  bool get isAvailable => _open() != null;

  @override
  Object register({required String name, required String type, required int port, required Uint8List txtRecord}) {
    final library = _open();
    if (library == null) {
      throw BonjourException('dnssd.dll is not available');
    }

    final registerFn = library.lookupFunction<_DnsServiceRegisterNative, _DnsServiceRegisterDart>(
      'DNSServiceRegister',
    );

    final sdRefPtr = calloc<Pointer<Void>>();
    final namePtr = name.toNativeUtf8();
    final regtypePtr = type.toNativeUtf8();
    final txtPtr = calloc<Uint8>(txtRecord.isEmpty ? 1 : txtRecord.length);
    try {
      for (var i = 0; i < txtRecord.length; i++) {
        txtPtr[i] = txtRecord[i];
      }
      final result = registerFn(
        sdRefPtr,
        0, // flags
        0, // interfaceIndex: all interfaces
        namePtr,
        regtypePtr,
        nullptr, // domain: default
        nullptr, // host: default (this machine)
        toNetworkByteOrder(port),
        txtRecord.length,
        txtPtr,
        nullptr, // callBack: none, the immediate return code is authoritative
        nullptr, // context
      );
      if (result != 0) {
        throw BonjourException('DNSServiceRegister failed with kDNSServiceErr $result');
      }
      return sdRefPtr.value;
    } finally {
      calloc.free(sdRefPtr);
      calloc.free(namePtr);
      calloc.free(regtypePtr);
      calloc.free(txtPtr);
    }
  }

  @override
  void deallocate(Object handle) {
    final library = _open();
    if (library == null) return;
    final deallocateFn = library.lookupFunction<_DnsServiceRefDeallocateNative, _DnsServiceRefDeallocateDart>(
      'DNSServiceRefDeallocate',
    );
    deallocateFn(handle as Pointer<Void>);
  }
}
