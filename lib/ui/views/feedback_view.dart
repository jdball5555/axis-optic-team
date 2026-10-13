import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

/// Feedback tickets live under the person who sent them:
/// /users/{userId}/feedback/{ticketId} (covered by the existing rules for
/// /users/**).
CollectionReference<Map<String, dynamic>> _ticketsFor(String userId) =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('feedback');

class FeedbackView extends ConsumerStatefulWidget {
  const FeedbackView({super.key});

  @override
  ConsumerState<FeedbackView> createState() => _FeedbackViewState();
}

class _FeedbackViewState extends ConsumerState<FeedbackView> {
  final _messageController = TextEditingController();
  String _type = 'Improvement';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    final message = _messageController.text.trim();
    final userId = ref.read(currentUserProvider)?['id'] as String?;
    if (message.isEmpty || userId == null) return;

    setState(() => _isSubmitting = true);
    try {
      await _ticketsFor(userId).add({
        'type': _type,
        'message': message,
        'submitted_by': userId,
        'store_id': ref.read(currentStoreIdProvider) ?? 'all',
        'status': 'Open',
        'timestamp': FieldValue.serverTimestamp(),
      });
      _messageController.clear();
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
                    'Report a bug or share an idea to help improve Axis Team.',
                    style: TextStyle(color: theme.textTheme.bodySmall?.color),
                  ),
                  const SizedBox(height: 24),
                  _buildComposer(theme),
                  const SizedBox(height: 32),
                  Text(
                    'My open tickets',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.titleLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (userId == null)
                    const _NoTickets()
                  else
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _ticketsFor(userId).snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const _NoTickets(
                            message: 'Your tickets couldn\'t be loaded right now.',
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final tickets =
                            snapshot.data!.docs
                                .where(
                                  (t) =>
                                      (t.data()['status'] as String? ?? 'Open') ==
                                      'Open',
                                )
                                .toList()
                              ..sort((a, b) {
                                final aTime = a.data()['timestamp'] as Timestamp?;
                                final bTime = b.data()['timestamp'] as Timestamp?;
                                return (bTime?.millisecondsSinceEpoch ?? 1 << 62)
                                    .compareTo(
                                      aTime?.millisecondsSinceEpoch ?? 1 << 62,
                                    );
                              });
                        if (tickets.isEmpty) return const _NoTickets();
                        return Column(
                          children: [
                            for (final t in tickets) _FeedbackTicket(ticket: t),
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
                  color: AppTheme.accent2,
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
                  color: AppTheme.accent,
                  selected: isBug,
                  onTap: () => setState(() => _type = 'Bug'),
                ),
              ),
            ],
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
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _isSubmitting ? null : _submitFeedback,
              icon: _isSubmitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_outlined, size: 18),
              label: Text(_isSubmitting ? 'Sending…' : 'Send feedback'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
            color: selected ? AppTheme.tint(color) : theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : theme.dividerColor,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: selected ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
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
              if (selected) Icon(Icons.check_circle, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoTickets extends StatelessWidget {
  final String message;
  const _NoTickets({this.message = 'There are no tickets.'});

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
          Text(message, style: TextStyle(color: theme.textTheme.bodySmall?.color)),
        ],
      ),
    );
  }
}

class _FeedbackTicket extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> ticket;
  const _FeedbackTicket({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = ticket.data();
    final isBug = data['type'] == 'Bug';
    final color = isBug ? AppTheme.accent : AppTheme.accent2;
    final time = (data['timestamp'] as Timestamp?)?.toDate();
    final submittedOn = time == null
        ? 'Sending…'
        : '${time.month}/${time.day}/${time.year}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isBug ? Icons.bug_report_outlined : Icons.lightbulb_outline,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      data['type'] as String? ?? 'Feedback',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(label: data['status'] as String? ?? 'Open', color: color),
                    const Spacer(),
                    Text(
                      submittedOn,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  data['message'] as String? ?? '',
                  style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                ),
              ],
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
        color: AppTheme.tint(color),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppTheme.onTint(color),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
