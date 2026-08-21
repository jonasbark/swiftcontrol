import Foundation
import Network
import dnssd

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS
#endif

/// Bonjour type used solely to probe the Local Network permission.
///
/// It must also be listed in the host app's `NSBonjourServices`, otherwise the
/// browse is rejected for a reason that has nothing to do with the permission
/// and every probe reports `denied`.
private let preflightServiceType = "_bikecontrol-preflight._tcp"

/// Apple ships no authorization-status API for Local Network privacy — not on
/// iOS 14...26, not on macOS 15...26. The only reliable signal is to actually
/// perform a Bonjour round trip and watch how it fails:
///
///  * the browser discovering our own listener  -> granted
///  * `kDNSServiceErr_PolicyDenied` (-65570)    -> denied
///  * neither, before the timeout               -> unknown
///
/// `unknown` is a real outcome, not an error: a device with no network at all
/// never completes the round trip even though the permission is fine. Callers
/// must not treat it as a denial.
public class LocalNetworkPermissionPlugin: NSObject, FlutterPlugin {
  private static let channelName = "bike_control/local_network_permission"

  /// Keeps the plugin alive for the process's lifetime.
  ///
  /// `register(with:)` otherwise hands over the only reference and ARC is free
  /// to release it, taking the in-flight probe — and its NWListener/NWBrowser —
  /// down with it. The symptom is brutal: both reach `.ready`, then nothing
  /// ever arrives, not even the timeout, and the Dart caller waits forever.
  private static var retained: LocalNetworkPermissionPlugin?

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let plugin = LocalNetworkPermissionPlugin()
    retained = plugin
    registrar.addMethodCallDelegate(plugin, channel: channel)
  }

  /// Guards `probe`. Two concurrent probes would advertise two instances of
  /// the same service type and each browser could resolve the *other* one, so
  /// only one runs at a time and later callers join the one in flight.
  private let lock = NSLock()
  private var probe: Probe?
  private var pending: [FlutterResult] = []

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "check":
      let arguments = call.arguments as? [String: Any]
      let timeoutMs = arguments?["timeoutMs"] as? Int ?? 4000
      check(timeoutMs: timeoutMs, result: result)
    case "openSettings":
      openSettings()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func check(timeoutMs: Int, result: @escaping FlutterResult) {
    lock.lock()
    pending.append(result)
    if probe != nil {
      // A probe is already running; this caller rides along on its outcome.
      lock.unlock()
      return
    }

    guard let probe = Probe(timeoutMs: timeoutMs) else {
      let waiting = pending
      pending = []
      lock.unlock()
      // NWListener creation only fails on malformed parameters, which are
      // hard-coded here — surface it rather than reporting a fake denial.
      let error = FlutterError(
        code: "probe_unavailable",
        message: "Could not create the local network probe",
        details: nil
      )
      for callback in waiting {
        callback(error)
      }
      return
    }
    self.probe = probe
    lock.unlock()

    probe.start { [weak self] outcome in
      guard let self else { return }
      self.lock.lock()
      let waiting = self.pending
      self.pending = []
      self.probe = nil
      self.lock.unlock()
      for callback in waiting {
        callback(outcome)
      }
    }
  }

  private func openSettings() {
    #if os(iOS)
      // Lands on BikeControl's own settings page, which is where the Local
      // Network toggle lives; iOS has no deep link to the toggle itself.
      guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
      DispatchQueue.main.async {
        UIApplication.shared.open(url)
      }
    #elseif os(macOS)
      // macOS 26 has no `Privacy_LocalNetwork` anchor in the Settings anchor
      // table (unlike `Privacy_Bluetooth`), so an unknown anchor degrades to
      // the Privacy & Security pane — still the right place to land.
      guard
        let url = URL(
          string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")
      else { return }
      NSWorkspace.shared.open(url)
    #endif
  }
}

/// One `NWListener` + `NWBrowser` pair, reporting exactly once.
private final class Probe {
  private let queue = DispatchQueue(label: "app.bikecontrol.localNetworkProbe")
  private let listener: NWListener
  private let browser: NWBrowser
  private let timeoutMs: Int

  private var completion: ((String) -> Void)?
  private var timeout: DispatchWorkItem?

  /// Held from `start` until `finish`, so a probe always outlives whoever
  /// asked for it. Every callback below is the only thing that can answer the
  /// Dart side; being deallocated first means that side waits forever.
  private var selfRetain: Probe?

  init?(timeoutMs: Int) {
    guard
      let listener = try? NWListener(
        using: NWParameters(tls: .none, tcp: NWProtocolTCP.Options()))
    else {
      return nil
    }
    self.listener = listener
    self.browser = NWBrowser(for: .bonjour(type: preflightServiceType, domain: nil), using: .tcp)
    self.timeoutMs = timeoutMs
  }

  func start(completion: @escaping (String) -> Void) {
    queue.async {
      self.completion = completion
      self.selfRetain = self

      let timeout = DispatchWorkItem { [weak self] in
        // Nothing was discovered and nothing was denied. Most likely there is
        // no usable network at all — report neither, and let the caller keep
        // whatever it already assumed.
        self?.finish("unknown")
      }
      self.timeout = timeout
      self.queue.asyncAfter(deadline: .now() + .milliseconds(self.timeoutMs), execute: timeout)

      // A listener without a connection handler refuses to start.
      self.listener.newConnectionHandler = { $0.cancel() }
      self.listener.service = NWListener.Service(
        name: UUID().uuidString, type: preflightServiceType)
      self.listener.stateUpdateHandler = { [weak self] state in
        // Only a denial is conclusive here: when Local Network is off the
        // listener otherwise reports `.ready` and silently advertises nothing,
        // which is exactly why the browser has to be the primary signal.
        switch state {
        case .failed(let error), .waiting(let error):
          if isPolicyDenied(error) {
            self?.finish("denied")
          }
        default:
          break
        }
      }
      self.listener.start(queue: self.queue)

      self.browser.stateUpdateHandler = { [weak self] state in
        switch state {
        case .failed(let error), .waiting(let error):
          if isPolicyDenied(error) {
            self?.finish("denied")
          }
        // Other `.waiting` reasons (no router, no interface) are transient and
        // say nothing about the permission — let the timeout call those.
        default:
          break
        }
      }
      self.browser.browseResultsChangedHandler = { [weak self] results, _ in
        // Any result proves Bonjour traffic reaches this process. It is
        // usually our own listener, but another BikeControl on the LAN is
        // just as good a proof.
        if !results.isEmpty {
          self?.finish("granted")
        }
      }
      self.browser.start(queue: self.queue)
    }
  }

  /// Reports `outcome` once and tears everything down. Always on `queue`.
  private func finish(_ outcome: String) {
    guard let completion else { return }
    self.completion = nil
    timeout?.cancel()
    timeout = nil
    listener.stateUpdateHandler = nil
    listener.newConnectionHandler = nil
    browser.stateUpdateHandler = nil
    browser.browseResultsChangedHandler = nil
    listener.cancel()
    browser.cancel()
    completion(outcome)
    selfRetain = nil
  }
}

/// True for `kDNSServiceErr_PolicyDenied` (-65570), the error the Network
/// framework raises when Local Network privacy blocks the operation.
private func isPolicyDenied(_ error: NWError) -> Bool {
  if case .dns(let code) = error {
    return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
  }
  return false
}
