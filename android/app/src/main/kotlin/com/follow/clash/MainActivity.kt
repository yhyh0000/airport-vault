package com.follow.clash

import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import com.follow.clash.common.GlobalState
import com.follow.clash.plugins.AppPlugin
import com.follow.clash.plugins.Phase4PerfPlugin
import com.follow.clash.plugins.ServicePlugin
import com.follow.clash.plugins.TilePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity(),
    CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Default) {

    private val webViewChannelName = "airport_vault/webview"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Phase4PerfGate.enabled(this)) {
            handlePhase4Intent(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (Phase4PerfGate.enabled(this)) {
            handlePhase4Intent(intent)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureAirportWebViewChannel(flutterEngine)
        flutterEngine.plugins.add(AppPlugin())
        flutterEngine.plugins.add(ServicePlugin())
        flutterEngine.plugins.add(TilePlugin())
        if (Phase4PerfGate.enabled(this)) {
            flutterEngine.plugins.add(Phase4PerfPlugin())
        }
        State.flutterEngine = flutterEngine
    }

    private fun configureAirportWebViewChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            webViewChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableWebViewCookies" -> runOnUiThread {
                    result.success(runCatching {
                        CookieManager.getInstance().setAcceptCookie(true)
                        true
                    }.getOrDefault(false))
                }

                "configureChromeWebView" -> runOnUiThread {
                    result.success(configureWebViews(window.decorView))
                }

                "getCookies" -> {
                    val url = call.argument<String>("url")?.trim().orEmpty()
                    if (url.isEmpty()) {
                        result.success("")
                    } else {
                        runOnUiThread {
                            result.success(runCatching {
                                val manager = CookieManager.getInstance()
                                manager.setAcceptCookie(true)
                                runCatching { manager.flush() }
                                manager.getCookie(url).orEmpty()
                            }.getOrDefault(""))
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * iKun uses an HttpOnly session cookie.  document.cookie cannot see it,
     * so keep the Android WebView cookie jar enabled and expose CookieManager
     * reads to Dart.  The recursive pass also removes the Android WebView UA
     * marker which can make the airport reject an embedded browser.
     */
    private fun configureWebViews(view: View): Boolean {
        var found = false
        if (view is WebView) {
            found = true
            runCatching {
                val cookies = CookieManager.getInstance()
                cookies.setAcceptCookie(true)
                cookies.setAcceptThirdPartyCookies(view, true)
            }
            runCatching {
                val settings = view.settings
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.databaseEnabled = true
                settings.javaScriptCanOpenWindowsAutomatically = true
                settings.setSupportMultipleWindows(false)
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                    settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                }
                var userAgent = settings.userAgentString.orEmpty()
                userAgent = userAgent
                    .replace(Regex(";\\s*wv"), "")
                    .replace("Version/4.0 ", "")
                    .replace(Regex("\\s{2,}"), " ")
                    .trim()
                if (userAgent.isNotEmpty()) {
                    settings.userAgentString = userAgent
                }
            }
            runCatching { view.onResume() }
            runCatching { view.resumeTimers() }
        }
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                if (configureWebViews(view.getChildAt(index))) {
                    found = true
                }
            }
        }
        return found
    }

    override fun onDestroy() {
        GlobalState.launch {
            Service.setEventListener(null)
        }
        State.flutterEngine = null
        super.onDestroy()
    }

    private fun handlePhase4Intent(intent: Intent?) {
        val cmd = intent?.getStringExtra(EXTRA_CMD) ?: return
        val extras = HashMap<String, String>()
        extras["cmd"] = cmd
        intent.extras?.keySet()?.forEach { key ->
            intent.getStringExtra(key)?.let { extras[key] = it }
        }
        val plugin = State.flutterEngine?.plugin<Phase4PerfPlugin>()
        if (plugin == null) {
            Log.w(TAG, "drop cmd=$cmd engine=${State.flutterEngine != null}")
            return
        }
        plugin.dispatch(cmd, extras)
    }

    companion object {
        private const val TAG = "Phase4Perf"
        const val EXTRA_CMD = "phase4_cmd"
    }
}
