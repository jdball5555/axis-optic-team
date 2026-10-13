import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../firebase_options.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../models/user_model.dart';

class AccessView extends ConsumerStatefulWidget {
  const AccessView({super.key});

  @override
  ConsumerState<AccessView> createState() => _AccessViewState();
}

class _AccessViewState extends ConsumerState<AccessView> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  bool _isSaving = false;

  final Map<String, Map<String, bool>> _pendingChanges = {};
  final Map<String, bool> _userIsGlobal = {};

  Future<List<UserModel>> _fetchRegisteredTeamMembers() async {
    final storeId = ref.read(currentStoreIdProvider) ?? '121';
    final snapshot = await FirebaseFirestore.instance.collection('users').where('owned_stores', arrayContains: storeId).get();
    final users = snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return UserModel.fromJson(data);
    }).toList();
    
    // Filter out existing privileged users (owners/bots)
    return users.where((u) {
      final t = u.title?.toLowerCase() ?? '';
      final r = u.role?.toLowerCase() ?? '';
      if (t == 'owner' || t == 'bot' || r == 'bot' || r == 'owner') return false;
      return true;
    }).toList();
  }

  void _setPendingAccess(String userId, String accessKey, bool val, bool isGlobal) {
    setState(() {
      _pendingChanges.putIfAbsent(userId, () => {})[accessKey] = val;
      _userIsGlobal[userId] = isGlobal;
    });
    
    // Update global state for MainLayout sidebar protection
    ref.read(unsavedChangesProvider.notifier).state = _pendingChanges.isNotEmpty;
    ref.read(saveChangesActionProvider.notifier).state = _saveChanges;
  }

  Future<void> _saveChanges() async {
    if (_pendingChanges.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final storeId = ref.read(currentStoreIdProvider) ?? '121';
      for (final entry in _pendingChanges.entries) {
        final userId = entry.key;
        final changes = entry.value;
        final isGlobal = _userIsGlobal[userId] ?? false;
        
        final updateData = <String, dynamic>{};
        changes.forEach((k, v) => updateData['access_levels.$k'] = v);
        
        if (isGlobal) {
          await FirebaseFirestore.instance.collection('users').doc(userId).update(updateData);
        } else {
          await FirebaseFirestore.instance.collection('stores').doc(storeId).collection('users').doc(userId).update(updateData);
        }
      }
      setState(() {
        _pendingChanges.clear();
        _userIsGlobal.clear();
      });
      ref.read(unsavedChangesProvider.notifier).state = false;
      ref.read(saveChangesActionProvider.notifier).state = null;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Changes saved successfully.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving changes: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handlePop() async {
    if (_pendingChanges.isEmpty) {
      context.pop();
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text('Unsaved Changes', style: TextStyle(color: Theme.of(context).textTheme.titleLarge?.color)),
        content: Text('You have unsaved changes. Do you want to save or discard them?', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'cancel'), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: const Text('Discard', style: TextStyle(color: Colors.red))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, 'save'), 
            child: const Text('Save Changes')
          ),
        ]
      )
    );
    if (result == 'discard') {
      ref.read(unsavedChangesProvider.notifier).state = false;
      ref.read(saveChangesActionProvider.notifier).state = null;
      if (mounted) context.pop();
    } else if (result == 'save') {
      await _saveChanges();
      if (mounted) context.pop();
    }
  }

  Future<void> _showAddAccessDialog() async {
    bool isBot = true; // Default to Bot Account
    UserModel? selectedTeamMember;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              title: Text('Add or Give Account Access', style: TextStyle(color: Theme.of(context).textTheme.titleLarge?.color)),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<bool>(
                            title: const Text('Bot Account (View Only)'),
                            value: true,
                            groupValue: isBot,
                            onChanged: (val) {
                              setStateDialog(() {
                                isBot = val!;
                              });
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<bool>(
                            title: const Text('Team Member'),
                            value: false,
                            groupValue: isBot,
                            onChanged: (val) {
                              setStateDialog(() {
                                isBot = val!;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (isBot) ...[
                      TextField(
                        controller: _nameController,
                        style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                        decoration: const InputDecoration(labelText: 'Bot Name', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _emailController,
                        style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                        decoration: const InputDecoration(labelText: 'Bot Email', border: OutlineInputBorder()),
                      ),
                    ] else ...[
                      FutureBuilder<List<UserModel>>(
                        future: _fetchRegisteredTeamMembers(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const CircularProgressIndicator();
                          }
                          if (snapshot.hasError) {
                            return Text('Error: ${snapshot.error}');
                          }
                          final users = snapshot.data ?? [];
                          if (users.isEmpty) return const Text('No registered team members found. Team members must create an account first.');
                          
                          return DropdownButtonFormField<UserModel>(
                            decoration: const InputDecoration(labelText: 'Select Registered Team Member', border: OutlineInputBorder()),
                            value: selectedTeamMember,
                            items: users.map((u) => DropdownMenuItem(
                              value: u,
                              child: Text('${u.firstName} ${u.lastName}'),
                            )).toList(),
                            onChanged: (val) {
                              setStateDialog(() {
                                selectedTeamMember = val;
                              });
                            },
                          );
                        },
                      ),
                    ]
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
                  onPressed: _isLoading ? null : () async {
                    if (isBot) {
                      await _createBotAccount();
                    } else {
                      if (selectedTeamMember != null) {
                        await _giveTeamMemberAccess(selectedTeamMember!);
                      }
                    }
                  },
                  child: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Confirm'),
                ),
              ],
            );
          }
        );
      }
    );
  }

  Future<void> _giveTeamMemberAccess(UserModel user) async {
    _setPendingAccess(user.id!, 'Appear in Roster', true, true);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _createBotAccount() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty || email.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final rnd = Random();
      final tempPassword = String.fromCharCodes(Iterable.generate(12, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
      
      FirebaseApp secondaryApp = await Firebase.initializeApp(
        name: 'Secondary_${DateTime.now().millisecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      String uid = '';
      try {
         final userCredential = await FirebaseAuth.instanceFor(app: secondaryApp).createUserWithEmailAndPassword(email: email, password: tempPassword);
         uid = userCredential.user!.uid;
      } finally {
         await secondaryApp.delete();
      }
      
      final storeId = ref.read(currentStoreIdProvider) ?? '121';
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'first_name': name,
        'last_name': 'Bot',
        'email': email,
        'owned_stores': [storeId],
        'role': 'bot',
        'title': 'Bot',
        'access_levels': {
          'Appear in Roster': false,
        }
      });

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bot Account created! PW: $tempPassword')));
        _nameController.clear();
        _emailController.clear();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allUsersAsync = ref.watch(allStoreUsersStreamProvider);
    final settingsAsync = ref.watch(storeSettingsProvider);
    final isScheduleEnabled = settingsAsync.valueOrNull?.isScheduleEnabled ?? false;
    final isShiftBoardEnabled = settingsAsync.valueOrNull?.isShiftBoardEnabled ?? false;

    final columns = [
      'Appear in Roster',
      'Access Team Members',
      'Access Roster',
      if (isScheduleEnabled) 'Access Schedule',
      if (isShiftBoardEnabled) 'Access Shift Board',
    ];

    return PopScope(
      canPop: _pendingChanges.isEmpty,
      onPopInvoked: (didPop) {
        if (!didPop) _handlePop();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Access Management'),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Theme.of(context).textTheme.bodyLarge?.color),
            onPressed: () => _handlePop(),
          ),
          actions: [
            if (_pendingChanges.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveChanges,
                  icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
                  label: const Text('Save Changes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      body: allUsersAsync.when(
        data: (users) {
          // Filter to those with > team member access
          // "Owner", "Bot", or anyone with an access_levels entry set to true
          final privilegedUsers = users.where((u) {
            final t = u.title?.toLowerCase() ?? '';
            final r = u.role?.toLowerCase() ?? '';
            if (t == 'owner' || t == 'bot' || r == 'bot' || r == 'owner') return true;
            if (u.accessLevels != null && u.accessLevels!.values.any((v) => v == true)) return true;
            return false;
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Privileged Accounts', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add or Give Account Access'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
                    onPressed: _showAddAccessDialog,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                color: Theme.of(context).cardColor,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      const DataColumn(label: Text('Name')),
                      const DataColumn(label: Text('Type')),
                      ...columns.map((col) => DataColumn(label: Text(col))),
                    ],
                    rows: privilegedUsers.map((user) {
                      final isOwner = user.title?.toLowerCase() == 'owner' || user.role?.toLowerCase() == 'owner';
                      final isGlobal = isOwner || user.title?.toLowerCase() == 'bot' || user.role?.toLowerCase() == 'bot';
                      final type = (user.title?.toLowerCase() == 'bot' || user.role?.toLowerCase() == 'bot') 
                          ? 'Bot' 
                          : (isOwner ? 'Owner' : 'Team Member');
                          
                      return DataRow(
                        cells: [
                          DataCell(Text('${user.firstName} ${user.lastName}')),
                          DataCell(Chip(label: Text(type))),
                          ...columns.map((col) {
                            if (isOwner && col != 'Appear in Roster') {
                              return const DataCell(SizedBox.shrink()); // Owners don't get checkboxes for these
                            }
                            final pendingVal = _pendingChanges[user.id]?[col];
                            final hasAccess = pendingVal ?? user.accessLevels?[col] ?? false;
                            return DataCell(
                              Checkbox(
                                value: hasAccess,
                                onChanged: (val) {
                                  if (val != null) {
                                    _setPendingAccess(user.id!, col, val, isGlobal);
                                  }
                                },
                              ),
                            );
                          }),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    ));
  }
}
