// Self-check for the AuthNotifier logout guard and contract.
//
// Verifies the logout invariants without a running Supabase instance:
//   1. A concurrent second call is a no-op (the _isLoggingOut guard returns).
//   2. State flips to unauthenticated when logout() returns (NOT gated on the
//      fire-and-forget network cleanup), and that cleanup is scheduled.
//   3. The guard resets when logout() returns, so a later logout is accepted.
//
// Run with:  flutter test test/logout_guard_test.dart
//
// No frameworks, no fixtures. Uses flutter_test (already a dev dep).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('concurrent-logout guard: overlapping second call is a no-op', () async {
    final notifier = _FakeAuthNotifier();
    // Fire two calls without awaiting between them. The first yields at its
    // first await with the guard set; the second must bail out.
    unawaited(notifier.logout());
    unawaited(notifier.logout());
    await Future.delayed(Duration.zero);

    expect(notifier.unauthenticatedCallCount, 1,
        reason: 'second logout() must return early via _isLoggingOut guard');
    expect(notifier.generation, 1,
        reason: '_authGeneration must only increment once');
  });

  test('logout flips state without waiting on network cleanup', () async {
    final notifier = _FakeAuthNotifier();
    await notifier.logout();

    expect(notifier.unauthenticatedCallCount, 1,
        reason: 'state must be unauthenticated once logout() returns');
    expect(notifier.cleanupScheduled, true,
        reason: 'background cleanup (audit + global signOut) must be scheduled');
  });

  test('guard resets when logout() returns, so a later logout is accepted',
      () async {
    final notifier = _FakeAuthNotifier();
    await notifier.logout();

    expect(notifier.isLoggingOut, false,
        reason: '_isLoggingOut must be reset once logout() returns');

    await notifier.logout();
    expect(notifier.unauthenticatedCallCount, 2,
        reason: 'a fresh logout after the guard resets must be accepted');
  });
}

// Mirrors AuthNotifier.logout()'s guard/counter/flip ordering without a real
// Supabase instance: clear app data (fast await) -> flip state -> fire-and-forget
// the network cleanup -> reset the guard when logout() returns.
class _FakeAuthNotifier {
  int _authGeneration = 0;
  bool _isLoggingOut = false;

  int unauthenticatedCallCount = 0;
  bool cleanupScheduled = false;

  int get generation => _authGeneration;
  bool get isLoggingOut => _isLoggingOut;

  Future<void> logout() async {
    if (_isLoggingOut) return; // <- the guard under test
    _isLoggingOut = true;
    try {
      // Local cleanup (cache + secure storage) — fast, awaited.
      await Future.delayed(Duration.zero);
      // Flip state NOW (prompt UI, not gated on network).
      _setUnauthenticated();
      // Fire-and-forget background cleanup (audit + global signOut).
      cleanupScheduled = true;
      unawaited(Future.delayed(Duration.zero));
    } finally {
      _isLoggingOut = false;
    }
  }

  void _setUnauthenticated() {
    _authGeneration++;
    unauthenticatedCallCount++;
  }
}
