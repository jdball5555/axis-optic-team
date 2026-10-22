import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import 'store_intro.dart';

/// Dashboard tile for one store: its blueprint orbiting across the whole
/// tile, with the store's name and how many team members it has. It has no
/// background of its own, so it sits on the tile like the other tiles do.
/// Works on any dashboard (All Stores or another store's).
class StoreTeamTile extends ConsumerWidget {
  const StoreTeamTile({super.key, required this.storeId, required this.name});
  final String storeId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final count = ref.watch(storeMembersProvider(storeId)).valueOrNull?.length;
    final people = count == 1 ? 'team member' : 'team members';
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Blueprint(storeId: storeId),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: count == null ? '–' : '$count',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accent,
                          ),
                        ),
                        TextSpan(
                          text: '  $people',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loads a store's blueprint once (usually already loaded at app start).
class _Blueprint extends StatefulWidget {
  const _Blueprint({required this.storeId});
  final String storeId;

  @override
  State<_Blueprint> createState() => _BlueprintState();
}

class _BlueprintState extends State<_Blueprint> {
  StoreIntro? _intro;

  @override
  void initState() {
    super.initState();
    _intro = StoreIntros.cachedFor([widget.storeId]);
    if (_intro == null) {
      StoreIntros.load(widget.storeId).then((i) {
        if (mounted && i != null) setState(() => _intro = i);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final intro = _intro;
    return intro == null ? const SizedBox.expand() : StoreOrbit(intro: intro);
  }
}
