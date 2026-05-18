package com.example.stream_app

import android.webkit.WebView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

class MainActivity : FlutterActivity() {
    private val androidWebViewChannel = "stream_app/android_webview"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, androidWebViewChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "addDocumentStartScript" -> {
                        val identifier = call.argument<Number>("webViewIdentifier")?.toLong()
                        val script = call.argument<String>("script")

                        if (identifier == null || script.isNullOrBlank()) {
                            result.error(
                                "bad_args",
                                "webViewIdentifier and script are required",
                                null,
                            )
                            return@setMethodCallHandler
                        }

                        val webView: WebView? =
                            WebViewFlutterAndroidExternalApi.getWebView(flutterEngine, identifier)
                        if (webView == null) {
                            result.error("webview_not_found", "WebView not found", null)
                            return@setMethodCallHandler
                        }

                        if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        WebViewCompat.addDocumentStartJavaScript(webView, script, setOf("*"))
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
