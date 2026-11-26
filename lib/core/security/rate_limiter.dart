/// Sliding-window rate limiter to protect local and coordinator APIs.
class RateLimiter {
  final int maxRequests;
  final Duration window;
  final Map<String, List<DateTime>> _buckets = {};

  RateLimiter({
    this.maxRequests = 120,
    this.window = const Duration(minutes: 1),
  });

  /// Returns true if the request from [clientKey] is allowed.
  bool allowRequest(String clientKey) {
    final now = DateTime.now();
    final cutoff = now.subtract(window);
    final timestamps = _buckets.putIfAbsent(clientKey, () => <DateTime>[]);
    timestamps.removeWhere((t) => t.isBefore(cutoff));

    if (timestamps.length >= maxRequests) {
      return false;
    }

    timestamps.add(now);
    return true;
  }

  void reset() => _buckets.clear();
}
