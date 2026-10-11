package com.canary233.PVEManager

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.res.Configuration
import android.net.Uri
import android.net.http.SslError
import android.os.Bundle
import android.os.Build
import android.os.Message
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowInsets
import android.view.inputmethod.InputMethodManager
import android.webkit.CookieManager
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

class RemoteConsoleActivity : Activity() {
    private val webViews = mutableListOf<WebView>()
    private lateinit var content: FrameLayout
    private lateinit var webView: WebView
    private lateinit var progressBar: ProgressBar
    private lateinit var toolbar: TextView
    private lateinit var errorText: TextView
    private lateinit var cookieDomain: String
    private var ignoreCertificateErrors = false
    private var terminalMode = false
    private var ctrlLatch = false
    private var altLatch = false
    private var ctrlButton: TextView? = null
    private var altButton: TextView? = null
    private lateinit var loadFailedTemplate: String
    private lateinit var unknownErrorMessage: String
    private lateinit var certificateErrorMessage: String
    private lateinit var errorHint: String

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)

        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Console"
        val url = intent.getStringExtra(EXTRA_URL) ?: ""
        val authCookie = intent.getStringExtra(EXTRA_AUTH_COOKIE) ?: ""
        val authCookieName = intent.getStringExtra(EXTRA_AUTH_COOKIE_NAME) ?: "PVEAuthCookie"
        cookieDomain = intent.getStringExtra(EXTRA_COOKIE_DOMAIN) ?: ""
        terminalMode = intent.getBooleanExtra(EXTRA_TERMINAL_MODE, false)
        loadFailedTemplate =
            intent.getStringExtra(EXTRA_LOAD_FAILED_TEMPLATE)
                ?: "Console failed to load: {description}"
        unknownErrorMessage =
            intent.getStringExtra(EXTRA_UNKNOWN_ERROR_MESSAGE) ?: "Unknown error"
        certificateErrorMessage =
            intent.getStringExtra(EXTRA_CERTIFICATE_ERROR_MESSAGE)
                ?: "Console certificate verification failed."
        errorHint =
            intent.getStringExtra(EXTRA_ERROR_HINT)
                ?: "Tap the title bar to return, or use the system back button."
        ignoreCertificateErrors =
            intent.getBooleanExtra(EXTRA_IGNORE_CERTIFICATE_ERRORS, false)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(if (terminalMode) TERMINAL_BACKGROUND else 0xff000000.toInt())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // Let the root apply system bar and keyboard insets once.
                window.setDecorFitsSystemWindows(false)
                setOnApplyWindowInsetsListener { view, insets ->
                    val safeInsets = insets.getInsets(
                        WindowInsets.Type.systemBars() or
                            WindowInsets.Type.displayCutout() or
                            WindowInsets.Type.ime()
                    )
                    view.setPadding(
                        safeInsets.left,
                        safeInsets.top,
                        safeInsets.right,
                        safeInsets.bottom
                    )
                    insets
                }
            } else {
                fitsSystemWindows = true
            }
        }
        toolbar = TextView(this).apply {
            text = title
            setTextColor(0xffffffff.toInt())
            textSize = 18f
            gravity = Gravity.CENTER_VERTICAL
            setPadding(36, 0, 36, 0)
            setBackgroundColor(0xff202124.toInt())
            setOnClickListener { finish() }
        }
        updateToolbarVisibility(resources.configuration)
        progressBar = ProgressBar(
            this,
            null,
            android.R.attr.progressBarStyleHorizontal
        ).apply {
            max = 100
            visibility = View.VISIBLE
        }
        content = FrameLayout(this)
        webView = createConsoleWebView()
        webViews.add(webView)
        errorText = TextView(this).apply {
            visibility = View.GONE
            gravity = Gravity.CENTER
            textSize = 15f
            setTextColor(0xffffffff.toInt())
            setPadding(48, 48, 48, 48)
            setBackgroundColor(0xff202124.toInt())
        }

        content.addView(
            webView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        content.addView(
            errorText,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        if (!terminalMode) {
            root.addView(
                toolbar,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    dp(56)
                )
            )
        }
        root.addView(
            progressBar,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                if (terminalMode) dp(2) else dp(3)
            )
        )
        root.addView(
            content,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        )
        if (terminalMode) {
            root.addView(
                createTerminalShortcutBar(),
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                )
            )
        }
        setContentView(root)

        CookieManager.getInstance().apply {
            setAcceptCookie(true)
            setAcceptThirdPartyCookies(webView, true)
            val secureAttribute = if (url.startsWith("https://", ignoreCase = true)) {
                "; Secure"
            } else {
                ""
            }
            val cookie = "$authCookieName=$authCookie; Path=/; HttpOnly; SameSite=Strict$secureAttribute"
            val originUrl = consoleOrigin(url)
            val domainUrl = consoleDomainUrl(url, cookieDomain)
            val loadConsole = {
                runOnUiThread {
                    if (!isFinishing && !isDestroyed) {
                        flush()
                        webView.loadUrl(url)
                    }
                }
            }
            if (domainUrl == originUrl) {
                setCookie(originUrl, cookie) {
                    loadConsole()
                }
            } else {
                setCookie(domainUrl, cookie) {
                    setCookie(originUrl, cookie) {
                        loadConsole()
                    }
                }
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createConsoleWebView(): WebView {
        return WebView(this).apply {
            setBackgroundColor(if (terminalMode) TERMINAL_BACKGROUND else 0xff000000.toInt())
            settings.apply {
                javaScriptEnabled = true
                javaScriptCanOpenWindowsAutomatically = true
                setSupportMultipleWindows(true)
                domStorageEnabled = true
                databaseEnabled = true
                loadsImagesAutomatically = true
                useWideViewPort = true
                loadWithOverviewMode = true
                builtInZoomControls = true
                displayZoomControls = false
                cacheMode = WebSettings.LOAD_DEFAULT
                mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
                textZoom = 100
            }
            isFocusable = true
            isFocusableInTouchMode = true
            requestFocus()
            webChromeClient = consoleChromeClient()
            webViewClient = consoleWebViewClient()
        }
    }

    private fun consoleChromeClient(): WebChromeClient {
        return object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                progressBar.progress = newProgress
                progressBar.visibility = if (newProgress in 1..99) {
                    View.VISIBLE
                } else {
                    View.GONE
                }
            }

            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message?
            ): Boolean {
                if (isFinishing || isDestroyed) {
                    return false
                }
                val message = resultMsg ?: return false
                val transport = message.obj as? WebView.WebViewTransport
                    ?: return false
                val popup = createConsoleWebView()
                CookieManager.getInstance().setAcceptThirdPartyCookies(popup, true)
                attachWebView(popup)
                transport.webView = popup
                message.sendToTarget()
                return true
            }

            override fun onCloseWindow(window: WebView?) {
                if (window != null) {
                    detachWebView(window)
                }
            }
        }
    }

    private fun consoleWebViewClient(): WebViewClient {
        return object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                errorText.visibility = View.GONE
                progressBar.visibility = View.VISIBLE
                if (terminalMode) {
                    view?.setBackgroundColor(TERMINAL_BACKGROUND)
                }
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                if (request?.isForMainFrame != true) {
                    return
                }
                val description = error?.description?.toString() ?: unknownErrorMessage
                showError(loadFailedTemplate.replace("{description}", description))
            }

            override fun onReceivedSslError(
                view: WebView?,
                handler: SslErrorHandler?,
                error: SslError?
            ) {
                if (ignoreCertificateErrors) {
                    handler?.proceed()
                    return
                }

                handler?.cancel()
                showError(certificateErrorMessage)
            }
        }
    }

    private fun createTerminalShortcutBar(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(TERMINAL_SHORTCUT_BACKGROUND)
            addView(
                createShortcutRow(
                    listOf(
                        ShortcutSpec("ESC") { sendKey(KeyEvent.KEYCODE_ESCAPE) },
                        ShortcutSpec("/") { sendKey(KeyEvent.KEYCODE_SLASH) },
                        ShortcutSpec("|") { sendKey(KeyEvent.KEYCODE_BACKSLASH, KeyEvent.META_SHIFT_ON) },
                        ShortcutSpec("-") { sendKey(KeyEvent.KEYCODE_MINUS) },
                        ShortcutSpec("HOME") { sendKey(KeyEvent.KEYCODE_MOVE_HOME) },
                        ShortcutSpec("↑") { sendKey(KeyEvent.KEYCODE_DPAD_UP) },
                        ShortcutSpec("END") { sendKey(KeyEvent.KEYCODE_MOVE_END) },
                        ShortcutSpec("PGUP") { sendKey(KeyEvent.KEYCODE_PAGE_UP) },
                        ShortcutSpec("FN") { focusKeyboard() },
                    )
                )
            )
            addView(
                createShortcutRow(
                    listOf(
                        ShortcutSpec("TAB") { sendKey(KeyEvent.KEYCODE_TAB) },
                        ShortcutSpec("CTRL", isToggle = true) { toggleCtrl(it) },
                        ShortcutSpec("ALT", isToggle = true) { toggleAlt(it) },
                        ShortcutSpec("←") { sendKey(KeyEvent.KEYCODE_DPAD_LEFT) },
                        ShortcutSpec("↓") { sendKey(KeyEvent.KEYCODE_DPAD_DOWN) },
                        ShortcutSpec("→") { sendKey(KeyEvent.KEYCODE_DPAD_RIGHT) },
                        ShortcutSpec("PGDN") { sendKey(KeyEvent.KEYCODE_PAGE_DOWN) },
                        ShortcutSpec("⌨") { focusKeyboard() },
                    )
                )
            )
        }
    }

    private fun createShortcutRow(items: List<ShortcutSpec>): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(4), dp(3), dp(4), dp(3))
            for (item in items) {
                val button = TextView(this@RemoteConsoleActivity).apply {
                        text = item.label
                        gravity = Gravity.CENTER
                        textSize = 16f
                        typeface = android.graphics.Typeface.DEFAULT_BOLD
                        setTextColor(0xfff3f0e2.toInt())
                        setBackgroundColor(TERMINAL_SHORTCUT_BACKGROUND)
                        setPadding(dp(4), 0, dp(4), 0)
                        setOnClickListener {
                            item.action(this)
                        }
                    }
                if (item.label == "CTRL") {
                    ctrlButton = button
                } else if (item.label == "ALT") {
                    altButton = button
                }
                addView(
                    button,
                    LinearLayout.LayoutParams(0, dp(42), 1f)
                )
            }
        }
    }

    private fun toggleCtrl(view: TextView) {
        ctrlLatch = !ctrlLatch
        updateModifierButtons()
    }

    private fun toggleAlt(view: TextView) {
        altLatch = !altLatch
        updateModifierButtons()
    }

    private fun sendKey(keyCode: Int, extraMetaState: Int = 0) {
        webView.requestFocus()
        val metaState = currentMetaState() or extraMetaState
        webView.dispatchKeyEvent(KeyEvent(0, 0, KeyEvent.ACTION_DOWN, keyCode, 0, metaState))
        webView.dispatchKeyEvent(KeyEvent(0, 0, KeyEvent.ACTION_UP, keyCode, 0, metaState))
        clearOneShotModifiers()
    }

    private fun currentMetaState(): Int {
        var metaState = 0
        if (ctrlLatch) {
            metaState = metaState or KeyEvent.META_CTRL_ON
        }
        if (altLatch) {
            metaState = metaState or KeyEvent.META_ALT_ON
        }
        return metaState
    }

    private fun clearOneShotModifiers() {
        ctrlLatch = false
        altLatch = false
        updateModifierButtons()
    }

    private fun updateModifierButtons() {
        ctrlButton?.setTextColor(if (ctrlLatch) 0xff64d2ff.toInt() else 0xfff3f0e2.toInt())
        altButton?.setTextColor(if (altLatch) 0xff64d2ff.toInt() else 0xfff3f0e2.toInt())
    }

    private fun focusKeyboard() {
        webView.requestFocus()
        val inputMethodManager =
            getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        inputMethodManager.showSoftInput(webView, InputMethodManager.SHOW_IMPLICIT)
    }

    private fun attachWebView(next: WebView) {
        webViews.lastOrNull()?.visibility = View.GONE
        webViews.add(next)
        webView = next
        val errorIndex = content.indexOfChild(errorText).takeIf { it >= 0 } ?: content.childCount
        content.addView(
            next,
            errorIndex,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        next.visibility = View.VISIBLE
        next.requestFocus()
    }

    private fun detachWebView(target: WebView) {
        if (!webViews.remove(target)) {
            return
        }
        content.removeView(target)
        releaseWebView(target)
        val previous = webViews.lastOrNull()
        if (previous != null) {
            webView = previous
            previous.visibility = View.VISIBLE
            previous.requestFocus()
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        updateToolbarVisibility(newConfig)
    }

    private fun updateToolbarVisibility(configuration: Configuration) {
        toolbar.visibility = if (
            terminalMode || configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        ) {
            View.GONE
        } else {
            View.VISIBLE
        }
    }

    override fun onBackPressed() {
        if (this::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
        } else if (webViews.size > 1) {
            detachWebView(webView)
        } else {
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        for (view in webViews.toList()) {
            content.removeView(view)
            releaseWebView(view)
        }
        webViews.clear()
        super.onDestroy()
    }

    private fun releaseWebView(view: WebView) {
        view.stopLoading()
        view.webChromeClient = null
        view.webViewClient = WebViewClient()
        view.destroy()
    }

    private fun showError(message: String) {
        errorText.text = "$message\n\n$errorHint"
        errorText.visibility = View.VISIBLE
        progressBar.visibility = View.GONE
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private fun consoleOrigin(url: String): String {
        val uri = Uri.parse(url)
        if (uri.scheme.isNullOrBlank() || uri.authority.isNullOrBlank()) {
            return url
        }
        val builder = Uri.Builder().scheme(uri.scheme).authority(uri.authority).path("/")
        return builder.build().toString()
    }

    private fun consoleDomainUrl(url: String, domain: String): String {
        if (domain.isBlank()) {
            return consoleOrigin(url)
        }
        val uri = Uri.parse(url)
        if (uri.scheme.isNullOrBlank()) {
            return consoleOrigin(url)
        }
        return Uri.Builder().scheme(uri.scheme).authority(domain).path("/").build().toString()
    }

    companion object {
        const val EXTRA_TITLE = "title"
        const val EXTRA_URL = "url"
        const val EXTRA_COOKIE_DOMAIN = "cookieDomain"
        const val EXTRA_AUTH_COOKIE = "authCookie"
        const val EXTRA_AUTH_COOKIE_NAME = "authCookieName"
        const val EXTRA_TERMINAL_MODE = "terminalMode"
        const val EXTRA_IGNORE_CERTIFICATE_ERRORS = "ignoreCertificateErrors"
        const val EXTRA_LOAD_FAILED_TEMPLATE = "loadFailedTemplate"
        const val EXTRA_UNKNOWN_ERROR_MESSAGE = "unknownErrorMessage"
        const val EXTRA_CERTIFICATE_ERROR_MESSAGE = "certificateErrorMessage"
        const val EXTRA_ERROR_HINT = "errorHint"
        private val TERMINAL_BACKGROUND = 0xff063f49.toInt()
        private val TERMINAL_SHORTCUT_BACKGROUND = 0xff174f59.toInt()
    }

    private data class ShortcutSpec(
        val label: String,
        val isToggle: Boolean = false,
        val action: (TextView) -> Unit,
    )
}
