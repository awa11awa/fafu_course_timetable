import 'package:webview_flutter/webview_flutter.dart';

import 'scoped_session.dart';

class WebSessionCookies {
  static Future<SchoolCookies> capture() async {
    final jar = SchoolCookies();
    // The authentication path matters: CASTGC is scoped to /authserver.
    for (final uri in [schoolTokenUri, schoolAuthCookieUri]) {
      try {
        final cookies = await WebViewCookieManager().getCookies(domain: uri);
        for (final cookie in cookies) {
          // Cookies read for the HTTP auth URL can be sent on that same auth
          // origin. Never merge them into the timetable's Cookie header.
          jar.addHeader('${cookie.name}=${cookie.value}', uri);
        }
      } catch (_) { /* Unsupported/unavailable WebView does not block cached data. */ }
    }
    return jar;
  }
}
