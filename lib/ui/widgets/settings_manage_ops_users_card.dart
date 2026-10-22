import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../firebase_options.dart';
import '../../core/theme/app_theme.dart';

class SettingsManageOpsUsersCard extends StatefulWidget {
  final String storeId;

  const SettingsManageOpsUsersCard({super.key, required this.storeId});

  @override
  State<SettingsManageOpsUsersCard> createState() =>
      _SettingsManageOpsUsersCardState();
}

class _SettingsManageOpsUsersCardState
    extends State<SettingsManageOpsUsersCard> {
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  bool _isLoading = false;

  Future<void> _generateUser() async {
    final email = _emailController.text.trim();
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();

    if (email.isEmpty || first.isEmpty || last.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      const chars =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final rnd = Random();
      final tempPassword = String.fromCharCodes(
        Iterable.generate(
          8,
          (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
        ),
      );

      FirebaseApp secondaryApp = await Firebase.initializeApp(
        name: 'Secondary_${DateTime.now().millisecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      String uid = '';
      try {
        final userCredential = await FirebaseAuth.instanceFor(
          app: secondaryApp,
        ).createUserWithEmailAndPassword(email: email, password: tempPassword);
        uid = userCredential.user!.uid;
      } finally {
        await secondaryApp.delete();
      }

      // We create them in the global users collection so they can log in.
      // But we DO NOT add them to /stores/{storeId}/users.
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'first_name': first,
        'last_name': last,
        'email': email,
        'owned_stores': [widget.storeId],
        'is_ops_only': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ops user generated! Email: $email | Password: $tempPassword. (Simulated sending email)',
            ),
          ),
        );
        _emailController.clear();
        _firstNameController.clear();
        _lastNameController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error generating user: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Generate Ops User',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'These users can log in and view the Ops page for this store, but will not appear on the team roster.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _firstNameController,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'First Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _lastNameController,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Last Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _generateUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Send Email Invite'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
