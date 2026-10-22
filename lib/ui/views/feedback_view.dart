import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

/// Feedback tickets live under the person who sent them:
/// /users/{userId}/feedback/{ticketId}
///   type: "Bug" | "Improvement", message, submitted_by, store_id, timestamp
///   submitter_name, submitter_email, store_name
///   status: "Open" | "Closed" (a developer closed it) | "Resolved" (you agreed)
///   replies: [ { from: "developer" | "user", name, text, at } ]
/// Developers answer them in the Optic app. New tickets, replies and reopens
/// also queue a push to the developers in /notifications.
CollectionReference<Map<String, dynamic>> _ticketsFor(String userId) =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('feedback');

// The app's own red and teal (they follow the Bright colors setting).
Color get _bugColor => AppTheme.red;
Color get _ideaColor => AppTheme.teal;

/// Readable text / icons on a solid [c] fill.
Color _onSolid(Color c) =>
    ThemeData.estimateBrightnessForColor(c) == Brightness.dark
    ? Colors.white
    : Colors.black87;

const _feedbackEmail = 'contact@axisoptic.com';

/// Lets the developers' phones know (sent by the Cloud Function).
Future<void> _notifyDevelopers({
  required String ticketPath,
  required bool bug,
  required String title,
  required String body,
  String app = 'Axis Team',
  String location = '',
}) async {
  try {
    await FirebaseFirestore.instance.collection('notifications').add({
      'type': 'feedback',
      'ticket_type': bug ? 'Bug' : 'Improvement',
      'ticket_path': ticketPath,
      'app': app,
      'location': location,
      'title': title,
      'body': body.length > 140 ? '${body.substring(0, 140)}…' : body,
      'send_at': Timestamp.now(),
      'status': 'scheduled',
      'created_at': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    debugPrint('Developer notification not queued: $e');
  }
}

class FeedbackView extends ConsumerStatefulWidget {
  const FeedbackView({super.key});

  @override
  ConsumerState<FeedbackView> createState() => _FeedbackViewState();
}

class _FeedbackViewState extends ConsumerState<FeedbackView> {
  final _messageController = TextEditingController();
  final _locationController = TextEditingController();
  String _type = 'Improvement';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  String _myName() {
    final u = ref.read(currentUserProvider) ?? const {};
    final name = [
      u['first_name'],
      u['last_name'],
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
    return name.isEmpty ? (u['email'] as String? ?? 'Someone') : name;
  }

  Future<void> _submitFeedback() async {
    final message = _messageController.text.trim();
    final location = _locationController.text.trim();
    final user = ref.read(currentUserProvider);
    final userId = user?['id'] as String?;
    if (message.isEmpty || userId == null) return;
    final storeId = ref.read(currentStoreIdProvider);
    final stores = ref.read(allStoresStreamProvider).valueOrNull ?? const [];
    final storeName =
        stores.where((s) => s['id'] == storeId).firstOrNull?['name'] as String?;
    final bug = _type == 'Bug';

    setState(() => _isSubmitting = true);
    try {
      final doc = await _ticketsFor(userId).add({
        'type': _type,
        'app': 'Axis Team',
        'location': location,
        'message': message,
        'submitted_by': userId,
        'submitter_name': _myName(),
        'submitter_email': user?['email'],
        'store_id': storeId ?? 'all',
        'store_name': ?storeName,
        'status': 'Open',
        'replies': [],
        'timestamp': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      await _notifyDevelopers(
        ticketPath: doc.path,
        bug: bug,
        app: 'Axis Team',
        location: location,
        title: bug
            ? '🔴 Bug from ${_myName()}'
            : '🔵 Improvement from ${_myName()}',
        body: location.isNotEmpty ? '[$location] $message' : message,
      );
      _messageController.clear();
      _locationController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feedback sent. Thank you!')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t send your feedback. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Opens an email to the developer with whatever's been typed so far.
  Future<void> _emailFeedback() async {
    final location = _locationController.text.trim();
    final message = _messageController.text.trim();
    final body = [
      if (location.isNotEmpty) 'Where: $location',
      if (message.isNotEmpty) message,
    ].join('\n\n');
    final uri = Uri(
      scheme: 'mailto',
      path: _feedbackEmail,
      query: _mailQuery({
        'subject':
            'Axis Team ${_type == 'Bug' ? 'bug' : 'idea'} from ${_myName()}',
        if (body.isNotEmpty) 'body': body,
      }),
    );
    final opened = await launchUrl(uri);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t open email. Write to $_feedbackEmail'),
        ),
      );
    }
  }

  /// mailto query with spaces as %20 (Uri's queryParameters uses "+").
  static String _mailQuery(Map<String, String> params) => params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userId = ref.watch(currentUserProvider)?['id'] as String?;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Feedback',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.titleLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Report a bug or share an idea. A developer reads every ticket and replies here, or you can email $_feedbackEmail.',
                    style: TextStyle(color: theme.textTheme.bodySmall?.color),
                  ),
                  const SizedBox(height: 24),
                  _buildComposer(theme),
                  const SizedBox(height: 32),
                  if (userId == null)
                    const _NoTickets()
                  else
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _ticketsFor(userId).snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const _NoTickets(
                            message:
                                'Your tickets couldn\'t be loaded right now.',
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        DateTime when(
                          QueryDocumentSnapshot<Map<String, dynamic>> d,
                        ) =>
                            ((d.data()['updated_at'] ?? d.data()['timestamp'])
                                    as Timestamp?)
                                ?.toDate() ??
                            DateTime(2100);
                        final all = snapshot.data!.docs.toList()
                          ..sort((a, b) => when(b).compareTo(when(a)));
                        String status(
                          QueryDocumentSnapshot<Map<String, dynamic>> d,
                        ) => d.data()['status'] as String? ?? 'Open';
                        DateTime whenCreated(
                          QueryDocumentSnapshot<Map<String, dynamic>> d,
                        ) =>
                            ((d.data()['timestamp'] ?? d.data()['updated_at'])
                                    as Timestamp?)
                                ?.toDate() ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        int compareOpen(
                          QueryDocumentSnapshot<Map<String, dynamic>> a,
                          QueryDocumentSnapshot<Map<String, dynamic>> b,
                        ) {
                          final aBug =
                              (a.data()['type'] as String? ?? '') == 'Bug';
                          final bBug =
                              (b.data()['type'] as String? ?? '') == 'Bug';
                          if (aBug != bBug) return aBug ? -1 : 1;
                          final cmp = whenCreated(a).compareTo(whenCreated(b));
                          if (cmp != 0) return cmp;
                          return a.id.compareTo(b.id);
                        }

                        final closed = all
                            .where((d) => status(d) == 'Closed')
                            .toList();
                        final open =
                            all.where((d) => status(d) == 'Open').toList()
                              ..sort(compareOpen);
                        final done = all
                            .where((d) => status(d) == 'Resolved')
                            .toList();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (closed.isNotEmpty) ...[
                              _SectionTitle(
                                'Closed by a developer · please check',
                                theme,
                              ),
                              for (final t in closed)
                                _FeedbackTicket(ticket: t, myName: _myName()),
                              const SizedBox(height: 20),
                            ],
                            _SectionTitle('My open tickets', theme),
                            if (open.isEmpty) const _NoTickets(),
                            for (final t in open)
                              _FeedbackTicket(ticket: t, myName: _myName()),
                            if (done.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _SectionTitle('Done', theme),
                              for (final t in done.take(10))
                                _FeedbackTicket(ticket: t, myName: _myName()),
                            ],
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(ThemeData theme) {
    final isBug = _type == 'Bug';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What would you like to share?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TypeOption(
                  icon: Icons.lightbulb_outline,
                  label: 'Improvement',
                  subtitle: 'An idea or something to make better',
                  color: _ideaColor,
                  selected: !isBug,
                  onTap: () => setState(() => _type = 'Improvement'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TypeOption(
                  icon: Icons.bug_report_outlined,
                  label: 'Bug',
                  subtitle: 'Something isn\'t working right',
                  color: _bugColor,
                  selected: isBug,
                  onTap: () => setState(() => _type = 'Bug'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Where on the website is this located?',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final loc in const [
                'Schedule',
                'Shift Board',
                'Time Clock',
                'Team Members',
                'Rosters',
                'Dashboard',
                'Portal',
                'Settings',
                'Entire Site',
              ])
                ChoiceChip(
                  label: Text(loc),
                  selected: _locationController.text == loc,
                  selectedColor: AppTheme.tint(AppTheme.teal),
                  checkmarkColor: AppTheme.onTint(AppTheme.teal),
                  side: BorderSide(
                    color: _locationController.text == loc
                        ? AppTheme.edge(AppTheme.teal)
                        : theme.dividerColor,
                  ),
                  onSelected: (selected) {
                    setState(() {
                      _locationController.text = selected ? loc : '';
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _locationController,
            decoration: InputDecoration(
              labelText: 'Where on the website is this? (page or feature)',
              hintText: 'e.g. Schedule, Shift Board, Rosters, Settings…',
              prefixIcon: const Icon(Icons.place_outlined, size: 20),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _messageController,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: isBug
                  ? 'What happened? Include what you were doing and what you expected.'
                  : 'Tell us what would make Axis Team better for you.',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _emailFeedback,
                icon: const Icon(Icons.mail_outline, size: 18),
                label: const Text('Email instead'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.textTheme.bodyLarge?.color,
                  side: BorderSide(color: theme.dividerColor),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _submitFeedback,
                icon: _isSubmitting
                    ? SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _onSolid(isBug ? _bugColor : _ideaColor),
                        ),
                      )
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(_isSubmitting ? 'Sending…' : 'Send feedback'),
                style: FilledButton.styleFrom(
                  backgroundColor: isBug ? _bugColor : _ideaColor,
                  foregroundColor: _onSolid(isBug ? _bugColor : _ideaColor),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.theme);
  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: theme.textTheme.titleLarge?.color,
      ),
    ),
  );
}

/// One of the two "what kind of feedback" choices.
class _TypeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TypeOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.tint(color)
                : theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.edge(color) : theme.dividerColor,
              width: selected ? AppTheme.edgeWidth : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.tint(color),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: AppTheme.onTint(color)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle,
                  size: 18,
                  color: AppTheme.onTint(color),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoTickets extends StatelessWidget {
  final String message;
  const _NoTickets({this.message = 'There are no open tickets.'});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(Icons.inbox_outlined, color: theme.textTheme.bodySmall?.color),
          const SizedBox(width: 12),
          Text(
            message,
            style: TextStyle(color: theme.textTheme.bodySmall?.color),
          ),
        ],
      ),
    );
  }
}

/// A ticket with the conversation, and (once a developer closes it) the
/// choice to agree or reopen.
class _FeedbackTicket extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> ticket;
  final String myName;
  const _FeedbackTicket({required this.ticket, required this.myName});

  @override
  State<_FeedbackTicket> createState() => _FeedbackTicketState();
}

class _FeedbackTicketState extends State<_FeedbackTicket> {
  final _reply = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Map<String, dynamic> _userReply(String text) => {
    'from': 'user',
    'name': widget.myName,
    'text': text,
    'at': Timestamp.now(),
  };

  Future<void> _save(
    Map<String, dynamic> changes,
    String done, {
    String? notifyTitle,
    String? notifyBody,
  }) async {
    setState(() => _busy = true);
    try {
      await widget.ticket.reference.update({
        ...changes,
        'updated_at': FieldValue.serverTimestamp(),
      });
      if (notifyTitle != null) {
        final d = widget.ticket.data();
        await _notifyDevelopers(
          ticketPath: widget.ticket.reference.path,
          bug: d['type'] == 'Bug',
          app: d['app'] as String? ?? 'Axis Team',
          location: (d['location'] as String? ?? '').trim(),
          title: notifyTitle,
          body: notifyBody ?? '',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t save that. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sendReply() {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    _reply.clear();
    _save(
      {
        'replies': FieldValue.arrayUnion([_userReply(text)]),
        'last_reply_from': 'user',
      },
      'Reply sent.',
      notifyTitle: '💬 ${widget.myName} replied',
      notifyBody: text,
    );
  }

  Future<void> _reopen() async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reopen this ticket?'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: note,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'What still isn\'t right?',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final text = note.text.trim();
    await _save(
      {
        'status': 'Open',
        'reopened_count': FieldValue.increment(1),
        'last_reply_from': 'user',
        if (text.isNotEmpty)
          'replies': FieldValue.arrayUnion([_userReply(text)]),
      },
      'Ticket reopened. The developer will take another look.',
      notifyTitle: '↩️ ${widget.myName} reopened a ticket',
      notifyBody: text.isEmpty
          ? (widget.ticket.data()['message'] as String? ?? '')
          : text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final data = widget.ticket.data();
    final isBug = data['type'] == 'Bug';
    final color = isBug ? _bugColor : _ideaColor;
    final status = data['status'] as String? ?? 'Open';
    final time = (data['timestamp'] as Timestamp?)?.toDate();
    final submittedOn = time == null
        ? 'Sending…'
        : '${time.month}/${time.day}/${time.year}';
    final replies = [
      for (final r in (data['replies'] as List? ?? const []))
        if (r is Map) r,
    ];
    final reopened = ((data['reopened_count'] as num?) ?? 0) > 0;
    final (statusLabel, statusColor) = switch (status) {
      'Closed' => ('Closed by developer', AppTheme.green),
      'Resolved' => ('Done', AppTheme.green),
      _ => (reopened ? 'Reopened' : 'Open', color),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: status == 'Closed' ? AppTheme.green : theme.dividerColor,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isBug
                              ? Icons.bug_report_outlined
                              : Icons.lightbulb_outline,
                          size: 18,
                          color: color,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          data['type'] as String? ?? 'Feedback',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusPill(label: statusLabel, color: statusColor),
                        if (((data['location'] as String?) ?? '')
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _StatusPill(
                            label: (data['location'] as String).trim(),
                            color:
                                theme.textTheme.bodyMedium?.color?.withValues(
                                  alpha: 0.7,
                                ) ??
                                Colors.white70,
                          ),
                        ],
                        const Spacer(),
                        Text(
                          submittedOn,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      data['message'] as String? ?? '',
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        height: 1.4,
                      ),
                    ),
                    if (replies.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final r in replies) _ReplyLine(reply: r),
                    ],

                    // Closed by a developer: agree or reopen.
                    if (status == 'Closed') ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.tint(AppTheme.green),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.verified_outlined,
                              color: AppTheme.onTint(AppTheme.green),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'A developer closed this ticket. Is it taken care of?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _save({
                                    'status': 'Resolved',
                                    'resolved_at': FieldValue.serverTimestamp(),
                                  }, 'Thanks! Marked as done.'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.green,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Yes, it\'s done'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _reopen,
                            icon: const Icon(Icons.undo_rounded, size: 18),
                            label: const Text('Reopen'),
                          ),
                        ],
                      ),
                    ],

                    // Open: add to the conversation.
                    if (status == 'Open' && replies.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _reply,
                              minLines: 1,
                              maxLines: 4,
                              onSubmitted: (_) => _sendReply(),
                              decoration: const InputDecoration(
                                hintText: 'Reply to the developer…',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _busy ? null : _sendReply,
                            icon: Icon(Icons.send_rounded, color: color),
                            tooltip: 'Send',
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyLine extends StatelessWidget {
  const _ReplyLine({required this.reply});
  final Map reply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dev = reply['from'] == 'developer';
    final at = (reply['at'] as Timestamp?)?.toDate();
    final when = at == null ? '' : ' · ${at.month}/${at.day}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: dev
            ? AppTheme.tint(AppTheme.accent)
            : theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dev
              ? AppTheme.edge(AppTheme.accent).withValues(alpha: 0.4)
              : theme.dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (dev) ...[
                Icon(
                  Icons.code_rounded,
                  size: 14,
                  color: AppTheme.onTint(AppTheme.accent),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                dev ? 'Developer$when' : 'You$when',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: dev
                      ? AppTheme.onTint(AppTheme.accent)
                      : theme.textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            reply['text'] as String? ?? '',
            style: TextStyle(
              color: theme.textTheme.bodyLarge?.color,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
