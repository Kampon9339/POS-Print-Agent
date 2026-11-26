/// Validates HTTP `Host` and `Origin` headers to prevent DNS rebinding
/// and unauthorized cross-origin access.
class OriginValidator {
  OriginValidator._();

  static const Set<String> _loopbackHosts = {'127.0.0.1', 'localhost', '[::1]'};

  /// Verifies that the HTTP `Host` header points to a loopback address
  /// (protects against DNS rebinding attacks against 127.0.0.1).
  static bool isValidLoopbackHost(String? hostHeader) {
    if (hostHeader == null || hostHeader.trim().isEmpty) {
      return false;
    }
    final trimmed = hostHeader.trim().toLowerCase();
    // Strip port if present (handling IPv6 [::1]:port)
    String hostOnly = trimmed;
    if (trimmed.startsWith('[')) {
      final closeBracket = trimmed.indexOf(']');
      if (closeBracket != -1) {
        hostOnly = trimmed.substring(0, closeBracket + 1);
      }
    } else if (trimmed.contains(':')) {
      hostOnly = trimmed.split(':').first;
    }
    return _loopbackHosts.contains(hostOnly);
  }

  /// Validates the `Origin` header if present.
  /// Non-browser HTTP clients (e.g., native services or curl tests) may omit Origin,
  /// while browser requests must match the configured allowed origins or loopback.
  static bool isAllowedOrigin(
    String? originHeader,
    List<String> allowedOrigins,
  ) {
    if (originHeader == null || originHeader.trim().isEmpty) {
      return true;
    }
    final normalized = originHeader.trim().toLowerCase();
    if (allowedOrigins.contains('*')) {
      return true;
    }
    for (final allowed in allowedOrigins) {
      if (allowed.trim().toLowerCase() == normalized) {
        return true;
      }
    }
    // Also permit localhost / 127.0.0.1 origins on any port by default for local Web POS
    final uri = Uri.tryParse(normalized);
    if (uri != null && (uri.host == 'localhost' || uri.host == '127.0.0.1')) {
      return true;
    }
    return false;
  }
}
