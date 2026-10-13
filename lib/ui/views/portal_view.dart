import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

// =============================================================================
// DATA
// =============================================================================
//
// Portal links live at /stores/{storeId}/portal_links/{linkId}.
// A link shared by several stores is written to each of those stores using the
// SAME document id, so the copies can be found, edited and deleted together.

CollectionReference<Map<String, dynamic>> _portalLinksFor(String storeId) =>
    FirebaseFirestore.instance
        .collection('stores')
        .doc(storeId)
        .collection('portal_links');

class PortalLink {
  final String id;
  final String title;
  final String url;
  final String description;
  final String group;

  /// Stores (among the ones currently being viewed) that contain this link.
  final Set<String> storeIds;

  const PortalLink({
    required this.id,
    required this.title,
    required this.url,
    required this.description,
    required this.group,
    required this.storeIds,
  });

  factory PortalLink.fromData(
    String id,
    Map<String, dynamic> data,
    String storeId,
  ) {
    final group = (data['group'] as String?)?.trim() ?? '';
    return PortalLink(
      id: id,
      title: (data['title'] as String?)?.trim().isNotEmpty == true
          ? (data['title'] as String).trim()
          : 'Untitled link',
      url: data['url'] as String? ?? '',
      description: data['description'] as String? ?? '',
      group: group.isEmpty ? 'General' : group,
      storeIds: {storeId},
    );
  }

  PortalLink withStore(String storeId) => PortalLink(
    id: id,
    title: title,
    url: url,
    description: description,
    group: group,
    storeIds: {...storeIds, storeId},
  );
}

Stream<List<PortalLink>> _streamLinksForStores(List<String> storeIds) {
  if (storeIds.isEmpty) return Stream.value(const []);
  final streams = storeIds.map(
    (sid) => _portalLinksFor(sid).snapshots().map(
      (snap) => snap.docs
          .map((d) => PortalLink.fromData(d.id, d.data(), sid))
          .toList(),
    ),
  );
  return Rx.combineLatestList(streams).map((perStore) {
    final merged = <String, PortalLink>{};
    for (final list in perStore) {
      for (final link in list) {
        final existing = merged[link.id];
        merged[link.id] = existing == null
            ? link
            : existing.withStore(link.storeIds.first);
      }
    }
    return merged.values.toList();
  });
}

/// Links for the current store, or for every store when "All Stores" is active.
final portalLinksProvider = StreamProvider<List<PortalLink>>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId != null) return _streamLinksForStores([storeId]);
  return FirebaseFirestore.instance
      .collection('stores')
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toList())
      .distinct((a, b) => a.join(',') == b.join(','))
      .switchMap(_streamLinksForStores);
});

/// Finds which stores actually contain a link with this id.
Future<Set<String>> _findStoresWithLink(
  String linkId,
  Iterable<String> storeIds,
) async {
  final results = await Future.wait(
    storeIds.map((sid) async {
      final doc = await _portalLinksFor(sid).doc(linkId).get();
      return doc.exists ? sid : null;
    }),
  );
  return results.whereType<String>().toSet();
}

class _StoreInfo {
  final String id;
  final String name;
  const _StoreInfo(this.id, this.name);
}

List<_StoreInfo> _storeInfos(List<Map<String, dynamic>> stores) {
  final list = stores
      .map(
        (s) => _StoreInfo(
          s['id'] as String,
          (s['name'] as String?)?.trim().isNotEmpty == true
              ? s['name'] as String
              : 'Untitled Store',
        ),
      )
      .toList();
  list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
}

String _friendlyError(Object e) {
  if (e is FirebaseException) {
    if (e.code == 'permission-denied') {
      return 'You don\'t have permission to change portal links for one of '
          'these stores. Check your Firestore rules for '
          'stores/{storeId}/portal_links.';
    }
    return e.message ?? e.code;
  }
  return e.toString();
}

// =============================================================================
// PAGE
// =============================================================================

class PortalView extends ConsumerWidget {
  const PortalView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeId = ref.watch(currentStoreIdProvider);
    final stores = _storeInfos(
      ref.watch(allStoresStreamProvider).valueOrNull ?? const [],
    );
    final storeNames = {for (final s in stores) s.id: s.name};
    final linksAsync = ref.watch(portalLinksProvider);
    final isAllStores = storeId == null;

