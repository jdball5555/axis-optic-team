import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

/// Helper to persist user first and last name across Firestore, FirebaseAuth, and Riverpod.
Future<void> updateUserName({
  required WidgetRef ref,
  required String newFirst,
  required String newLast,
}) async {
  final currentUser = ref.read(currentUserProvider);
  if (currentUser == null) return;
  final uid =
      currentUser['id'] as String? ?? FirebaseAuth.instance.currentUser?.uid;

  if (uid != null && uid.isNotEmpty) {
    try {
      // 1. Update root users collection
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'first_name': newFirst,
        'last_name': newLast,
      }, SetOptions(merge: true));
    } catch (_) {}

    // 2. Update in owned stores' users collections if present
    final ownedStores = List<String>.from(currentUser['owned_stores'] ?? []);
    for (final sid in ownedStores) {
      try {
        final storeDoc = FirebaseFirestore.instance
            .collection('stores')
            .doc(sid)
            .collection('users')
            .doc(uid);
        final snap = await storeDoc.get();
        if (snap.exists) {
          await storeDoc.update({'first_name': newFirst, 'last_name': newLast});
        }
      } catch (_) {}
    }

    final currentStoreId = ref.read(currentStoreIdProvider);
    if (currentStoreId != null && !ownedStores.contains(currentStoreId)) {
      try {
        final storeDoc = FirebaseFirestore.instance
            .collection('stores')
            .doc(currentStoreId)
            .collection('users')
            .doc(uid);
        final snap = await storeDoc.get();
        if (snap.exists) {
          await storeDoc.update({'first_name': newFirst, 'last_name': newLast});
        }
      } catch (_) {}
    }
  }

  // 3. Update FirebaseAuth display name
  try {
    await FirebaseAuth.instance.currentUser?.updateDisplayName(
      '$newFirst $newLast'.trim(),
    );
  } catch (_) {}

  // 4. Update Riverpod currentUserProvider state
  ref.read(currentUserProvider.notifier).state = {
    ...currentUser,
    'first_name': newFirst,
    'last_name': newLast,
  };
}

/// Helper to persist user email across Firestore, FirebaseAuth, and Riverpod.
/// The user's password remains unchanged.
Future<void> updateUserEmail({
  required WidgetRef ref,
  required String newEmail,
}) async {
  final cleanEmail = newEmail.trim().toLowerCase();
  if (cleanEmail.isEmpty || !cleanEmail.contains('@') || !cleanEmail.contains('.')) {
    throw Exception('Please enter a valid email address.');
  }

  final currentUser = ref.read(currentUserProvider);
  if (currentUser == null) throw Exception('Not logged in.');
  final uid =
      currentUser['id'] as String? ?? FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid.isEmpty) throw Exception('User ID not found.');

  bool updatedViaEndpoint = false;
  // 1. Try invoking Cloud Function endpoint with user ID token
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final token = await user.getIdToken();
      final url = Uri.parse(
        'https://us-central1-project-attendance-app.cloudfunctions.net/changeUserEmail',
      );
      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'newEmail': cleanEmail}),
      );
      if (res.statusCode == 200) {
        updatedViaEndpoint = true;
      } else if (res.statusCode == 409) {
        throw Exception('This email address is already in use by another account.');
      }
    }
  } catch (e) {
    if (e.toString().contains('already in use')) rethrow;
  }

  // 2. Update root users collection in Firestore (which triggers onUserWritten to update Auth)
  if (!updatedViaEndpoint) {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'email': cleanEmail,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Update in owned stores' users collections if present
    final ownedStores = List<String>.from(currentUser['owned_stores'] ?? []);
    for (final sid in ownedStores) {
      try {
        final storeDoc = FirebaseFirestore.instance
            .collection('stores')
            .doc(sid)
            .collection('users')
            .doc(uid);
        final snap = await storeDoc.get();
        if (snap.exists) {
          await storeDoc.update({'email': cleanEmail});
        }
      } catch (_) {}
    }

    final currentStoreId = ref.read(currentStoreIdProvider);
    if (currentStoreId != null && !ownedStores.contains(currentStoreId)) {
      try {
        final storeDoc = FirebaseFirestore.instance
            .collection('stores')
            .doc(currentStoreId)
            .collection('users')
            .doc(uid);
        final snap = await storeDoc.get();
        if (snap.exists) {
          await storeDoc.update({'email': cleanEmail});
        }
      } catch (_) {}
    }
  }

  // 3. Update saved_email in SharedPreferences
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('saved_email') != null) {
      await prefs.setString('saved_email', cleanEmail);
    }
  } catch (_) {}

  // 4. Update Riverpod currentUserProvider state
  ref.read(currentUserProvider.notifier).state = {
    ...currentUser,
    'email': cleanEmail,
  };
}

