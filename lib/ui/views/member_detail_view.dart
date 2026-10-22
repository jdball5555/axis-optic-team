import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../widgets/multi_select_field.dart';
import '../../models/store_settings_model.dart';
import '../../models/title_journey.dart';

class MemberDetailView extends ConsumerStatefulWidget {
  final String userId;
  final String? returnPath;
  const MemberDetailView({super.key, required this.userId, this.returnPath});

  @override
  ConsumerState<MemberDetailView> createState() => _MemberDetailViewState();
}

class _MemberDetailViewState extends ConsumerState<MemberDetailView> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _preferredNameController;
  late TextEditingController _titleController;
  late TextEditingController _startDateController;
  late TextEditingController _storeController;
  late TextEditingController _positionController;
  late TextEditingController _designationController;
  late TextEditingController _additionalTagsController;
  late TextEditingController _workingTimeController;
  late TextEditingController _avgShiftsController;
  late TextEditingController _payRateController;
  late TextEditingController _foodHandlersController;
  late TextEditingController _generalNotesController;
  late TextEditingController _hiringNotesController;
  late TextEditingController _endDateController;
  late TextEditingController _managerPermitController;

  UserModel? _initialUser;
  bool _isSaving = false;
  bool _showPreferredName = false;
  bool _showEndDate = false;
  List<Map<String, dynamic>> _historyLogs = [];

  final Map<String, ProviderSubscription<AsyncValue<UserModel?>>>
      _preloadUserSubs = {};
  final Map<String, ProviderSubscription<AsyncValue<List<Map<String, dynamic>>>>>
      _preloadTimeOffSubs = {};
  final Map<String, ProviderSubscription<AsyncValue<Map<String, dynamic>?>>>
      _preloadAvailabilitySubs = {};

  @override
  void didUpdateWidget(MemberDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userId != oldWidget.userId) {
      _initialUser = null;
      final sortedUsers = ref.read(sortedUsersProvider).valueOrNull ?? [];
      final immediateUser =
          sortedUsers.where((u) => u.id == widget.userId).firstOrNull;
      if (immediateUser != null) {
        _initControllers(immediateUser, force: true);
      }
    }
  }

  void _clearPreloadWindow() {
    if (_preloadUserSubs.isNotEmpty) {
      for (final sub in _preloadUserSubs.values) {
        sub.close();
      }
      for (final sub in _preloadTimeOffSubs.values) {
        sub.close();
      }
      for (final sub in _preloadAvailabilitySubs.values) {
        sub.close();
      }
      _preloadUserSubs.clear();
      _preloadTimeOffSubs.clear();
      _preloadAvailabilitySubs.clear();
    }
  }

  void _updatePreloadWindow(List<UserModel> sortedUsers, int currentIndex) {
    if (currentIndex == -1 || sortedUsers.isEmpty) return;
    final start = (currentIndex - 2).clamp(0, sortedUsers.length - 1);
    final end = (currentIndex + 2).clamp(0, sortedUsers.length - 1);

    final targetIds = <String>{};
    for (int i = start; i <= end; i++) {
      final uid = sortedUsers[i].id;
      if (uid != null && uid.isNotEmpty) {
        targetIds.add(uid);
      }
    }

    // 1. Unload profiles moved more than 2 away
    final toRemove = _preloadUserSubs.keys
        .where((id) => !targetIds.contains(id))
        .toList();
    for (final id in toRemove) {
      _preloadUserSubs[id]?.close();
      _preloadUserSubs.remove(id);
      _preloadTimeOffSubs[id]?.close();
      _preloadTimeOffSubs.remove(id);
      _preloadAvailabilitySubs[id]?.close();
      _preloadAvailabilitySubs.remove(id);
    }

    // 2. Preload profiles within 2 away
    for (final id in targetIds) {
      if (!_preloadUserSubs.containsKey(id)) {
        _preloadUserSubs[id] = ref.listenManual(
          userStreamProvider(id),
          (previous, next) {},
        );
      }
      if (!_preloadTimeOffSubs.containsKey(id)) {
        _preloadTimeOffSubs[id] = ref.listenManual(
          userTimeOffRequestsProvider(id),
          (previous, next) {},
        );
      }
      if (!_preloadAvailabilitySubs.containsKey(id)) {
        _preloadAvailabilitySubs[id] = ref.listenManual(
          userAvailabilityProvider(id),
          (previous, next) {},
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _preferredNameController = TextEditingController();
    _titleController = TextEditingController();
    _startDateController = TextEditingController();
    _storeController = TextEditingController();
    _positionController = TextEditingController();
    _designationController = TextEditingController();
    _additionalTagsController = TextEditingController();
    _workingTimeController = TextEditingController();
    _avgShiftsController = TextEditingController();
    _payRateController = TextEditingController();
    _foodHandlersController = TextEditingController();
    _generalNotesController = TextEditingController();
    _hiringNotesController = TextEditingController();
    _endDateController = TextEditingController();
    _managerPermitController = TextEditingController();
  }

  void _initControllers(UserModel user, {bool force = false}) {
    if (_initialUser != null && !force && _initialUser!.id == user.id) return;
    _initialUser = user;

    _showPreferredName =
        user.preferredName != null && user.preferredName!.trim().isNotEmpty;
    _firstNameController.text = user.firstName ?? '';
    _lastNameController.text = user.lastName ?? '';
    _preferredNameController.text = user.preferredName ?? '';
    _titleController.text = user.title ?? '';
    _startDateController.text =
        user.startDate?.toIso8601String().split('T').first ?? '';
    _storeController.text = user.store ?? '';
    _positionController.text = user.position ?? '';
    _designationController.text = user.designation ?? '';
    _additionalTagsController.text = user.additionalTags?.join(', ') ?? '';
    _workingTimeController.text = user.workingTime ?? '';
    _avgShiftsController.text = user.avgShifts ?? '';
    _payRateController.text = user.payRate?.toString() ?? '';
    _foodHandlersController.text =
        user.foodHandlersExpiration?.toIso8601String().split('T').first ?? '';
    _generalNotesController.text = user.generalNotes ?? '';
    _hiringNotesController.text = user.hiringNotes ?? '';
    _endDateController.text =
        user.endDate?.toIso8601String().split('T').first ?? '';
    _managerPermitController.text =
        user.managerPermitExpiration?.toIso8601String().split('T').first ?? '';
    _showEndDate = user.endDate != null;
    _historyLogs = (user.historyLogs ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _preferredNameController.dispose();
    _titleController.dispose();
    _startDateController.dispose();
    _storeController.dispose();
    _positionController.dispose();
    _designationController.dispose();
    _additionalTagsController.dispose();
    _workingTimeController.dispose();
    _avgShiftsController.dispose();
    _payRateController.dispose();
    _foodHandlersController.dispose();
    _generalNotesController.dispose();
    _hiringNotesController.dispose();
    _endDateController.dispose();
    _managerPermitController.dispose();
    _clearPreloadWindow();
    super.dispose();
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: controller.text.isNotEmpty
          ? (DateTime.tryParse(controller.text) ?? DateTime.now())
          : DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(
            context,
          ).copyWith(colorScheme: Theme.of(context).colorScheme),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        controller.text = picked.toIso8601String().split('T').first;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_initialUser == null) return;

    setState(() => _isSaving = true);

    try {
      DateTime? foodPermit;
      if (_foodHandlersController.text.isNotEmpty) {
        foodPermit = DateTime.tryParse(_foodHandlersController.text.trim());
      }
      DateTime? startDate;
      if (_startDateController.text.isNotEmpty) {
        startDate = DateTime.tryParse(_startDateController.text.trim());
      }

      DateTime? endDate;
      if (_endDateController.text.isNotEmpty && _showEndDate) {
        endDate = DateTime.tryParse(_endDateController.text.trim());
      }

      DateTime? mgrPermit;
      if (_managerPermitController.text.isNotEmpty) {
        mgrPermit = DateTime.tryParse(_managerPermitController.text.trim());
      }

      double? payRate;
      if (_payRateController.text.isNotEmpty) {
        payRate = double.tryParse(_payRateController.text.trim());
      }

      List<String> tags = _additionalTagsController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final updatedUser = _initialUser!.copyWith(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        preferredName: _preferredNameController.text.trim(),
        title: _titleController.text.trim(),
        startDate: startDate,
        endDate: endDate,
        store: _storeController.text.trim(),
        position: _positionController.text.trim(),
        designation: _designationController.text.trim(),
        additionalTags: tags,
        workingTime: _workingTimeController.text.trim(),
        avgShifts: _avgShiftsController.text.trim(),
        payRate: payRate,
        foodHandlersExpiration: foodPermit,
        managerPermitExpiration: mgrPermit,
        generalNotes: _generalNotesController.text.trim(),
        hiringNotes: _hiringNotesController.text.trim(),
        historyLogs: _historyLogs,
      );

      final firestoreService = ref.read(firestoreServiceProvider);
      await firestoreService.updateUser(updatedUser);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteProfile() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          'Delete Profile?',
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this team member? This cannot be undone.',
          style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final firestoreService = ref.read(firestoreServiceProvider);
      await firestoreService.deleteUser(
        widget.userId,
        userStore: _initialUser?.store,
      );
      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting profile: $e')));
      }
    }
  }

  Widget _buildPill(String label, Color color, {bool filled = false}) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : AppTheme.tint(color),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.edge(color), width: 1.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: filled ? Colors.white : AppTheme.onTint(color),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildFieldGrid(
    BuildContext context,
    UserModel user,
    StoreSettingsModel settings,
  ) {
    final currentStoreId = ref.watch(currentStoreIdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ROW 1
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTextField(context, 'FIRST NAME', _firstNameController),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showPreferredName = !_showPreferredName;
                      });
                    },
                    icon: Icon(
                      _showPreferredName ? Icons.close : Icons.add,
                      size: 12,
                    ),
                    label: Text(
                      _showPreferredName
                          ? 'Remove Preferred Name'
                          : 'Preferred Name?',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2.0,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 28),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (_showPreferredName) ...[
              Expanded(
                child: _buildTextField(
                  context,
                  'PREFERRED NAME',
                  _preferredNameController,
                ),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: _buildTextField(context, 'LAST NAME', _lastNameController),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDropdownField(
                    context,
                    'TITLE',
                    _titleController,
                    settings.titles.map((e) => e.name).toList(),
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: () => _showPromoteDialog(settings),
                    icon: const Icon(Icons.emoji_events_outlined, size: 12),
                    label: const Text(
                      'Promoted?',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2.0,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 28),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTextField(
                    context,
                    'START DATE',
                    _startDateController,
                    icon: Icons.calendar_today,
                    onIconTap: () => _selectDate(_startDateController),
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showEndDate = !_showEndDate;
                        if (!_showEndDate) {
                          _endDateController.text = ''; // clear if closed
                        }
                      });
                    },
                    icon: Icon(
                      _showEndDate ? Icons.close : Icons.exit_to_app,
                      size: 12,
                    ),
                    label: Text(
                      _showEndDate ? 'Remove End Date' : 'Leaving?',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2.0,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 28),
                    ),
                  ),
                ],
              ),
            ),
            if (_showEndDate) ...[
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  context,
                  'END DATE',
                  _endDateController,
                  icon: Icons.calendar_today,
                  onIconTap: () => _selectDate(_endDateController),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        // ROW 2
        Row(
          children: [
            if (currentStoreId == null) ...[
              Expanded(
                child: Builder(
                  builder: (context) {
                    final allStoresAsync = ref.watch(allStoresStreamProvider);
                    return allStoresAsync.when(
                      data: (stores) {
                        if (stores.isEmpty) return const SizedBox.shrink();

                        if (!stores.any(
                          (s) => s['id'] == _storeController.text,
                        )) {
                          _storeController.text = stores.first['id'] as String;
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'STORE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).textTheme.bodySmall?.color,
                              ),
                            ),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<String>(
                              value: stores.any((s) => s['id'] == _storeController.text)
                                  ? _storeController.text
                                  : (stores.isNotEmpty ? stores.first['id'] as String : null),
                              items: stores.map((s) {
                                return DropdownMenuItem(
                                  value: s['id'] as String,
                                  child: Text(
                                    s['name'] as String? ?? 'Untitled Store',
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _storeController.text = val;
                                  });
                                }
                              },
                              decoration: const InputDecoration(),
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).textTheme.bodyLarge?.color,
                              ),
                              dropdownColor: Theme.of(context).cardColor,
                            ),
                          ],
                        );
                      },
                      loading: () => const CircularProgressIndicator(),
                      error: (e, st) => Text('Error loading stores: $e'),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: _buildDropdownField(
                context,
                'POSITION',
                _positionController,
                settings.positions,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdownField(
                context,
                'DESIGNATION',
                _designationController,
                settings.designations,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: AppMultiSelectDropdown<String>(
                label: 'ADDITIONAL TAGS',
                options: settings.tags.map((e) => e.name).toList(),
                selected: _additionalTagsController.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList(),
                allLabel: 'All Tags',
                emptyText: 'None',
                onChanged: (tags) => setState(
                  () => _additionalTagsController.text = tags.join(', '),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // ROW 3
        Row(
          children: [
            Expanded(
              child: _buildDropdownField(
                context,
                'WORKING TIME',
                _workingTimeController,
                settings.workingTimes,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                context,
                'AVG SHIFTS / WK',
                _avgShiftsController,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                context,
                'PAY (\$ / HR)',
                _payRateController,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                context,
                'FOOD PERMIT EXP.',
                _foodHandlersController,
                icon: Icons.calendar_today,
                onIconTap: () => _selectDate(_foodHandlersController),
              ),
            ),
            if (settings.titles.any(
              (t) => t.name == _titleController.text && t.mgrPermit,
            )) ...[
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  context,
                  'MANAGER PERMIT EXP.',
                  _managerPermitController,
                  icon: Icons.calendar_today,
                  onIconTap: () => _selectDate(_managerPermitController),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        // ROW 4
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildTextField(
                context,
                'GENERAL NOTES & COMMENTS',
                _generalNotesController,
                maxLines: 3,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                context,
                'HIRING NOTES',
                _hiringNotesController,
                maxLines: 3,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField(
    BuildContext context,
    String label,
    TextEditingController controller, {
    IconData? icon,
    int maxLines = 1,
    VoidCallback? onIconTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          readOnly: onIconTap != null,
          onTap: onIconTap,
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            suffixIcon: icon != null
                ? InkWell(
                    onTap: onIconTap,
                    child: Icon(
                      icon,
                      size: 16,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField(
    BuildContext context,
    String label,
    TextEditingController controller,
    List<String> options,
  ) {
    final uniqueOptions = options.toSet().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: uniqueOptions.contains(controller.text)
              ? controller.text
              : (uniqueOptions.isNotEmpty ? uniqueOptions.first : null),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                controller.text = val;
              });
            }
          },
          items: uniqueOptions
              .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
              .toList(),
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontSize: 14,
          ),
          dropdownColor: Theme.of(context).cardColor,
          decoration: const InputDecoration(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final allowMemberNavigation = widget.returnPath == '/' &&
        !(ModalRoute.of(context) is PopupRoute);

    final userAsyncValue = ref.watch(userStreamProvider(widget.userId));
    final sortedUsersAsync = ref.watch(sortedUsersProvider);

    int currentIndex = -1;
    int totalUsers = 0;
    UserModel? prevUser;
    UserModel? nextUser;

    final sortedUsers = sortedUsersAsync.valueOrNull ?? [];
    if (sortedUsers.isNotEmpty) {
      totalUsers = sortedUsers.length;
      currentIndex = sortedUsers.indexWhere((u) => u.id == widget.userId);

      if (currentIndex > 0) {
        prevUser = sortedUsers[currentIndex - 1];
      }
      if (currentIndex != -1 && currentIndex < totalUsers - 1) {
        nextUser = sortedUsers[currentIndex + 1];
      }
    }

    if (allowMemberNavigation) {
      _updatePreloadWindow(sortedUsers, currentIndex);
    } else {
      _clearPreloadWindow();
    }

    final fallbackUser =
        sortedUsers.where((u) => u.id == widget.userId).firstOrNull;
    final activeUser =
        userAsyncValue.valueOrNull ?? fallbackUser ?? _initialUser;

    if (activeUser != null) {
      _initControllers(activeUser);
    }

    final storeId =
        activeUser?.store ??
        ref.watch(currentStoreIdProvider) ??
        'QYfhsc0dBHLBbgOflHsA';
    final settings =
        ref.watch(specificStoreSettingsProvider(storeId)).valueOrNull ??
        const StoreSettingsModel();
    final isScheduleEnabled = settings.isScheduleEnabled;
    final isShiftBoardEnabled = settings.isShiftBoardEnabled;
    final isTeamMemberAccountsEnabled =
        isScheduleEnabled || isShiftBoardEnabled;

    if (activeUser == null && userAsyncValue.isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
    if (activeUser == null && userAsyncValue.hasError) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Text(
            'Error: ${userAsyncValue.error}',
            style: TextStyle(color: AppTheme.primaryRed),
          ),
        ),
      );
    }
    if (activeUser == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Text(
            'User not found.',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ),
      );
    }

    final user = activeUser;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: 24.0,
          vertical: 16.0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Action Bar
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                TextButton.icon(
                  onPressed: () {
                    if (ModalRoute.of(context) is PopupRoute) {
                      Navigator.of(context).pop();
                    } else if (widget.returnPath != null &&
                        widget.returnPath!.isNotEmpty) {
                      context.go(widget.returnPath!);
                    } else {
                      context.go('/');
                    }
                  },
                      icon: Icon(
                        ModalRoute.of(context) is PopupRoute
                            ? Icons.close
                            : Icons.arrow_back,
                        size: 16,
                      ),
                      label: Text(
                        ModalRoute.of(context) is PopupRoute
                            ? 'Close'
                            : widget.returnPath == '/rosters'
                            ? 'Back to Rosters'
                            : widget.returnPath == '/schedule'
                            ? 'Back to Schedule'
                            : widget.returnPath == '/shift'
                            ? 'Back to Shift'
                            : 'Back to Team Members Roster',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () =>
                              _showAddChecklistDialog(context, user, settings),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Checklist'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        if (allowMemberNavigation)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: Icon(
                                  Icons.arrow_back,
                                  size: 16,
                                  color: prevUser != null
                                      ? Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.color
                                      : Theme.of(context).dividerColor,
                                ),
                                onPressed: prevUser != null
                                    ? () {
                                        final fromParam =
                                            widget.returnPath != null
                                            ? '?from=${Uri.encodeComponent(widget.returnPath!)}'
                                            : '';
                                        context.go(
                                          '/member/${prevUser!.id}$fromParam',
                                        );
                                      }
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${currentIndex != -1 ? currentIndex + 1 : 0} of $totalUsers',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: Icon(
                                  Icons.arrow_forward,
                                  size: 16,
                                  color: nextUser != null
                                      ? Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.color
                                      : Theme.of(context).dividerColor,
                                ),
                                onPressed: nextUser != null
                                    ? () {
                                        final fromParam =
                                            widget.returnPath != null
                                            ? '?from=${Uri.encodeComponent(widget.returnPath!)}'
                                            : '';
                                        context.go(
                                          '/member/${nextUser!.id}$fromParam',
                                        );
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _deleteProfile,
                          icon: const Icon(Icons.delete, size: 16),
                          label: const Text('Delete Profile'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryRed,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Header Name
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${user.firstName ?? ''} ${user.lastName ?? ''}'.trim(),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Text(
                        'Start Date: ${user.startDate != null ? user.startDate!.toIso8601String().split('T').first : 'N/A'}',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Builder(
                      builder: (context) {
                        Color titleColor = AppTheme.lightBlue;
                        if (user.title != null) {
                          final tConf =
                              settings.titles
                                  .where((t) => t.name == user.title)
                                  .firstOrNull ??
                              settings.tags
                                  .where((t) => t.name == user.title)
                                  .firstOrNull;
                          final tColor = tConf?.color;
                          if (tColor != null) {
                            titleColor = AppTheme.getColorFromName(tColor);
                          }
                        }
                        return _buildPill(
                          user.title ?? 'In Training',
                          titleColor,
                        );
                      },
                    ),
                    if (user.position != null && user.position!.isNotEmpty)
                      _buildPill(user.position!, AppTheme.lightBlue),
                    if (user.designation != null &&
                        user.designation!.isNotEmpty)
                      _buildPill(user.designation!, AppTheme.lightBlue),
                    Builder(
                      builder: (context) {
                        final storeId = user.store ?? 'QYfhsc0dBHLBbgOflHsA';
                        final storeData = ref
                            .watch(storeStreamProvider(storeId))
                            .valueOrNull;
                        final name =
                            storeData?['name'] as String? ?? 'Untitled Store';
                        return _buildPill(name, AppTheme.lightBlue);
                      },
                    ),
                    _buildPill(memberStatus(user), switch (memberStatus(user)) {
                      'Active' => AppTheme.green,
                      'Leaving' => AppTheme.primaryRed,
                      _ => Colors.grey,
                    }),
                    if (user.additionalTags != null)
                      ...user.additionalTags!.map((tag) {
                        Color tagColor = AppTheme.lightBlue;
                        final tagConf = settings.tags
                            .where((t) => t.name == tag)
                            .firstOrNull;
                        final tagColorName = tagConf?.color;
                        if (tagColorName != null) {
                          tagColor = AppTheme.getColorFromName(tagColorName);
                        }
                        return _buildPill(tag, tagColor);
                      }),
                    if (user.foodHandlersExpiration == null)
                      _buildPill(
                        'No Food Permit',
                        AppTheme.primaryRed,
                        filled: true,
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                Builder(
                  builder: (context) {
                    final storeId = user.store ?? 'QYfhsc0dBHLBbgOflHsA';
                    final storeSettings =
                        ref
                            .watch(specificStoreSettingsProvider(storeId))
                            .valueOrNull ??
                        ref.watch(storeSettingsProvider).valueOrNull ??
                        const StoreSettingsModel();
                    return _buildChecklistSection(user, storeSettings);
                  },
                ),

                // Edit Form Card
                Card(
                  color: Theme.of(context).cardColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.assignment_ind_outlined,
                                color: Theme.of(
                                  context,
                                ).textTheme.titleLarge?.color,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Employee Profile Data',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.titleLarge?.color,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          _buildFieldGrid(context, user, settings),

                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _showEmployeeDataSummary(
                                  context,
                                  user,
                                  settings,
                                ),
                                icon: const Icon(
                                  Icons.description_outlined,
                                  size: 16,
                                ),
                                label: const Text('Employee Data Summary'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                  side: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: _isSaving ? null : _saveProfile,
                                icon: _isSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save, size: 16),
                                label: const Text('Save Profile Data'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 900;
                    if (isNarrow) {
                      return Column(
                        children: [
                          _buildAvailabilityCard(context, isScheduleEnabled),
                          const SizedBox(height: 16),
                          _buildTimeOffCard(context, isScheduleEnabled),
                          const SizedBox(height: 16),
                          _buildAccountCard(isTeamMemberAccountsEnabled),
                        ],
                      );
                    }
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildAvailabilityCard(
                              context,
                              isScheduleEnabled,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTimeOffCard(
                              context,
                              isScheduleEnabled,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildAccountCard(
                              isTeamMemberAccountsEnabled,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildHistoryLogCard(context),
              ],
            ),
          ),
        );
  }

  /// The store this team member belongs to.
  String get _memberStoreId => (_initialUser?.store?.isNotEmpty ?? false)
      ? _initialUser!.store!
      : (ref.read(currentStoreIdProvider) ?? 'QYfhsc0dBHLBbgOflHsA');

  Future<void> _showPromoteDialog(
    StoreSettingsModel settings, {
    VoidCallback? onDismiss,
  }) async {
    final storeId = _memberStoreId;
    final memberId = _initialUser?.id ?? widget.userId;

    // The journey (for the suggested next titles) and whether they have a
    // phone with notifications on.
    TitleJourney? saved;
    var hasPhone = false;
    try {
      saved = await ref
          .read(titleJourneyProvider(storeId).future)
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      final doc = await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('users')
          .doc(memberId)
          .get()
          .timeout(const Duration(seconds: 3));
      final tokens = doc.data()?['fcm_tokens'];
      hasPhone =
          tokens is List &&
          tokens.isNotEmpty &&
          doc.data()?['notifications_enabled'] != false;
    } catch (_) {}
    if (!mounted) return;

    final journey = journeyFor(saved, settings.titles);
    final choices = promotionChoices(
      _titleController.text,
      settings.titles,
      journey,
    );
    String selectedTitle =
        choices.firstOrNull ??
        (settings.titles.isNotEmpty ? settings.titles.first.name : '');
    DateTime promoteDate = DateTime.now();
    bool notify = true;
    int delay = 0; // minutes; -1 = a time picked below
    TimeOfDay? pickedTime;

    DateTime revealTime() {
      final now = DateTime.now();
      if (!notify) return now;
      if (delay >= 0) return now.add(Duration(minutes: delay));
      final t = pickedTime ?? TimeOfDay.fromDateTime(now);
      var at = DateTime(now.year, now.month, now.day, t.hour, t.minute);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      return at;
    }

    String timeText(DateTime d) {
      final now = DateTime.now();
      final t = TimeOfDay.fromDateTime(d).format(context);
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final sameDay =
          d.year == now.year && d.month == now.month && d.day == now.day;
      if (sameDay) return t;
      if (d.year == tomorrow.year &&
          d.month == tomorrow.month &&
          d.day == tomorrow.day) {
        return 'tomorrow at $t';
      }
      return '${d.month}/${d.day} at $t';
    }

    final firstName = (_preferredNameController.text.trim().isNotEmpty
        ? _preferredNameController.text.trim()
        : _firstNameController.text.trim());

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final muted = Theme.of(context).textTheme.bodySmall?.color;
            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              title: Text(
                'Promote Team Member',
                style: TextStyle(
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        value: settings.titles.any((t) => t.name == selectedTitle)
                            ? selectedTitle
                            : (settings.titles.isNotEmpty
                                  ? settings.titles.first.name
                                  : null),
                        items: settings.titles
                            .map((t) => t.name)
                            .toSet()
                            .map(
                              (name) => DropdownMenuItem(
                                value: name,
                                child: Row(
                                  children: [
                                    Text(name),
                                    if (choices.contains(name)) ...[
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.arrow_forward,
                                        size: 14,
                                        color: AppTheme.accent2,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setStateDialog(() => selectedTitle = val);
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'New Title',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (choices.length > 1) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Next on their journey: ${choices.join(' or ')}',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: promoteDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2101),
                          );
                          if (picked != null) {
                            setStateDialog(() => promoteDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Promotion Date',
                            border: OutlineInputBorder(),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                promoteDate.toIso8601String().split('T').first,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                              ),
                              Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Push notification to team member'),
                        subtitle: Text(
                          'Sends a notification to their phone and shows them a '
                          'congratulations screen in the Axis Team app.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                        value: notify,
                        onChanged: (v) => setStateDialog(() => notify = v),
                      ),
                      if (notify) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          value: delay,
                          decoration: const InputDecoration(
                            labelText: 'Send',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(value: 0, child: Text('Right away')),
                            const DropdownMenuItem(value: 15, child: Text('In 15 minutes')),
                            const DropdownMenuItem(value: 30, child: Text('In 30 minutes')),
                            const DropdownMenuItem(value: 60, child: Text('In 1 hour')),
                            const DropdownMenuItem(value: 120, child: Text('In 2 hours')),
                            DropdownMenuItem(
                              value: -1,
                              child: Text(
                                pickedTime == null
                                    ? 'At a time I pick…'
                                    : 'At ${pickedTime!.format(context)}',
                              ),
                            ),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            if (v == -1) {
                              final t = await showTimePicker(
                                context: context,
                                initialTime:
                                    pickedTime ??
                                    TimeOfDay.fromDateTime(
                                      DateTime.now().add(
                                        const Duration(hours: 1),
                                      ),
                                    ),
                              );
                              if (t == null) return;
                              setStateDialog(() {
                                pickedTime = t;
                                delay = -1;
                              });
                            } else {
                              setStateDialog(() => delay = v);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          delay == 0
                              ? '${firstName.isEmpty ? 'They' : firstName} will be notified as soon as you promote them.'
                              : '${firstName.isEmpty ? 'They' : firstName} will be notified at ${timeText(revealTime())}. '
                                    'Until then the app keeps showing their current title.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                        if (!hasPhone) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: AppTheme.orange,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'No phone with notifications turned on yet. They\'ll '
                                  'see the congratulations the next time they open the app.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.orange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: muted)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final oldTitle = _titleController.text;
                    final reveal = revealTime();
                    setState(() {
                      _titleController.text = selectedTitle;
                      _historyLogs.add({
                        'event': 'Promoted to $selectedTitle (from $oldTitle)',
                        'date': promoteDate.toIso8601String().split('T').first,
                      });
                      _saveProfile();
                    });
                    if (oldTitle != selectedTitle) {
                      _announcePromotion(
                        storeId: storeId,
                        memberId: memberId,
                        firstName: firstName,
                        from: oldTitle,
                        to: selectedTitle,
                        date: promoteDate,
                        revealAt: reveal,
                        notify: notify,
                      );
                    }
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Promote'),
                ),
              ],
            );
          },
        );
      },
    );
    if (onDismiss != null) onDismiss();
  }

  /// Records the promotion for the phone app (the congratulations screen and
  /// the title change it animates) and, when asked, schedules the push
  /// notification (sent by the sendDueNotifications Cloud Function).
  Future<void> _announcePromotion({
    required String storeId,
    required String memberId,
    required String firstName,
    required String from,
    required String to,
    required DateTime date,
    required DateTime revealAt,
    required bool notify,
  }) async {
    final db = FirebaseFirestore.instance;
    final note = db.collection('notifications').doc();
    final batch = db.batch();
    batch.set(
      db.collection('stores').doc(storeId).collection('users').doc(memberId),
      {
        'promotion': {
          'id': note.id,
          'from': from,
          'to': to,
          'date': date.toIso8601String().split('T').first,
          'reveal_at': Timestamp.fromDate(revealAt),
          'notify': notify,
          'seen': false,
          'created_at': FieldValue.serverTimestamp(),
        },
      },
      SetOptions(mergeFields: ['promotion']),
    );
    if (notify) {
      batch.set(note, {
        'type': 'promotion',
        'store_id': storeId,
        'member_id': memberId,
        'promotion_id': note.id,
        'title': firstName.isEmpty
            ? 'Congratulations! 🎉'
            : 'Congratulations, $firstName! 🎉',
        'body': 'You\'ve been promoted to $to. Tap to see your new title.',
        'send_at': Timestamp.fromDate(revealAt),
        'status': 'scheduled',
        'created_at': FieldValue.serverTimestamp(),
        'created_by': FirebaseAuth.instance.currentUser?.uid,
      });
    }
    try {
      await batch.commit();
      if (!mounted) return;
      final when = TimeOfDay.fromDateTime(revealAt).format(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notify
                ? (revealAt.difference(DateTime.now()).inMinutes < 1
                      ? 'Promoted to $to. Their notification is on its way.'
                      : 'Promoted to $to. Their notification goes out at $when.')
                : 'Promoted to $to.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Promoted, but the notification couldn\'t be scheduled: $e',
            ),
          ),
        );
      }
    }
  }

  Widget _buildChecklistSection(UserModel user, StoreSettingsModel settings) {
    ChecklistConfig? titleChecklist;
    TitleConfig? titleConfig;
    if (user.title != null) {
      titleConfig = settings.titles
          .where((t) => t.name == user.title)
          .firstOrNull;
      titleConfig ??= settings.tags
          .where((t) => t.name == user.title)
          .firstOrNull;

      if (titleConfig != null &&
          titleConfig.linkChecklist &&
          titleConfig.linkedChecklistId != null) {
        titleChecklist = settings.checklists
            .where((c) => c.id == titleConfig!.linkedChecklistId)
            .firstOrNull;
      }
    }

    List<ChecklistConfig> allUserChecklists = [];
    if (titleChecklist != null) {
      allUserChecklists.add(titleChecklist);
    }

    final assignedIds = user.assignedChecklists ?? [];
    for (final cid in assignedIds) {
      final cl = settings.checklists.where((c) => c.id == cid).firstOrNull;
      if (cl != null && !allUserChecklists.any((c) => c.id == cl.id)) {
        allUserChecklists.add(cl);
      }
    }

    if (allUserChecklists.isEmpty) return const SizedBox.shrink();

    final completedChecklists =
        _initialUser?.completedChecklists ?? user.completedChecklists ?? [];
    final currentPosition = _positionController.text.isNotEmpty
        ? _positionController.text
        : user.position;
    final activeChecklists = allUserChecklists
        .where((c) =>
            c.tasksForPosition(currentPosition).isNotEmpty &&
            !completedChecklists.contains(c.id))
        .toList();
    if (activeChecklists.isEmpty) return const SizedBox.shrink();

    final completedTasks =
        _initialUser?.completedTasks ?? user.completedTasks ?? [];

    return Column(
      children: activeChecklists.map((userChecklist) {
        final color = AppTheme.getColorFromName(userChecklist.color);
        final applicableTasks = userChecklist.tasksForPosition(currentPosition);
        final completedInThis = applicableTasks.where((task) =>
            completedTasks.any((t) => t.toString().trim() == task.text.trim())
        ).length;
        final cleanChecklistName = userChecklist.name
            .replaceAll(
              RegExp(r'\bchecklist\b', caseSensitive: false),
              '',
            )
            .trim();
        final checklistHeading = cleanChecklistName.isNotEmpty
            ? '$cleanChecklistName Checklist'
            : userChecklist.name;

        return Column(
          children: [
            Card(
              color: Theme.of(context).cardColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: color.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.check_box_outlined,
                              color: color,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              checklistHeading,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).textTheme.titleLarge?.color,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '$completedInThis/${applicableTasks.length} Completed',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        int columns = 1;
                        if (constraints.maxWidth >= 900) {
                          columns = 3;
                        } else if (constraints.maxWidth >= 500) {
                          columns = 2;
                        }
                        const spacing = 16.0;
                        final itemWidth = columns == 1
                            ? constraints.maxWidth
                            : ((constraints.maxWidth - ((columns - 1) * spacing)) /
                                    columns)
                                .floorToDouble();

                        return Wrap(
                          spacing: spacing,
                          runSpacing: 4.0,
                          children: applicableTasks.map((taskItem) {
                            final task = taskItem.text;
                            final isCompleted = completedTasks.any(
                              (t) => t.toString().trim() == task.trim(),
                            );
                            return SizedBox(
                              width: itemWidth,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () async {
                                  List<String> newCompleted = completedTasks
                                      .map((e) => e.toString())
                                      .toList();
                                  if (!isCompleted) {
                                    if (!newCompleted.any(
                                      (t) =>
                                          t.toString().trim() ==
                                          task.trim(),
                                    )) {
                                      newCompleted.add(task);
                                    }
                                  } else {
                                    newCompleted.removeWhere(
                                      (t) =>
                                          t.toString().trim() ==
                                          task.trim(),
                                    );
                                  }

                                  UserModel updatedUser = _initialUser!.copyWith(
                                    completedTasks: newCompleted,
                                  );

                                  setState(() {
                                    _initialUser = updatedUser;
                                  });

                                  if (!mounted) return;

                                  final allApplicableDone = applicableTasks.every(
                                    (t) => newCompleted.any(
                                      (c) => c.trim() == t.text.trim(),
                                    ),
                                  );

                                  if (allApplicableDone) {
                                    final newLogs = _historyLogs
                                        .map((e) => Map<String, dynamic>.from(e))
                                        .toList();
                                    newLogs.add({
                                      'event':
                                          'Completed ${userChecklist.name} Checklist',
                                      'date': DateTime.now()
                                          .toIso8601String()
                                          .split('T')
                                          .first,
                                    });
                                    _historyLogs = newLogs;

                                    final newCompletedChecklists =
                                        List<String>.from(completedChecklists);
                                    if (!newCompletedChecklists.contains(
                                      userChecklist.id,
                                    )) {
                                      newCompletedChecklists.add(
                                        userChecklist.id,
                                      );
                                    }

                                    final fullyUpdatedUser =
                                        updatedUser.copyWith(
                                          historyLogs: newLogs,
                                        );
                                    setState(() {
                                      _initialUser = fullyUpdatedUser;
                                    });

                                    ref
                                        .read(firestoreServiceProvider)
                                        .updateUser(fullyUpdatedUser);

                                    if (titleConfig?.autoPromoteOnChecklist ==
                                        true) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        if (mounted) {
                                          _showPromoteDialog(
                                            settings,
                                            onDismiss: () async {
                                              if (mounted &&
                                                  _initialUser != null) {
                                                final afterDialogUser =
                                                    _initialUser!.copyWith(
                                                      completedTasks: [],
                                                      completedChecklists:
                                                          newCompletedChecklists,
                                                    );
                                                setState(() {
                                                  _initialUser =
                                                      afterDialogUser;
                                                });
                                                await ref
                                                    .read(
                                                      firestoreServiceProvider,
                                                    )
                                                    .updateUser(
                                                      afterDialogUser,
                                                    );
                                              }
                                            },
                                          );
                                        }
                                      });
                                    } else {
                                      Future.delayed(
                                        const Duration(seconds: 1),
                                        () async {
                                          if (mounted && _initialUser != null) {
                                            final afterDialogUser =
                                                _initialUser!.copyWith(
                                                  completedTasks: [],
                                                  completedChecklists:
                                                      newCompletedChecklists,
                                                );
                                            setState(() {
                                              _initialUser = afterDialogUser;
                                            });
                                            await ref
                                                .read(
                                                  firestoreServiceProvider,
                                                )
                                                .updateUser(afterDialogUser);
                                          }
                                        },
                                      );
                                    }
                                  } else {
                                    ref
                                        .read(firestoreServiceProvider)
                                        .updateUser(updatedUser);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8.0,
                                    horizontal: 8.0,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isCompleted
                                            ? Icons.check_box
                                            : Icons.check_box_outline_blank,
                                        color: isCompleted
                                            ? color
                                            : Theme.of(
                                                context,
                                              ).unselectedWidgetColor,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          task,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            decoration: isCompleted
                                                ? TextDecoration.lineThrough
                                                : null,
                                            color: isCompleted
                                                ? Colors.grey
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      }).toList(),
    );
  }

  void _showEmployeeDataSummary(
    BuildContext context,
    UserModel user,
    StoreSettingsModel settings,
  ) {
    if (settings.employeeDataSummaryFields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fields selected for summary in Settings.'),
        ),
      );
      return;
    }

    final Map<String, String> summaryData = {};
    for (final field in settings.employeeDataSummaryFields) {
      switch (field) {
        case 'First Name':
          summaryData[field] = user.firstName ?? 'N/A';
          break;
        case 'Last Name':
          summaryData[field] = user.lastName ?? 'N/A';
          break;
        case 'Preferred Name':
          summaryData[field] = user.preferredName ?? 'N/A';
          break;
        case 'Title':
          summaryData[field] = user.title ?? 'N/A';
          break;
        case 'Start Date':
          summaryData[field] =
              user.startDate?.toIso8601String().split('T').first ?? 'N/A';
          break;
        case 'End Date':
          summaryData[field] =
              user.endDate?.toIso8601String().split('T').first ?? 'N/A';
          break;
        case 'Store':
          summaryData[field] = user.store ?? 'N/A';
          break;
        case 'Position':
          summaryData[field] = user.position ?? 'N/A';
          break;
        case 'Designation':
          summaryData[field] = user.designation ?? 'N/A';
          break;
        case 'Additional Tags':
          summaryData[field] = user.additionalTags?.join(', ') ?? 'N/A';
          break;
        case 'Working Time':
          summaryData[field] = user.workingTime ?? 'N/A';
          break;
        case 'Avg Shifts / Wk':
          summaryData[field] = user.avgShifts ?? 'N/A';
          break;
        case 'Pay (\$ / Hr)':
          summaryData[field] = user.payRate?.toString() ?? 'N/A';
          break;
        case 'Food Permit Exp.':
          summaryData[field] =
              user.foodHandlersExpiration?.toIso8601String().split('T').first ??
              'N/A';
          break;
        case 'Manager Permit Exp.':
          summaryData[field] =
              user.managerPermitExpiration
                  ?.toIso8601String()
                  .split('T')
                  .first ??
              'N/A';
          break;
        case 'General Notes & Comments':
          summaryData[field] = user.generalNotes ?? 'N/A';
          break;
        case 'Hiring Notes':
          summaryData[field] = user.hiringNotes ?? 'N/A';
          break;
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            'Employee Data Summary',
            style: TextStyle(
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: summaryData.entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.key,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.value,
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showAddChecklistDialog(
    BuildContext context,
    UserModel user,
    StoreSettingsModel settings,
  ) {
    if (settings.checklists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No checklists available in this store.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            'Assign Checklist',
            style: TextStyle(
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          content: SizedBox(
            width: 300,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: settings.checklists.map((checklist) {
                  final isAlreadyAssigned =
                      (user.assignedChecklists ?? []).contains(checklist.id) ||
                      ((user.completedChecklists ?? []).contains(checklist.id));
                  return ListTile(
                    title: Text(
                      checklist.name,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    trailing: isAlreadyAssigned
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () async {
                      if (isAlreadyAssigned) {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: Theme.of(context).cardColor,
                            title: Text(
                              'Assign this checklist again?',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).textTheme.titleLarge?.color,
                              ),
                            ),
                            content: Text(
                              'This will clear the previous completion status for this checklist.',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Re-assign'),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                      }

                      Navigator.of(
                        context,
                      ).pop(); // Close main checklist dialog
                      setState(() => _isSaving = true);
                      try {
                        // Clear tasks belonging to this checklist from completedTasks
                        final currentCompletedTasks = List<String>.from(
                          user.completedTasks ?? [],
                        );
                        currentCompletedTasks.removeWhere(
                          (task) => checklist.items
                              .map((i) => i.toString().trim())
                              .contains(task.trim()),
                        );

                        // Remove from completed checklists
                        final currentCompletedChecklists = List<String>.from(
                          user.completedChecklists ?? [],
                        );
                        currentCompletedChecklists.remove(checklist.id);

                        // Add to assigned checklists if not present
                        final currentAssigned = List<String>.from(
                          user.assignedChecklists ?? [],
                        );
                        if (!currentAssigned.contains(checklist.id)) {
                          currentAssigned.add(checklist.id);
                        }

                        final updatedUser = user.copyWith(
                          assignedChecklists: currentAssigned,
                          completedChecklists: currentCompletedChecklists,
                          completedTasks: currentCompletedTasks,
                        );

                        setState(() {
                          _initialUser = updatedUser;
                        });

                        final firestoreService = ref.read(
                          firestoreServiceProvider,
                        );
                        await firestoreService.updateUser(updatedUser);

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Assigned ${checklist.name} to team member.',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted)
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      } finally {
                        if (mounted) setState(() => _isSaving = false);
                      }
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAvailabilityCard(BuildContext context, bool isScheduleEnabled) {
    return Card(
      color: Theme.of(context).cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_month,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Availability',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.titleLarge?.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!isScheduleEnabled)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 28,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Enable schedule for the store to see this tile.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (!(_initialUser?.email != null &&
                _initialUser!.email!.isNotEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Text(
                    'Must have an account created.',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ),
              )
            else
              ref
                  .watch(userAvailabilityProvider(widget.userId))
                  .when(
                    data: (availability) {
                      if (availability == null || availability.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: Center(
                            child: Text(
                              'No availability set.',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.color,
                              ),
                            ),
                          ),
                        );
                      }
                      final days = [
                        'monday',
                        'tuesday',
                        'wednesday',
                        'thursday',
                        'friday',
                        'saturday',
                        'sunday',
                      ];

                      String formatTime(String time24) {
                        try {
                          final parts = time24.split(':');
                          int h = int.parse(parts[0]);
                          final m = parts[1];
                          final suffix = h >= 12 ? 'PM' : 'AM';
                          if (h == 0) {
                            h = 12;
                          } else if (h > 12) {
                            h -= 12;
                          }
                          return '$h:$m $suffix';
                        } catch (_) {
                          return time24;
                        }
                      }

                      return Column(
                        children: days.map((day) {
                          final slots =
                              availability[day] as List<dynamic>? ?? [];

                          final dayName =
                              day.substring(0, 1).toUpperCase() +
                              day.substring(1);

                          String availabilityText = 'Unavailable';
                          if (slots.isNotEmpty) {
                            availabilityText = slots
                                .map(
                                  (s) =>
                                      '${formatTime(s['start'])} - ${formatTime(s['end'])}',
                                )
                                .join(', ');
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    dayName,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge?.color,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    availabilityText,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.color,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, st) => Center(
                      child: Text(
                        'Error loading availability',
                        style: TextStyle(color: AppTheme.primaryRed),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeOffCard(BuildContext context, bool isScheduleEnabled) {
    return Card(
      color: Theme.of(context).cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.flight_takeoff,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Time Off Requests',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.titleLarge?.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!isScheduleEnabled)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.flight_takeoff_outlined,
                        size: 28,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Enable schedule for the store to see this tile.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (!(_initialUser?.email != null &&
                _initialUser!.email!.isNotEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Text(
                    'Must have an account created.',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ),
              )
            else
              ref
                  .watch(userTimeOffRequestsProvider(widget.userId))
                  .when(
                    data: (requests) {
                      if (requests.isEmpty) {
                        return Center(
                          child: Text(
                            'No time off requests found.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                        );
                      }

                      final sortedRequests =
                          List<Map<String, dynamic>>.from(requests)..sort((
                            a,
                            b,
                          ) {
                            final aStatus = a['status'] as String? ?? '';
                            final bStatus = b['status'] as String? ?? '';
                            if (aStatus == 'pending' && bStatus != 'pending') {
                              return -1;
                            }
                            if (bStatus == 'pending' && aStatus != 'pending') {
                              return 1;
                            }
                            return 0;
                          });

                      return Column(
                        children: sortedRequests.asMap().entries.map((entry) {
                          final index = entry.key;
                          final req = entry.value;
                          final status = req['status'] as String? ?? 'unknown';

                          Color statusColor = AppTheme.green;
                          if (status == 'pending') {
                            statusColor = AppTheme.yellow;
                          }
                          if (status == 'denied') {
                            statusColor = AppTheme.primaryRed;
                          }

                          return Column(
                            children: [
                              if (index > 0) const Divider(),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${req['start_date']} to ${req['end_date']}',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  '${req['reason'] ?? 'No reason provided'}',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.color,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, st) => Center(
                      child: Text(
                        'Error loading time off',
                        style: TextStyle(color: AppTheme.primaryRed),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard(bool isTeamMemberAccountsEnabled) {
    final hasAccount =
        _initialUser?.email != null && _initialUser!.email!.isNotEmpty;

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person_pin,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Account Login',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.titleLarge?.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!isTeamMemberAccountsEnabled)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 28,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Enable schedule or shift board to create an account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (hasAccount) ...[
              Text(
                'Email: ${_initialUser!.email}',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: OutlinedButton(
                  onPressed: () async {
                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(
                        email: _initialUser!.email!,
                      );
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Email sent')),
                        );
                    } catch (e) {
                      if (context.mounted)
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  child: const Text('Send Password Reset Email'),
                ),
              ),
            ] else ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      ElevatedButton(
                        onPressed: _showCreateAccountDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Create Account'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          final baseUrl =
                              'https://project-attendance-app.web.app/auth';
                          final query = Uri(
                            queryParameters: {
                              if (_initialUser?.firstName != null &&
                                  _initialUser!.firstName!.isNotEmpty)
                                'firstName': _initialUser!.firstName,
                              if (_initialUser?.lastName != null &&
                                  _initialUser!.lastName!.isNotEmpty)
                                'lastName': _initialUser!.lastName,
                              if (_initialUser?.email != null &&
                                  _initialUser!.email!.isNotEmpty)
                                'email': _initialUser!.email,
                              'memberId': widget.userId,
                              if (_initialUser?.store != null)
                                'storeId': _initialUser!.store,
                            },
                          ).query;
                          final link = '$baseUrl?$query';
                          Clipboard.setData(ClipboardData(text: link));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Setup link copied to clipboard!'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.link),
                        label: const Text('Copy Setup Link'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryLogCard(BuildContext context) {
    return Card(
      color: Theme.of(context).cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'History Log',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.titleLarge?.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_historyLogs.isEmpty)
              Text(
                'No history logs yet.',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ..._historyLogs.reversed.map((log) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Icon(
                        Icons.circle,
                        size: 8,
                        color: AppTheme.lightBlue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            log['event'] ?? 'Event',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            log['date'] ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showCreateAccountDialog() {
    final emailController = TextEditingController();
    bool isCreating = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              title: Text(
                'Create Account',
                style: TextStyle(
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter an email address for ${_initialUser?.firstName ?? 'this team member'}.',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: emailController,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      labelStyle: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                if (!isCreating)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ElevatedButton(
                  onPressed: isCreating
                      ? null
                      : () async {
                          if (emailController.text.trim().isEmpty) return;
                          setDialogState(() => isCreating = true);

                          try {
                            // 1. Generate Temp Password and create Firebase Auth User
                            const chars =
                                'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
                            final rnd = Random();
                            final tempPassword = String.fromCharCodes(
                              Iterable.generate(
                                8,
                                (_) =>
                                    chars.codeUnitAt(rnd.nextInt(chars.length)),
                              ),
                            );

                            FirebaseApp
                            secondaryApp = await Firebase.initializeApp(
                              name:
                                  'Secondary_${DateTime.now().millisecondsSinceEpoch}',
                              options: DefaultFirebaseOptions.currentPlatform,
                            );
                            String uid = '';
                            try {
                              final userCredential =
                                  await FirebaseAuth.instanceFor(
                                    app: secondaryApp,
                                  ).createUserWithEmailAndPassword(
                                    email: emailController.text.trim(),
                                    password: tempPassword,
                                  );
                              uid = userCredential.user!.uid;
                            } finally {
                              await secondaryApp.delete();
                            }

                            // 2. Create Global User Document
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .set({
                                  'first_name': _initialUser?.firstName,
                                  'last_name': _initialUser?.lastName,
                                  'email': emailController.text.trim(),
                                  'password': tempPassword,
                                  'needs_password_reset': true,
                                  'role': 'team_member',
                                  'storeId': _initialUser?.store,
                                  'userId': widget.userId,
                                });

                            // 3. Update Team Member Document
                            if (_initialUser?.store != null) {
                              await FirebaseFirestore.instance
                                  .collection('stores')
                                  .doc(_initialUser!.store)
                                  .collection('users')
                                  .doc(widget.userId)
                                  .update({
                                    'email': emailController.text.trim(),
                                  });
                            }

                            if (mounted) {
                              setState(() {
                                _initialUser = _initialUser!.copyWith(
                                  email: emailController.text.trim(),
                                );
                              });
                              Navigator.of(context).pop();
                              _showAccountCreatedDialog(
                                emailController.text.trim(),
                                tempPassword,
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                              setDialogState(() => isCreating = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: isCreating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAccountCreatedDialog(String email, String tempPassword) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            'Account Created!',
            style: TextStyle(
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Please provide this information to the team member. They will be prompted to change their password upon their first login.',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Email: $email',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Temporary Password: $tempPassword',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

/// Opens the member's profile inside a modal dialog so the user doesn't lose their place.
Future<void> showMemberProfileDialog(BuildContext context, String userId) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 850),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: MemberDetailView(userId: userId),
        ),
      ),
    ),
  );
}
