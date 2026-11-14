import 'package:flutter/material.dart';

import '../l10n/localization.dart';
import 'data.dart';
import 'tracking_features.dart';

class ProjectSharingDialog extends StatefulWidget {
  final FrayStore store;
  final WorkItem? item;
  final DateTime month;
  const ProjectSharingDialog({
    super.key,
    required this.store,
    this.item,
    required this.month,
  });
  @override
  State<ProjectSharingDialog> createState() => _ProjectSharingDialogState();
}

class _ProjectSharingDialogState extends State<ProjectSharingDialog>
    with LocalizedState {
  Map<String, dynamic> data = {};
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  String get path => widget.item == null
      ? '/api/invitations'
      : '/api/projects/${widget.item!.id}';
  Future<void> load() async {
    try {
      if (widget.store.demo) {
        throw ApiException('Sharing is available for signed-in accounts.');
      }
      final result = await widget.store.api(
        'GET',
        '$path${widget.item == null ? '' : '?month=${monthKey(widget.month)}'}',
      );
      if (mounted) setState(() => data = Map<String, dynamic>.from(result));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> change(Map<String, dynamic> body, {bool leave = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.api(leave ? 'DELETE' : 'POST', path, body);
      await widget.store.load(widget.month);
      if (!mounted) return;
      if (leave || body['action'] == 'transfer') {
        Navigator.pop(context);
        return;
      }
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirm(
    String title,
    Map<String, dynamic> body, {
    bool leave = false,
  }) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(title)),
        content: Text(
          tr(
            'Personal entries and notes stay private. Historical time remains in the project totals.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Confirm')),
          ),
        ],
      ),
    );
    if (yes == true) await change(body, leave: leave);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.item?.name ?? tr('Invitations')),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Text(
                tr(error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (widget.item != null && data.isNotEmpty) ...[
              Text(
                '${tr('Project total this month')}: ${context.duration(data['totalMinutes'])}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  'Only aggregate time is shared. Individual entries and notes remain private.',
                ),
              ),
              const Divider(height: 28),
              Text(
                tr('Members'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final member in data['members'] ?? [])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(member['name']),
                  subtitle: Text(
                    tr(member['role'] == 'owner' ? 'Owner' : 'Member'),
                  ),
                  trailing: data['isOwner'] == true && member['role'] != 'owner'
                      ? PopupMenuButton<String>(
                          enabled: !busy,
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'remove',
                              child: Text(tr('Remove member')),
                            ),
                            PopupMenuItem(
                              value: 'transfer',
                              child: Text(tr('Transfer ownership')),
                            ),
                          ],
                          onSelected: (action) => confirm(
                            action == 'remove'
                                ? 'Remove this member?'
                                : 'Transfer ownership to this member?',
                            {'action': action, 'userId': member['id']},
                          ),
                        )
                      : null,
                ),
              if (data['isOwner'] == true) ...[
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final email = await askText(
                            context,
                            'Invite by email',
                          );
                          if (email != null && email.trim().isNotEmpty) {
                            await change({
                              'action': 'invite',
                              'email': email.trim(),
                            });
                          }
                        },
                  icon: const Icon(Icons.person_add_outlined),
                  label: Text(tr('Invite by email')),
                ),
                for (final invitation in data['invitations'] ?? [])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(invitation['email']),
                    subtitle: Text(tr('Pending invitation')),
                    trailing: PopupMenuButton<String>(
                      enabled: !busy,
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'resend',
                          child: Text(tr('Resend invitation')),
                        ),
                        PopupMenuItem(
                          value: 'revoke',
                          child: Text(tr('Revoke invitation')),
                        ),
                      ],
                      onSelected: (action) => change(
                        action == 'resend'
                            ? {'action': 'invite', 'email': invitation['email']}
                            : {
                                'action': 'revoke',
                                'invitationId': invitation['id'],
                              },
                      ),
                    ),
                  ),
              ] else
                TextButton(
                  onPressed: busy
                      ? null
                      : () => confirm('Leave this project?', {}, leave: true),
                  child: Text(tr('Leave project')),
                ),
            ],
            if (widget.item == null) ...[
              Text(
                tr('Invitations are linked to your signed-in email address.'),
              ),
              if ((data['invitations'] as List? ?? []).isEmpty && !busy)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Text(tr('No pending invitations.')),
                ),
              for (final invitation in data['invitations'] ?? [])
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invitation['project'],
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          FilledButton(
                            onPressed: busy
                                ? null
                                : () => change({
                                    'id': invitation['id'],
                                    'accept': true,
                                  }),
                            child: Text(tr('Accept')),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => change({
                                    'id': invitation['id'],
                                    'accept': false,
                                  }),
                            child: Text(tr('Decline')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: Text(tr('Done')),
      ),
    ],
  );
}
