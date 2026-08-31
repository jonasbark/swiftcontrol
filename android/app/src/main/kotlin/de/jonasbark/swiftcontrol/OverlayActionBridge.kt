package de.jonasbark.swiftcontrol

import android.util.Log
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * Workaround for flutter_overlay_window 0.5.0's broken overlay→main bridge:
 * `FlutterOverlayWindow.shareData()` from the overlay isolate logs but the
 * message never arrives at main's Dart. This singleton owns a custom
 * MethodChannel between the two engines, plumbed through Java/Kotlin so we
 * control both ends.
 *
 * Wiring:
 * - MainActivity creates a MethodChannel on the main engine and points
 *   `mainChannel` at it via [bindMainChannel]. Main Dart sets a method-call
 *   handler on this channel to receive `"action"` calls.
 * - When the overlay is shown, main Dart calls `installOverlayHandler` (via
 *   MethodChannel from the main engine) which looks up the overlay engine via
 *   [FlutterEngineCache] and registers a handler on it. That handler forwards
 *   `"push"` calls received from overlay Dart back through `mainChannel` as
 *   `"action"` calls to main Dart.
 */
object OverlayActionBridge {
    const val CHANNEL = "bike_control/overlay_actions"
    private const val TAG = "OverlayActionBridge"
    private const val OVERLAY_ENGINE_KEY = "myCachedEngine" // matches OverlayConstants.CACHED_TAG

    private var mainChannel: MethodChannel? = null
    private var overlayChannel: MethodChannel? = null

    fun bindMainChannel(channel: MethodChannel) {
        mainChannel = channel
    }

    /**
     * Looks up the overlay engine from [FlutterEngineCache] and registers a
     * MethodChannel handler on it. Idempotent; safe to call multiple times.
     * Returns true on success, false if the overlay engine is not cached yet.
     */
    fun installOverlayHandler(): Boolean {
        if (overlayChannel != null) return true
        val engine = FlutterEngineCache.getInstance().get(OVERLAY_ENGINE_KEY)
        if (engine == null) {
            Log.w(TAG, "overlay engine not in cache yet")
            return false
        }
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "push" -> {
                    val action = call.arguments as? String
                    if (action != null) {
                        // Forward to main Dart as an "action" call.
                        mainChannel?.invokeMethod("action", action)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        overlayChannel = channel
        Log.i(TAG, "overlay-side handler installed")
        return true
    }

    /** Tear down the overlay-side handler when the overlay closes. */
    fun uninstallOverlayHandler() {
        overlayChannel?.setMethodCallHandler(null)
        overlayChannel = null
    }

    /**
     * Re-tops the overlay window in place, without tearing down the overlay
     * engine or restarting the service.
     *
     * The overlay is a `TYPE_APPLICATION_OVERLAY` window added by the package's
     * `OverlayService` while BikeControl was in the foreground. Once a trainer
     * app (e.g. Rouvy) comes to the foreground the overlay can end up buried
     * beneath it and stays hidden until the window is re-added — the rider sees
     * it over every other app "but only not with Rouvy" (support 73367365).
     *
     * We can't fix it with close+show from Dart: the package's `showOverlay`
     * uses `startService`, which Android blocks from the background, and the
     * trainer app being foreground is exactly the background case. So instead we
     * reach into the already-running service and re-add its view in place —
     * `removeViewImmediate` is synchronous, so the following `addView`
     * re-enters the top of the overlay z-order (and re-attaches the surface)
     * with no service start involved.
     *
     * flutter_overlay_window 0.5.0 exposes no API for this, so we reflect into
     * the service's private fields. A null service (overlay not running)
     * returns false and the caller treats it as a no-op; anything else — a
     * renamed field on a package bump, a detached view — is rethrown as a
     * [RuntimeException] so Flutter's method-channel wrapper turns it into a
     * Dart error the caller records, rather than a silent no-op (a raw checked
     * reflection exception would escape that wrapper and crash the platform
     * thread). Runs on the platform (main) thread, as WindowManager view ops
     * require; method-call handlers already dispatch there.
     */
    fun reassertOverlay(): Boolean {
        try {
            val window = overlayWindow() ?: return false
            window.manager.removeViewImmediate(window.view)
            window.manager.addView(window.view, window.params)
            return true
        } catch (t: Throwable) {
            Log.w(TAG, "reassertOverlay failed", t)
            throw RuntimeException("reassertOverlay failed: ${t.message}", t)
        }
    }

    /**
     * Keep the device screen on while the overlay is visible by adding
     * `FLAG_KEEP_SCREEN_ON` to the overlay window's own LayoutParams.
     *
     * `wakelock_plus` only sets that flag on BikeControl's *activity* window,
     * which is inert whenever the activity is backgrounded — the normal state
     * during a ride, where the tablet acts as a bridge and only this overlay is
     * on screen (over the launcher or the trainer app). Setting the flag on the
     * overlay window instead keeps the screen awake regardless of what the
     * activity is doing, and it is bounded by the overlay's lifetime: closing
     * the overlay removes the window and the flag with it.
     *
     * Same reflection caveat as [reassertOverlay]; the flag survives a
     * subsequent reassert because that re-adds the view with these same params.
     */
    fun setKeepScreenOn(enable: Boolean): Boolean {
        try {
            val window = overlayWindow() ?: return false
            val had = (window.params.flags and
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0
            if (enable == had) return true
            window.params.flags = if (enable) {
                window.params.flags or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            } else {
                window.params.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON.inv()
            }
            window.manager.updateViewLayout(window.view, window.params)
            return true
        } catch (t: Throwable) {
            Log.w(TAG, "setKeepScreenOn failed", t)
            throw RuntimeException("setKeepScreenOn failed: ${t.message}", t)
        }
    }

    private class OverlayWindow(
        val view: View,
        val manager: WindowManager,
        val params: WindowManager.LayoutParams,
    )

    /**
     * Reflects into the package's running [OverlayService] to reach its window.
     * Returns null when the overlay isn't running (service instance, view,
     * window manager or params absent); a renamed field on a package bump
     * throws, which callers turn into a recorded Dart error rather than a
     * silent no-op. flutter_overlay_window 0.5.0 exposes no API for either use.
     */
    private fun overlayWindow(): OverlayWindow? {
        val serviceClass = Class.forName(
            "flutter.overlay.window.flutter_overlay_window.OverlayService",
        )
        val service = serviceClass.getDeclaredField("instance")
            .apply { isAccessible = true }
            .get(null) ?: return null
        val flutterView = serviceClass.getDeclaredField("flutterView")
            .apply { isAccessible = true }
            .get(service) as? View ?: return null
        val windowManager = serviceClass.getDeclaredField("windowManager")
            .apply { isAccessible = true }
            .get(service) as? WindowManager ?: return null
        val params = flutterView.layoutParams as? WindowManager.LayoutParams ?: return null
        return OverlayWindow(flutterView, windowManager, params)
    }
}
