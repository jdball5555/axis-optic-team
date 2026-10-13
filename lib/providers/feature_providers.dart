import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_providers.dart';

class FeatureToggleNotifier extends Notifier<bool> {
  final bool isSchedule;

  FeatureToggleNotifier(this.isSchedule);

  @override
  bool build() {
    final settings = ref.watch(storeSettingsProvider).valueOrNull;
    if (settings == null) return false;
    return isSchedule ? settings.isScheduleEnabled : settings.isShiftBoardEnabled;
  }

  Future<void> toggle(bool value) async {
    state = value;
    final settings = ref.read(storeSettingsProvider).valueOrNull;
    if (settings != null) {
      final updatedSettings = isSchedule
          ? settings.copyWith(isScheduleEnabled: value)
          : settings.copyWith(isShiftBoardEnabled: value);
      await ref.read(firestoreServiceProvider).updateStoreSettings(updatedSettings);
    }
  }
}

final scheduleFeatureProvider = NotifierProvider<FeatureToggleNotifier, bool>(() => FeatureToggleNotifier(true));
final shiftFeatureProvider = NotifierProvider<FeatureToggleNotifier, bool>(() => FeatureToggleNotifier(false));
