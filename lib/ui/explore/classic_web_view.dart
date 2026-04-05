/// Full-featured WebView browser for Classic Web mode in Explore.
///
/// Provides a complete browsing experience with JavaScript, cookies,
/// navigation tracking, and dark-mode injection. Cookie storage is
/// isolated per user profile/identity.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A full-featured WebView browser widget for Explore's Classic Web mode.
///
/// Embeddable in any parent layout — does **not** include its own navigation
/// chrome (back/forward/refresh buttons). Those controls live in the OmniBar;
/// use the public navigation methods exposed here to drive them.
///
/// Cookie storage is automatically cleared when the active user identity
/// changes, ensuring each profile has isolated browsing state.
///
/// ```dart
/// ClassicWebView(
///   initialUrl: 'https://example.com',
///   onUrlChanged: (url) => omniBarController.text = url,
///   onTitleChanged: (title) => setState(() => _tabLabel = title),
///   onProgress: (p) => setState(() => _progress = p),
/// )
/// ```
class ClassicWebView extends ConsumerStatefulWidget {
  /// Creates a [ClassicWebView].
  const ClassicWebView({
    super.key,
    this.initialUrl,
    this.onUrlChanged,
    this.onTitleChanged,
    this.onProgress,
  });

  /// Initial URL to load. If null, loads `about:blank`.
  final String? initialUrl;

  /// Called when the current URL changes (e.g. for omnibar display).
  final ValueChanged<String>? onUrlChanged;

  /// Called when the page title changes (e.g. for tab labels).
  final ValueChanged<String>? onTitleChanged;

  /// Called with loading progress (0–100).
  final ValueChanged<int>? onProgress;

  @override
  ConsumerState<ClassicWebView> createState() => ClassicWebViewState();
}

/// State for [ClassicWebView].
///
/// Public navigation methods ([goBack], [goForward], [reload], etc.) are
/// exposed so a parent can drive the browser via a [GlobalKey].
class ClassicWebViewState extends ConsumerState<ClassicWebView> {
  late final WebViewController _controller;
  final WebViewCookieManager _cookieManager = WebViewCookieManager();

  bool _isLoading = false;
  double _progress = 0;
  bool _hasError = false;
  String? _errorDescription;

  /// Tracks the identity id so we can detect switches.
  String? _lastIdentityId;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: _onPageStarted,
          onProgress: _onProgress,
          onPageFinished: _onPageFinished,
          onWebResourceError: _onWebResourceError,
        ),
      );

    final url = widget.initialUrl;
    if (url != null && url.isNotEmpty) {
      _controller.loadRequest(Uri.parse(url));
    } else {
      _controller.loadRequest(Uri.parse('about:blank'));
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation delegate callbacks
  // ---------------------------------------------------------------------------

  void _onPageStarted(String url) {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorDescription = null;
      _progress = 0;
    });
    widget.onUrlChanged?.call(url);
  }

  void _onProgress(int progress) {
    if (!mounted) return;
    setState(() => _progress = progress / 100.0);
    widget.onProgress?.call(progress);
  }

  void _onPageFinished(String url) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _progress = 1;
    });

    // Extract and notify page title.
    _controller.getTitle().then((title) {
      if (mounted && title != null && title.isNotEmpty) {
        widget.onTitleChanged?.call(title);
      }
    }).ignore();

    // Inject dark-mode hints so sites that respect prefers-color-scheme
    // render appropriately inside the dark Kabuk shell.
    _injectDarkMode();
  }

  void _onWebResourceError(WebResourceError error) {
    if (!mounted) return;
    // Only show the error page for main-frame navigation failures.
    // Sub-resource errors (ads, analytics, third-party scripts) are common
    // and should not replace the entire page with an error screen.
    if (error.isForMainFrame != true) return;
    setState(() {
      _isLoading = false;
      _hasError = true;
      _errorDescription = error.description;
    });
  }

  // ---------------------------------------------------------------------------
  // Dark mode injection
  // ---------------------------------------------------------------------------

  /// Injects dark-mode CSS/meta into the current page.
  ///
  /// Mirrors the approach used by `QuickPeekSheet` so the browsing
  /// experience stays consistent with the Kabuk dark shell.
  void _injectDarkMode() {
    _controller.runJavaScript('''
(function() {
  try {
    var meta = document.querySelector('meta[name="color-scheme"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = 'color-scheme';
      document.head && document.head.appendChild(meta);
    }
    meta.content = 'dark';
    var style = document.createElement('style');
    style.id = '__kabuk_dark';
    if (!document.getElementById('__kabuk_dark')) {
      style.textContent = ':root { color-scheme: dark; }';
      document.head && document.head.appendChild(style);
    }
  } catch (e) {}
})();
''').ignore();
  }

  // ---------------------------------------------------------------------------
  // Per-profile cookie isolation
  // ---------------------------------------------------------------------------

  /// Clears all WebView cookies and reloads the current page.
  ///
  /// Called automatically when the active identity changes so that each
  /// profile gets an isolated browsing session.
  Future<void> _clearCookiesAndReload() async {
    await _cookieManager.clearCookies();
    await _controller.reload();
  }

  // ---------------------------------------------------------------------------
  // Public navigation API
  // ---------------------------------------------------------------------------

  /// Navigates back in the WebView history.
  Future<void> goBack() => _controller.goBack();

  /// Navigates forward in the WebView history.
  Future<void> goForward() => _controller.goForward();

  /// Reloads the current page.
  Future<void> reload() => _controller.reload();

  /// Whether the WebView can navigate back.
  Future<bool> canGoBack() => _controller.canGoBack();

  /// Whether the WebView can navigate forward.
  Future<bool> canGoForward() => _controller.canGoForward();

  /// Returns the current URL, or `null` if unavailable.
  Future<String?> currentUrl() => _controller.currentUrl();

  /// Returns the current page title, or `null` if unavailable.
  Future<String?> currentTitle() => _controller.getTitle();

  /// Loads [url] in the WebView, replacing the current page.
  Future<void> loadUrl(String url) =>
      _controller.loadRequest(Uri.parse(url));

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Watch the current identity and clear cookies on switch.
    final identityAsync = ref.watch(currentIdentityProvider);
    final currentId = identityAsync.valueOrNull?.id;
    if (_lastIdentityId != null && currentId != _lastIdentityId) {
      // Identity changed — isolate browsing state.
      unawaited(_clearCookiesAndReload());
    }
    _lastIdentityId = currentId;

    return Column(
      children: [
        // Chrome-style linear progress indicator.
        if (_isLoading)
          LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            minHeight: 2,
            backgroundColor: Colors.transparent,
            valueColor: const AlwaysStoppedAnimation<Color>(
              KabukTheme.accentGreen,
            ),
          ),

        // Main content: WebView or error state.
        Expanded(
          child: _hasError ? _buildError(context) : WebViewWidget(
            controller: _controller,
          ),
        ),
      ],
    );
  }

  /// Builds the error state with a message and retry button.
  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 48,
              color: context.kabukTextTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load page',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.kabukTextPrimary,
              ),
            ),
            if (_errorDescription != null && _errorDescription!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _errorDescription!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: context.kabukTextSecondary,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _isLoading = true;
                });
                _controller.reload();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
