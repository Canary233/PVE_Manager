package com.canary233.PVEManager

import android.content.Intent
import android.os.Build
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var activeToast: Toast? = null
    private var consoleResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pve_manager/remote_console"
        ).setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val url = call.argument<String>("url")
            val fallbackTitle = call.argument<String>("fallbackTitle") ?: "Console"
            val title = call.argument<String>("title") ?: fallbackTitle
            val cookieDomain = call.argument<String>("cookieDomain")
            val authCookie = call.argument<String>("authCookie")
            val ignoreCertificateErrors =
                call.argument<Boolean>("ignoreCertificateErrors") ?: false
            val invalidArgumentsMessage =
                call.argument<String>("invalidArgumentsMessage") ?: "Invalid console arguments."

            if (url.isNullOrBlank() || cookieDomain.isNullOrBlank() || authCookie.isNullOrBlank()) {
                result.error("INVALID_ARGUMENT", invalidArgumentsMessage, null)
                return@setMethodCallHandler
            }
            if (consoleResult != null) {
                result.error("CONSOLE_BUSY", "A console is already open.", null)
                return@setMethodCallHandler
            }

            val intent = Intent(this, RemoteConsoleActivity::class.java).apply {
                putExtra(RemoteConsoleActivity.EXTRA_TITLE, title)
                putExtra(RemoteConsoleActivity.EXTRA_URL, url)
                putExtra(RemoteConsoleActivity.EXTRA_COOKIE_DOMAIN, cookieDomain)
                putExtra(RemoteConsoleActivity.EXTRA_AUTH_COOKIE, authCookie)
                putExtra(
                    RemoteConsoleActivity.EXTRA_AUTH_COOKIE_NAME,
                    call.argument<String>("authCookieName") ?: "PVEAuthCookie"
                )
                putExtra(
                    RemoteConsoleActivity.EXTRA_TERMINAL_MODE,
                    call.argument<Boolean>("terminalMode") ?: false
                )
                putExtra(
                    RemoteConsoleActivity.EXTRA_LOAD_FAILED_TEMPLATE,
                    call.argument<String>("loadFailedTemplate")
                )
                putExtra(
                    RemoteConsoleActivity.EXTRA_UNKNOWN_ERROR_MESSAGE,
                    call.argument<String>("unknownErrorMessage")
                )
                putExtra(
                    RemoteConsoleActivity.EXTRA_CERTIFICATE_ERROR_MESSAGE,
                    call.argument<String>("certificateErrorMessage")
                )
                putExtra(RemoteConsoleActivity.EXTRA_ERROR_HINT, call.argument<String>("errorHint"))
                putExtra(
                    RemoteConsoleActivity.EXTRA_IGNORE_CERTIFICATE_ERRORS,
                    ignoreCertificateErrors
                )
            }
            consoleResult = result
            try {
                startActivityForResult(intent, CONSOLE_REQUEST_CODE)
            } catch (error: Exception) {
                consoleResult = null
                result.error("CONSOLE_OPEN_FAILED", error.message, null)
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pve_manager/toast"
        ).setMethodCallHandler { call, result ->
            if (call.method != "show") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val message = call.argument<String>("message")
            if (message.isNullOrBlank()) {
                result.error("INVALID_ARGUMENT", "Toast message is required.", null)
                return@setMethodCallHandler
            }

            activeToast?.cancel()
            activeToast = Toast.makeText(
                applicationContext,
                message,
                Toast.LENGTH_SHORT
            ).also(Toast::show)
            result.success(null)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pve_manager/dynamic_color"
        ).setMethodCallHandler { call, result ->
            if (call.method != "getCorePalette") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            result.success(readSystemCorePalette())
        }
    }

    private fun readSystemCorePalette(): IntArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return null
        }

        val palettes = listOf(
            "system_accent1",
            "system_accent2",
            "system_accent3",
            "system_neutral1",
            "system_neutral2"
        )
        val tones = listOf(1000, 900, 800, 700, 600, 500, 400, 300, 200, 100, 50, 10, 0)
        val colors = ArrayList<Int>(palettes.size * tones.size)
        for (palette in palettes) {
            for (tone in tones) {
                val resourceId = resources.getIdentifier(
                    "${palette}_$tone",
                    "color",
                    "android"
                )
                if (resourceId == 0) {
                    return null
                }
                colors.add(resources.getColor(resourceId, null))
            }
        }
        return colors.toIntArray()
    }

    override fun onDestroy() {
        consoleResult?.error("CONSOLE_CLOSED", "Console host activity closed.", null)
        consoleResult = null
        activeToast?.cancel()
        activeToast = null
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == CONSOLE_REQUEST_CODE) {
            consoleResult?.success(null)
            consoleResult = null
        }
    }

    companion object {
        private const val CONSOLE_REQUEST_CODE = 401
    }
}