    final links = linksAsync.valueOrNull ?? const <PortalLink>[];
    final groups = <String, List<PortalLink>>{};
    for (final link in links) {
      groups.putIfAbsent(link.group, () => []).add(link);
    }
    final sortedGroups = groups.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final g in groups.values) {
      g.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }

    final subtitle = isAllStores
        ? 'Showing links from all stores'
        : 'Showing links for ${storeNames[storeId] ?? 'this store'}';

    void openEditor({PortalLink? link}) => showDialog<void>(
      context: context,
      builder: (_) => _PortalLinkDialog(
        link: link,
        existingGroups: sortedGroups,
        stores: stores,
        currentStoreId: storeId,
      ),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.link, color: AppTheme.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Portal',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.titleLarge?.color,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: stores.isEmpty ? null : () => openEditor(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add link'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Expanded(
              child: linksAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Could not load portal links: ${_friendlyError(e)}'),
                ),
                data: (_) => links.isEmpty
                    ? const _PortalEmptyState()
                    : ListView.separated(
                        itemCount: sortedGroups.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 24),
                        itemBuilder: (context, index) {
                          final group = sortedGroups[index];
                          return _PortalGroup(
                            title: group,
                            links: groups[group]!,
                            storeNames: storeNames,
                            showStoreTags: isAllStores && stores.length > 1,
                            onEdit: (link) => openEditor(link: link),
                            onDelete: (link) => _confirmDelete(
                              context,
                              link: link,
                              stores: stores,
                              currentStoreId: storeId,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalEmptyState extends StatelessWidget {
  const _PortalEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bookmark_outline,
            size: 52,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
          const SizedBox(height: 16),
          Text(
            'No portal links yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Use "Add link" to add training, ordering, or other resources.',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalGroup extends StatelessWidget {
  final String title;
  final List<PortalLink> links;
  final Map<String, String> storeNames;
  final bool showStoreTags;
  final ValueChanged<PortalLink> onEdit;
  final ValueChanged<PortalLink> onDelete;

  const _PortalGroup({
    required this.title,
    required this.links,
    required this.storeNames,
    required this.showStoreTags,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: Theme.of(context).textTheme.bodySmall?.color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: links
              .map(
                (link) => _PortalLinkCard(
                  link: link,
                  storeNames: storeNames,
                  showStoreTags: showStoreTags,
                  onEdit: () => onEdit(link),
                  onDelete: () => onDelete(link),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _PortalLinkCard extends StatelessWidget {
  final PortalLink link;
  final Map<String, String> storeNames;
  final bool showStoreTags;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PortalLinkCard({
    required this.link,
    required this.storeNames,
    required this.showStoreTags,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inAllStores =
        storeNames.isNotEmpty && storeNames.keys.every(link.storeIds.contains);
    final tagLabels = inAllStores
        ? const ['All stores']
        : (link.storeIds.map((id) => storeNames[id] ?? 'Unknown store').toList()
            ..sort());

    return SizedBox(
      width: 310,
      child: Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openLink(context, link.url),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.open_in_new,
                      color: AppTheme.accent,
                      size: 19,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        link.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    PopupMenuButton<String>(
                      iconSize: 18,
                      color: theme.cardColor,
                      onSelected: (value) {
                        if (value == 'edit') onEdit();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ],
                ),
                if (link.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    link.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.textTheme.bodySmall?.color),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  link.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 12,
                  ),
                ),
                if (showStoreTags) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: tagLabels
                        .map(
                          (label) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: theme.dividerColor.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.store_outlined,
                                  size: 12,
                                  color: theme.textTheme.bodySmall?.color,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openLink(BuildContext context, String rawUrl) async {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This portal link has an invalid URL.')),
    );
    return;
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open this portal link.')),
    );
  }
}

// =============================================================================
// DELETE
// =============================================================================

Future<void> _confirmDelete(
  BuildContext context, {
  required PortalLink link,
  required List<_StoreInfo> stores,
  required String? currentStoreId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  Set<String> foundIn;
  try {
    foundIn = await _findStoresWithLink(link.id, stores.map((s) => s.id));
  } catch (_) {
    foundIn = link.storeIds;
  }
  if (foundIn.isEmpty) foundIn = link.storeIds;
  if (!context.mounted) return;

  final storeName = {for (final s in stores) s.id: s.name};
  final canRemoveFromCurrentOnly =
      currentStoreId != null &&
      foundIn.contains(currentStoreId) &&
      foundIn.length > 1;

  // 'current' = remove from this store only, 'all' = remove everywhere.
  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      title: const Text('Delete portal link?'),
      content: Text(
        foundIn.length > 1
            ? '"${link.title}" is shared with ${foundIn.length} stores '
                  '(${(foundIn.map((id) => storeName[id] ?? id).toList()..sort()).join(', ')}).'
            : 'Remove "${link.title}" from the portal?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        if (canRemoveFromCurrentOnly)
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop('current'),
            child: Text(
              'Remove from ${storeName[currentStoreId] ?? 'this store'} only',
            ),
          ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop('all'),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: Text(foundIn.length > 1 ? 'Delete from all stores' : 'Delete'),
        ),
      ],
    ),
  );
  if (choice == null) return;

  final targets = choice == 'current' ? {currentStoreId!} : foundIn;
  try {
    final batch = FirebaseFirestore.instance.batch();
    for (final sid in targets) {
      batch.delete(_portalLinksFor(sid).doc(link.id));
    }
    await batch.commit();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(_friendlyError(e))));
  }
}

// =============================================================================
// ADD / EDIT DIALOG
// =============================================================================

class _PortalLinkDialog extends StatefulWidget {
  final PortalLink? link;
  final List<String> existingGroups;
  final List<_StoreInfo> stores;
  final String? currentStoreId;

  const _PortalLinkDialog({
    required this.existingGroups,
    required this.stores,
    required this.currentStoreId,
    this.link,
  });

  @override
  State<_PortalLinkDialog> createState() => _PortalLinkDialogState();
}

class _PortalLinkDialogState extends State<_PortalLinkDialog> {
  static const _newGroupValue = '__new_group__';

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _urlController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _newGroupController;
  late final List<String> _groupOptions;
  late String _selectedGroup;

  /// Stores the link is saved in right now (empty for a new link).
  Set<String> _originalStores = {};

  /// Stores the user wants the link to be in.
  late Set<String> _selectedStores;
  bool _loadingStores = false;

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.link != null;
  List<String> get _allStoreIds => widget.stores.map((s) => s.id).toList();

  @override
  void initState() {
    super.initState();
    final link = widget.link;
    _titleController = TextEditingController(text: link?.title);
    _urlController = TextEditingController(text: link?.url);
    _descriptionController = TextEditingController(text: link?.description);
    _newGroupController = TextEditingController();

    _groupOptions = {
      'General',
      ...widget.existingGroups,
      if (link != null) link.group,
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _selectedGroup = link?.group ?? 'General';

    if (link != null) {
      _originalStores = {...link.storeIds};
      _selectedStores = {...link.storeIds};
      _loadExistingStores(link.id);
    } else if (widget.currentStoreId != null) {
      _selectedStores = {widget.currentStoreId!};
    } else {
      _selectedStores = _allStoreIds.toSet();
    }
  }

  /// When viewing a single store we only know about that store's copy, so look
  /// up which other stores share this link.
  Future<void> _loadExistingStores(String linkId) async {
    setState(() => _loadingStores = true);
    try {
      final found = await _findStoresWithLink(linkId, _allStoreIds);
      if (!mounted) return;
      if (found.isNotEmpty) {
        setState(() {
          _originalStores = found;
          _selectedStores = {...found};
        });
      }
    } catch (_) {
      // Fall back to what we already know.
    } finally {
      if (mounted) setState(() => _loadingStores = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    _newGroupController.dispose();
    super.dispose();
  }

  /// Adds https:// when the user types something like "example.com".
  String _normalizeUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.contains('://')) return value;
    return 'https://$value';
  }

  String? _validateUrl(String? raw) {
    final value = _normalizeUrl(raw ?? '');
    if (value.isEmpty) return 'Enter a link.';
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        !uri.host.contains('.')) {
      return 'Enter a valid web address, e.g. example.com';
    }
    return null;
  }

  Future<void> _save() async {
    final formOk = _formKey.currentState!.validate();
    if (_selectedStores.isEmpty) {
      setState(() => _error = 'Choose at least one store for this link.');
      return;
    }
    if (!formOk) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final group = _selectedGroup == _newGroupValue
        ? _newGroupController.text.trim()
        : _selectedGroup;

    final linkData = <String, dynamic>{
      'title': _titleController.text.trim(),
      'group': group,
      'url': _normalizeUrl(_urlController.text),
      'description': _descriptionController.text.trim(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    // Same id in every store so the copies stay linked.
    final linkId =
        widget.link?.id ??
        FirebaseFirestore.instance.collection('stores').doc().id;

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final sid in _selectedStores) {
        final isNewInStore = !_originalStores.contains(sid);
        batch.set(_portalLinksFor(sid).doc(linkId), {
          ...linkData,
          if (isNewInStore) 'created_at': FieldValue.serverTimestamp(),
          if (isNewInStore) 'visible_to': ['All'],
        }, SetOptions(merge: true));
      }
      for (final sid in _originalStores.difference(_selectedStores)) {
        batch.delete(_portalLinksFor(sid).doc(linkId));
      }
      await batch.commit();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(e);
      });
    }
  }

  Widget _storeLabel(ThemeData theme, String text) => Row(
    children: [
      Icon(
        Icons.store_outlined,
        size: 18,
        color: theme.textTheme.bodySmall?.color,
      ),
      const SizedBox(width: 8),
      Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: theme.textTheme.bodyLarge?.color,
        ),
      ),
    ],
  );

  /// Viewing a single store: the link always belongs to that store.
  Widget _buildFixedStore(ThemeData theme) {
    final name = widget.stores
            .where((s) => s.id == widget.currentStoreId)
            .firstOrNull
            ?.name ??
        'This store';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.dividerColor),
      ),
      child: _storeLabel(theme, 'Store: $name'),
    );
  }

  void _toggleStore(String id) {
    setState(() {
      _error = null;
      if (!_selectedStores.remove(id)) _selectedStores.add(id);
    });
  }

  void _toggleAllStores() {
    setState(() {
      _error = null;
      final allSelected = _allStoreIds.every(_selectedStores.contains);
      _selectedStores = allSelected ? <String>{} : _allStoreIds.toSet();
    });
  }

  /// Viewing All Stores: pick which stores get the link.
  Widget _buildStorePicker(ThemeData theme) {
    final allSelected = _allStoreIds.every(_selectedStores.contains);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _storeLabel(theme, 'Show in stores'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StoreToggle(
              label: 'All stores',
              selected: allSelected,
              enabled: !_saving,
              onTap: _toggleAllStores,
            ),
            for (final store in widget.stores)
              _StoreToggle(
                label: store.name,
                selected: _selectedStores.contains(store.id),
                enabled: !_saving,
                onTap: () => _toggleStore(store.id),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    InputDecoration field(String label, {String? hint, IconData? icon}) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: icon == null ? null : Icon(icon, size: 20),
          border: const OutlineInputBorder(),
        );

    return AlertDialog(
      backgroundColor: theme.cardColor,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _isEditing ? Icons.edit_outlined : Icons.add_link,
              color: AppTheme.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _isEditing ? 'Edit portal link' : 'Add portal link',
            style: TextStyle(color: theme.textTheme.titleLarge?.color),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                TextFormField(
                  controller: _titleController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: field(
                    'Title',
                    hint: 'e.g. Supply ordering',
                    icon: Icons.title,
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a title.' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: field('Link', hint: 'https://…', icon: Icons.link),
                  validator: _validateUrl,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: field(
                    'Description (optional)',
                    hint: 'What is this link for?',
                  ).copyWith(alignLabelWithHint: true),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedGroup,
                  dropdownColor: theme.cardColor,
                  decoration: field('Group', icon: Icons.folder_outlined),
                  items: [
                    for (final g in _groupOptions)
                      DropdownMenuItem(value: g, child: Text(g)),
                    DropdownMenuItem(
                      value: _newGroupValue,
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 18, color: AppTheme.accent),
                          SizedBox(width: 6),
                          Text(
                            'New group…',
                            style: TextStyle(color: AppTheme.accent),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _selectedGroup = v ?? 'General'),
                ),
                if (_selectedGroup == _newGroupValue) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _newGroupController,
                    autofocus: true,
                    decoration: field(
                      'New group name',
                      hint: 'e.g. Training',
                      icon: Icons.create_new_folder_outlined,
                    ),
                    validator: (v) => (v?.trim() ?? '').isEmpty
                        ? 'Enter a group name.'
                        : null,
                  ),
                ],
                if (widget.currentStoreId != null) ...[
                  const SizedBox(height: 16),
                  _buildFixedStore(theme),
                ] else if (widget.stores.length > 1) ...[
                  const SizedBox(height: 20),
                  _buildStorePicker(theme),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || _loadingStores ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_isEditing ? 'Save changes' : 'Add link'),
        ),
      ],
    );
  }
}

/// Lightweight selectable pill — no ripple, quick color change.
class _StoreToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _StoreToggle({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.accent : theme.dividerColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 16,
                color: selected
                    ? AppTheme.accent
                    : theme.textTheme.bodySmall?.color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected
                      ? AppTheme.accent
                      : theme.textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
