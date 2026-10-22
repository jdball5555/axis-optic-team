// Push notifications on the phone (Android / iOS).
//
// Each phone saves its Firebase Cloud Messaging token on the team member's
// record (stores/{storeId}/users/{memberId}.fcm_tokens). The website writes
// what to send to /notifications, and the sendDueNotifications Cloud Function
// (functions/index.js) sends it to those tokens when it's due.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class PushService {
  PushService._();

  /// Push works in the Android and iOS apps (not the website).
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// The last notification the person tapped to open the app.
  static final opened = ValueNotifier<RemoteMessage?>(null);

  /// A notification that arrived while the app was open (phones don't show
  /// those, so the app does).
  static final foreground = ValueNotifier<RemoteMessage?>(null);

  static StreamSubscription<String>? _refreshSub;
  static String? _token;
  static ({String storeId, String memberId})? _member;

  static DocumentReference<Map<String, dynamic>> _doc(
    String storeId,
    String memberId,
  ) => FirebaseFirestore.instance
      .collection('stores')
      .doc(storeId)
      .collection('users')
      .doc(memberId);

  /// Call once at startup (after Firebase.initializeApp).
  static Future<void> init() async {
    if (!supported) return;
    try {
      FirebaseMessaging.onMessageOpenedApp.listen((m) => opened.value = m);
      FirebaseMessaging.onMessage.listen((m) => foreground.value = m);
      final first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) opened.value = first;
    } catch (e) {
      debugPrint('Push init failed: $e');
    }
  }

  /// Is this person's phone allowed to show notifications?
  static Future<bool> permitted() async {
    if (!supported) return false;
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      return s.authorizationStatus == AuthorizationStatus.authorized ||
          s.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  /// Turns notifications on for this phone: asks for permission (the phone
  /// only asks once) and saves this phone's token on the team member.
  /// [remember] also saves their choice (the Settings switch).
  /// Returns false when notifications are blocked.
  static Future<bool> enable(
    String storeId,
    String memberId, {
    bool remember = false,
  }) async {
    if (!supported || storeId.isEmpty || memberId.isEmpty) return false;
    final fm = FirebaseMessaging.instance;
    final settings = await fm.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return false;
    }
    final token = await fm.getToken();
    if (token == null || token.isEmpty) return false;

    // Moved to another store / person on this phone: take the token off the
    // old record first.
    final before = _member;
    if (before != null &&
        (before.storeId != storeId || before.memberId != memberId)) {
      await _remove(before.storeId, before.memberId, token);
    }

    _token = token;
    _member = (storeId: storeId, memberId: memberId);
    await _doc(storeId, memberId).update({
      'fcm_tokens': FieldValue.arrayUnion([token]),
      'notifications_enabled': ?(remember ? true : null),
    });

    _refreshSub ??= fm.onTokenRefresh.listen((fresh) async {
      final m = _member;
      final old = _token;
      _token = fresh;
      if (m == null) return;
      try {
        await _doc(m.storeId, m.memberId).update({
          'fcm_tokens': FieldValue.arrayUnion([fresh]),
        });
        if (old != null && old != fresh) {
          await _remove(m.storeId, m.memberId, old);
        }
      } catch (e) {
        debugPrint('Push token refresh failed: $e');
      }
    });
    return true;
  }

  /// This phone's notification address (asks for permission first).
  /// Null when notifications are blocked or unavailable.
  static Future<String?> thisPhone() async {
    if (!supported) return null;
    final fm = FirebaseMessaging.instance;
    final settings = await fm.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
    final token = await fm.getToken();
    return token == null || token.isEmpty ? null : token;
  }

  /// The Settings switch turned off: stop sending to this phone.
  static Future<void> disable(String storeId, String memberId) async {
    if (storeId.isEmpty || memberId.isEmpty) return;
    String? token = _token;
    if (token == null && supported) {
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (_) {}
    }
    await _doc(storeId, memberId).update({
      'notifications_enabled': false,
      'fcm_tokens': ?(token == null ? null : FieldValue.arrayRemove([token])),
    });
  }

  /// Signing out: this phone shouldn't get their notifications any more.
  static Future<void> signOut(String? storeId, String? memberId) async {
    if (!supported) return;
    final m = _member;
    final sid = storeId ?? m?.storeId;
    final mid = memberId ?? m?.memberId;
    _member = null;
    try {
      final token = _token ?? await FirebaseMessaging.instance.getToken();
      if (token != null && sid != null && mid != null) {
        await _remove(sid, mid, token);
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('Push sign out failed: $e');
    }
    _token = null;
  }

  static Future<void> _remove(String storeId, String memberId, String token) =>
      _doc(storeId, memberId).update({
        'fcm_tokens': FieldValue.arrayRemove([token]),
      });
}
