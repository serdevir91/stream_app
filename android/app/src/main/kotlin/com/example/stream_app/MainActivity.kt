package com.example.stream_app

import android.content.Intent
import java.io.File
import android.webkit.WebView
import androidx.core.content.FileProvider
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

class MainActivity : FlutterActivity() {
    private val androidWebViewChannel = "stream_app/android_webview"
    private val appUpdaterChannel = "stream_app/app_updater"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appUpdaterChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("bad_args", "path is required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            result.success(openApkInstaller(path))
                        } catch (e: Exception) {
                            result.error("install_failed", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

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

    private fun openApkInstaller(path: String): Boolean {
        val apkFile = File(path)
        if (!apkFile.exists()) {
            return false
        }

        val apkUri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            apkFile,
        )

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
        return true
    }
}
