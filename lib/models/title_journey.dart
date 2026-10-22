// The team member journey: how titles lead to each other (In Training →
// Team Member → Trainer / Leader → Director ...). Titles are circles on a
// grid; arrows say which titles someone can be promoted to next. A title can
// lead to several (a split) and several can lead to one.
//
// Firestore: /stores/{storeId}/settings/title_journey
//   nodes: { "<titleId>": { "x": 0, "y": 0 } }   // grid column / row
//   links: [ { "from": "<titleId>", "to": "<titleId>" } ]
//   icons: { "<titleId>": "<icon key>" }      // see journey_widgets.dart

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'store_settings_model.dart';

class JourneyCell {
  final int x;
  final int y;
  const JourneyCell(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      other is JourneyCell && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

class JourneyLink {
  final String from;
  final String to;
  const JourneyLink(this.from, this.to);

  @override
  bool operator ==(Object other) =>
      other is JourneyLink && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
}

class TitleJourney {
  /// Where each title sits (titles not here aren't on the journey).
  final Map<String, JourneyCell> nodes;
  final List<JourneyLink> links;

  /// Icon picked for each title (keys from kJourneyIcons); missing = a
  /// default guessed from the title's name.
  final Map<String, String> icons;

  /// True when this came from the store's saved journey (false = built from
  /// the title order because none was saved yet).
  final bool saved;

  const TitleJourney({
    this.nodes = const {},
    this.links = const [],
    this.icons = const {},
    this.saved = false,
  });

  /// A straight line through the titles in their current order.
  factory TitleJourney.fromTitleOrder(List<TitleConfig> titles) => TitleJourney(
    nodes: {
      for (var i = 0; i < titles.length; i++) titles[i].id: JourneyCell(i, 0),
    },
    links: [
      for (var i = 0; i + 1 < titles.length; i++)
        JourneyLink(titles[i].id, titles[i + 1].id),
    ],
  );

  factory TitleJourney.fromJson(Map<String, dynamic>? j) {
    final nodes = <String, JourneyCell>{};
    final raw = j?['nodes'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is Map) {
          final x = v['x'];
          final y = v['y'];
          if (x is num && y is num)
            nodes[k] = JourneyCell(x.toInt(), y.toInt());
        }
      });
    }
    final links = <JourneyLink>[];
    for (final l in (j?['links'] as List? ?? const [])) {
      if (l is Map && l['from'] is String && l['to'] is String) {
        final link = JourneyLink(l['from'] as String, l['to'] as String);
        if (!links.contains(link)) links.add(link);
      }
    }
    final icons = <String, String>{};
    final rawIcons = j?['icons'];
    if (rawIcons is Map) {
      rawIcons.forEach((k, v) {
        if (k is String && v is String) icons[k] = v;
      });
    }
    return TitleJourney(
      nodes: nodes,
      links: links,
      icons: icons,
      saved: j != null,
    );
  }

  Map<String, dynamic> toJson() => {
    'nodes': {
      for (final e in nodes.entries) e.key: {'x': e.value.x, 'y': e.value.y},
    },
    'links': [
      for (final l in links) {'from': l.from, 'to': l.to},
    ],
    'icons': icons,
  };

  TitleJourney copyWith({
    Map<String, JourneyCell>? nodes,
    List<JourneyLink>? links,
    Map<String, String>? icons,
  }) => TitleJourney(
    nodes: nodes ?? this.nodes,
    links: links ?? this.links,
    icons: icons ?? this.icons,
    saved: saved,
  );

  /// This journey with only titles that still exist (deleted titles and
  /// their arrows dropped).
  TitleJourney cleaned(Iterable<String> titleIds) {
    final ids = titleIds.toSet();
    return TitleJourney(
      nodes: {
        for (final e in nodes.entries)
          if (ids.contains(e.key)) e.key: e.value,
      },
      links: [
        for (final l in links)
          if (ids.contains(l.from) &&
              ids.contains(l.to) &&
              nodes.containsKey(l.from) &&
              nodes.containsKey(l.to))
            l,
      ],
      icons: icons,
      saved: saved,
    );
  }

  /// Titles someone in [titleId] can be promoted to, top to bottom.
  List<String> next(String titleId) {
    final out = [
      for (final l in links)
        if (l.from == titleId) l.to,
    ];
    out.sort((a, b) => (nodes[a]?.y ?? 0).compareTo(nodes[b]?.y ?? 0));
    return out;
  }

  List<String> previous(String titleId) => [
    for (final l in links)
      if (l.to == titleId) l.from,
  ];

  /// Every title reachable from [titleId] (not including it).
  Set<String> ahead(String titleId) {
    final seen = <String>{};
    final queue = [...next(titleId)];
    while (queue.isNotEmpty) {
      final t = queue.removeLast();
      if (seen.add(t)) queue.addAll(next(t));
    }
    seen.remove(titleId);
    return seen;
  }

  /// Every title that leads to [titleId] (not including it).
  Set<String> behind(String titleId) {
    final seen = <String>{};
    final queue = [...previous(titleId)];
    while (queue.isNotEmpty) {
      final t = queue.removeLast();
      if (seen.add(t)) queue.addAll(previous(t));
    }
    seen.remove(titleId);
    return seen;
  }

  /// Would an arrow from → to make a loop?
  bool wouldLoop(String from, String to) =>
      from == to || ahead(to).contains(from);

  /// Where new hires start: the left-most title with no arrows in (top first).
  String? get start {
    final starts = nodes.keys.where((id) => previous(id).isEmpty).toList()
      ..sort(_byCell);
    return starts.firstOrNull ??
        (nodes.keys.toList()..sort(_byCell)).firstOrNull;
  }

  int _byCell(String a, String b) {
    final ca = nodes[a]!;
    final cb = nodes[b]!;
    final x = ca.x.compareTo(cb.x);
    return x != 0 ? x : ca.y.compareTo(cb.y);
  }

  /// Titles in journey order: by column, then row; titles not on the
  /// journey go last in their old order.
  List<TitleConfig> orderTitles(List<TitleConfig> titles) {
    final on = titles.where((t) => nodes.containsKey(t.id)).toList()
      ..sort((a, b) => _byCell(a.id, b.id));
    final off = titles.where((t) => !nodes.containsKey(t.id)).toList();
    return [...on, ...off];
  }

  int get columns => nodes.values.fold(0, (a, c) => math.max(a, c.x + 1));
  int get rows => nodes.values.fold(0, (a, c) => math.max(a, c.y + 1));

  /// How many titles are on the longest path through the journey.
  int get longestPath {
    final memo = <String, int>{};
    int depth(String id) =>
        memo[id] ??= 1 + next(id).fold<int>(0, (m, n) => math.max(m, depth(n)));
    return nodes.keys.fold<int>(0, (m, id) => math.max(m, depth(id)));
  }

  /// Titles from the start to [id] along the arrows (shortest way), or just
  /// [id] when it can't be reached from the start.
  int stepOf(String id) {
    final s = start;
    if (s == null) return 1;
    final seen = <String, int>{s: 1};
    final queue = [s];
    while (queue.isNotEmpty) {
      final t = queue.removeAt(0);
      if (t == id) return seen[t]!;
      for (final n in next(t)) {
        if (!seen.containsKey(n)) {
          seen[n] = seen[t]! + 1;
          queue.add(n);
        }
      }
    }
    return (nodes[id]?.x ?? 0) + 1;
  }

  String? titleAt(JourneyCell cell) =>
      nodes.entries.where((e) => e.value == cell).firstOrNull?.key;
}

