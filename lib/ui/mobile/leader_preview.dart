// Leader tools in phone Settings: test the promotion moment on yourself
// (nothing saves). "View as team member" lives in mobile_data.dart.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/push_service.dart';
import 'mobile_data.dart';
import 'mobile_ui.dart';
import 'promotion_page.dart';

/// Tests the promotion on yourself (to Operator): sends this phone a real
/// promotion notification, and the congratulations plays the next time you
/// open the app or when you tap the notification. Nothing about your
/// account changes.
Future<void> startPromotionTest(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(storeSettingsProvider).valueOrNull;
  final access = ref.read(mobileAccessProvider);
  final user = ref.read(currentUserProvider);
  const to = 'Operator';
  var from =
      access.member?.title ??
      (access.isOwner
          ? 'Owner'
          : access.isBot
          ? 'Bot'
          : 'Team Member');
  if (from == to) {
    // Already an Operator: pretend it's from the title before it.
    final titles = settings?.titles ?? const [];
    final i = titles.indexWhere((t) => t.name == to);
    from = i > 0 ? titles[i - 1].name : 'Director';
  }
  final name = access.member != null
      ? firstNameOf(access.member)
      : (user?['first_name'] as String? ?? '').trim();

  final now = DateTime.now();
  final promotion = Promotion(
    id: 'test-${now.millisecondsSinceEpoch}',
    from: from,
    to: to,
    date: DateTime(now.year, now.month, now.day),
    // Plays the next time the app is opened (not right now).
    revealAt: now.add(const Duration(seconds: 2)),
    seen: false,
  );
  await TestPromotion.save(promotion);
  ref.read(promotionTestProvider.notifier).state = promotion;

  String? problem;
  final token = await PushService.thisPhone().catchError((_) => null);
  if (!PushService.supported) {
    problem = 'Notifications only work in the phone app.';
  } else if (token == null) {
    problem =
        'Notifications are turned off for Axis Team on this phone. '
        'Turn them on in your phone\'s settings to get the notification.';
  } else {
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'type': 'promotion_test',
        'tokens': [token],
        'store_id': ref.read(currentStoreIdProvider),
        'to': to,
        'first_name': name,
        'title': name.isEmpty
            ? 'Congratulations! 🎉'
            : 'Congratulations, $name! 🎉',
        'body': 'You\'ve been promoted to $to. Tap to see your new title.',
        'send_at': Timestamp.fromDate(now),
        'status': 'scheduled',
        'created_at': FieldValue.serverTimestamp(),
        'created_by': FirebaseAuth.instance.currentUser?.uid,
      });
    } catch (e) {
      problem = 'The notification couldn\'t be sent ($e).';
    }
  }

  if (!context.mounted) return;
  final c = MColors(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(ctx).cardColor,
      title: Text(problem == null ? 'Test notification sent' : 'Test is ready'),
      content: Text(
        problem == null
            ? 'Leave the app. Within about a minute you\'ll get the promotion '
                  'notification. Tap it (or just open Axis Team again) to see '
                  'the whole thing.\n\nNothing about your account changes.'
            : '$problem\n\nLeave the app and open it again to see the promotion. '
                  'Nothing about your account changes.',
        style: TextStyle(color: c.text, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