/// Fallback dialog if a modal is ever requested.
Future<void> showChangeNameDialog(BuildContext context, WidgetRef ref) async {
  final currentUser = ref.read(currentUserProvider);
  if (currentUser == null) return;

  final firstController = TextEditingController(
    text: currentUser['first_name'] as String? ?? '',
  );
  final lastController = TextEditingController(
    text: currentUser['last_name'] as String? ?? '',
  );

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      bool isSaving = false;
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          final theme = Theme.of(dialogContext);
          return AlertDialog(
            backgroundColor: theme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.badge_outlined, color: AppTheme.accent, size: 24),
                const SizedBox(width: 10),
                Text(
                  'Change Your Name',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.titleLarge?.color,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Update the first and last name for your account.',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: firstController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                    decoration: const InputDecoration(
                      labelText: 'First Name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: lastController,
                    textCapitalization: TextCapitalization.words,
                    style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                    decoration: const InputDecoration(
                      labelText: 'Last Name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        final newFirst = firstController.text.trim();
                        final newLast = lastController.text.trim();
                        if (newFirst.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('First name cannot be empty.'),
                            ),
                          );
                          return;
                        }

                        setState(() => isSaving = true);
                        await updateUserName(
                          ref: ref,
                          newFirst: newFirst,
                          newLast: newLast,
                        );

                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Name updated to $newFirst $newLast',
                              ),
                            ),
                          );
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Modal dialog to prompt the user for a new email.
/// Password stays unchanged.
Future<void> showChangeEmailDialog(BuildContext context, WidgetRef ref) async {
  final currentUser = ref.read(currentUserProvider);
  if (currentUser == null) return;

  final emailController = TextEditingController(
    text: currentUser['email'] as String? ?? '',
  );

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      bool isSaving = false;
      String? errorMessage;

      return StatefulBuilder(
        builder: (dialogContext, setState) {
          final theme = Theme.of(dialogContext);
          return AlertDialog(
            backgroundColor: theme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.email_outlined, color: AppTheme.accent, size: 22),
                const SizedBox(width: 8),
                const Text('Change Email'),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'When you change your email, your password stays the same. You will use this new email to sign in.',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    enabled: !isSaving,
                    decoration: InputDecoration(
                      labelText: 'New Email Address',
                      errorText: errorMessage,
                      filled: true,
                      fillColor: theme.scaffoldBackgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        final newEmail = emailController.text.trim();
                        if (newEmail.isEmpty || !newEmail.contains('@') || !newEmail.contains('.')) {
                          setState(() {
                            errorMessage = 'Please enter a valid email address.';
                          });
                          return;
                        }

                        setState(() {
                          isSaving = true;
                          errorMessage = null;
                        });

                        try {
                          await updateUserEmail(
                            ref: ref,
                            newEmail: newEmail,
                          );

                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Email updated to $newEmail. Your password remains unchanged.',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setState(() {
                              isSaving = false;
                              errorMessage = e.toString().replaceAll('Exception: ', '');
                            });
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save Email'),
              ),
            ],
          );
        },
      );
    },
  );
}
