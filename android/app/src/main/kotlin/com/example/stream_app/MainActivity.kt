package com.example.stream_app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Parcelable
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
    private val externalPlayerChannel = "stream_app/external_player"
    private val externalPlayerRequest = 4711
    private var pendingPlayerResult: MethodChannel.Result? = null

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

                    "supportedAbis" -> result.success(android.os.Build.SUPPORTED_ABIS.toList())

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, externalPlayerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listPlayers" -> result.success(listVideoPlayers())
                    "launch" -> launchExternalPlayer(call.arguments as? Map<*, *>, result)
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

    @Suppress("DEPRECATION")
    private fun listVideoPlayers(): List<Map<String, String>> {
        val probe = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse("http://127.0.0.1/video.mp4"), "video/*")
        }
        val seen = mutableSetOf<String>()
        val players = mutableListOf<Map<String, String>>()
        for (info in packageManager.queryIntentActivities(probe, 0)) {
            val pkg = info.activityInfo?.packageName ?: continue
            if (pkg == packageName || !seen.add(pkg)) continue
            players.add(
                mapOf(
                    "package" to pkg,
                    "label" to info.loadLabel(packageManager).toString(),
                ),
            )
        }
        return players
    }

    /**
     * Opens a stream in another app. Extras cover VLC (subtitles_location,
     * long position) and the MX Player API that Just Player and mpv-android
     * also read (subs, subs.enable, int position, return_result).
     */
    private fun launchExternalPlayer(args: Map<*, *>?, result: MethodChannel.Result) {
        val url = args?.get("url") as? String
        if (url.isNullOrBlank()) {
            result.error("bad_args", "url is required", null)
            return
        }
        val pkg = (args["package"] as? String)?.takeIf { it.isNotBlank() }
        val title = args["title"] as? String
        val positionMs = (args["positionMs"] as? Number)?.toLong() ?: 0L
        val subtitles = (args["subtitles"] as? List<*>)?.mapNotNull { it as? Map<*, *> } ?: emptyList()
        val headers = (args["headers"] as? Map<*, *>) ?: emptyMap<Any, Any>()
        val isVlc = pkg?.startsWith("org.videolan.vlc") == true

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(url), "video/*")
            if (pkg != null) setPackage(pkg)
            if (title != null) {
                putExtra("title", title)
                putExtra("forcename", title)
            }
            if (isVlc) {
                putExtra("position", positionMs)
                putExtra("from_start", positionMs <= 0L)
            } else {
                putExtra("position", positionMs.toInt())
            }
            putExtra("return_result", true)
            putExtra("secure_uri", true)
            if (subtitles.isNotEmpty()) {
                val uris = subtitles.mapNotNull { (it["url"] as? String)?.let(Uri::parse) }
                val names = subtitles.map { (it["name"] as? String) ?: "Subtitle" }
                putExtra("subtitles_location", uris.first().toString())
                putExtra("subs", uris.toTypedArray<Parcelable>())
                putExtra("subs.name", names.toTypedArray())
                putExtra("subs.enable", arrayOf<Parcelable>(uris.first()))
            }
            if (headers.isNotEmpty()) {
                val flat = headers.flatMap { (k, v) -> listOf(k.toString(), v.toString()) }
                putExtra("headers", flat.toTypedArray())
            }
        }

        try {
            pendingPlayerResult?.success(null)
            pendingPlayerResult = result
            if (pkg == null) {
                startActivityForResult(Intent.createChooser(intent, title ?: "Open with"), externalPlayerRequest)
            } else {
                startActivityForResult(intent, externalPlayerRequest)
            }
        } catch (e: ActivityNotFoundException) {
            pendingPlayerResult = null
            result.error("not_found", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != externalPlayerRequest) return
        val pending = pendingPlayerResult ?: return
        pendingPlayerResult = null
        val extras = data?.extras
        fun number(vararg keys: String): Long? {
            for (key in keys) {
                @Suppress("DEPRECATION")
                val value = extras?.get(key)
                if (value is Number) return value.toLong()
            }
            return null
        }
        pending.success(
            mapOf(
                "ok" to (resultCode == Activity.RESULT_OK),
                "positionMs" to number("extra_position", "position"),
                "durationMs" to number("extra_duration", "duration"),
                "endBy" to extras?.getString("end_by"),
            ),
        )
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