/// The journey for a store: saved one, or built from the title order.
TitleJourney journeyFor(TitleJourney? saved, List<TitleConfig> titles) {
  if (saved == null || !saved.saved) return TitleJourney.fromTitleOrder(titles);
  final j = saved.cleaned(titles.map((t) => t.id));
  // Nothing saved matches today's titles (e.g. they were all re-created).
  if (j.nodes.isEmpty && saved.nodes.isNotEmpty) {
    return TitleJourney.fromTitleOrder(titles).copyWith(icons: saved.icons);
  }
  return j;
}

DocumentReference<Map<String, dynamic>> _journeyDoc(String storeId) =>
    FirebaseFirestore.instance
        .collection('stores')
        .doc(storeId)
        .collection('settings')
        .doc('title_journey');

/// The store's saved journey (null while loading; `saved == false` when
/// none was saved yet).
final titleJourneyProvider = StreamProvider.family<TitleJourney, String>(
  (ref, storeId) => _journeyDoc(storeId).snapshots().map(
    (d) => d.exists ? TitleJourney.fromJson(d.data()) : const TitleJourney(),
  ),
);

Future<void> saveTitleJourney(String storeId, TitleJourney journey) =>
    _journeyDoc(
      storeId,
    ).set({...journey.toJson(), 'updated_at': FieldValue.serverTimestamp()});

/// The titles a promotion would usually go to from [current] (journey
/// arrows first; otherwise the next title in order).
List<String> promotionChoices(
  String? current,
  List<TitleConfig> titles,
  TitleJourney journey,
) {
  final byId = {for (final t in titles) t.id: t.name};
  final currentId = titles.where((t) => t.name == current).firstOrNull?.id;
  if (currentId != null) {
    final next = [
      for (final id in journey.next(currentId))
        if (byId[id] case final name?) name,
    ];
    if (next.isNotEmpty) return next;
    final i = titles.indexWhere((t) => t.id == currentId);
    if (i >= 0 && i + 1 < titles.length) return [titles[i + 1].name];
    return const [];
  }
  final start = journey.start;
  return [if (byId[start] case final name?) name];
}
