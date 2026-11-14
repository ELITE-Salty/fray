import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/localization.dart';
import 'data.dart';

class AccountSecurityDialog extends StatefulWidget {
  final FrayStore store;
  const AccountSecurityDialog({super.key, required this.store});
  @override
  State<AccountSecurityDialog> createState() => _AccountSecurityDialogState();
}

class _AccountSecurityDialogState extends State<AccountSecurityDialog>
    with LocalizedState {
  String action = 'password';
  final password = TextEditingController(),
      code = TextEditingController(),
      newPassword = TextEditingController(),
      confirmation = TextEditingController();
  bool busy = false, acknowledged = false;
  String? error, notice;
  Map<String, dynamic>? setup;
  List<String>? recovery;
  @override
  void dispose() {
    for (final c in [password, code, newPassword, confirmation]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final store = widget.store;
      if (store.demo) {
        throw ApiException(
          'Account security is available for signed-in accounts.',
        );
      }
      if (action == 'delete' &&
          (store.queue.isNotEmpty || store.runningTimer != null)) {
        throw ApiException(
          'Sync or discard pending entries and stop the timer before deleting your account.',
        );
      }
      if (action == 'password' && newPassword.text != confirmation.text) {
        throw ApiException('The passwords do not match.');
      }
      final result = await store.api(
        'POST',
        setup == null
            ? '/api/account/$action'
            : '/api/account/authenticator/finish',
        setup == null
            ? {
                'password': password.text,
                'code': code.text.trim(),
                'newPassword': newPassword.text,
                'confirmation': confirmation.text,
              }
            : {'code': code.text.trim()},
      );
      password.clear();
      code.clear();
      newPassword.clear();
      confirmation.clear();
      if (action == 'delete') {
        await store.forgetWorkspace();
        if (mounted) Navigator.pop(context);
        return;
      }
      if (!mounted) return;
      setState(() {
        if (result['secret'] != null) {
          setup = Map<String, dynamic>.from(result);
        } else if (result['recoveryCodes'] != null) {
          recovery = List<String>.from(result['recoveryCodes']);
          setup = null;
        } else {
          notice = 'Password changed. Other sessions must sign in again.';
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && (recovery == null || acknowledged),
    child: AlertDialog(
      title: Text(tr('Account security')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (recovery != null) ...[
                Text(
                  tr(
                    'Save these new recovery codes. Previous recovery codes no longer work.',
                  ),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  recovery!.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                TextButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: recovery!.join('\n')),
                  ),
                  icon: const Icon(Icons.copy),
                  label: Text(tr('Copy recovery codes')),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: acknowledged,
                  onChanged: (v) => setState(() => acknowledged = v ?? false),
                  title: Text(tr('I have saved my recovery codes')),
                ),
              ] else if (setup != null) ...[
                Text(
                  tr(
                    'Scan the code or copy the setup key. Your current authenticator works until you confirm the new one.',
                  ),
                ),
                Center(
                  child: QrImageView(
                    data: setup!['uri'],
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
                SelectableText(setup!['secret']),
                TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: setup!['secret'])),
                  icon: const Icon(Icons.copy),
                  label: Text(tr('Copy setup key')),
                ),
                TextField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('Authenticator code'),
                  ),
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  initialValue: action,
                  isExpanded: true,
                  items:
                      {
                            'password': 'Change password',
                            'recovery': 'Regenerate recovery codes',
                            'rotate': 'Replace authenticator',
                            'delete': 'Delete account',
                          }.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(
                                tr(e.value),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          action = v!;
                          error = notice = null;
                          password.clear();
                          code.clear();
                          newPassword.clear();
                          confirmation.clear();
                        }),
                ),
                const SizedBox(height: 16),
                if (action == 'delete')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      tr(
                        'This permanently deletes your account and personal records. Transfer shared projects first. Type DELETE to confirm.',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: tr('Current password'),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: code,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: tr('Authenticator or recovery code'),
                  ),
                ),
                if (action == 'password') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: newPassword,
                    obscureText: true,
                    decoration: InputDecoration(labelText: tr('New password')),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: confirmation,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: tr('Confirm password'),
                    ),
                  ),
                ],
                if (action == 'delete') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: confirmation,
                    decoration: InputDecoration(labelText: tr('Type DELETE')),
                  ),
                ],
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    tr(error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(tr(notice!)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy || (recovery != null && !acknowledged)
              ? null
              : () => Navigator.pop(context),
          child: Text(tr('Done')),
        ),
        if (recovery == null)
          FilledButton(
            onPressed: busy ? null : submit,
            child: Text(
              tr(
                busy
                    ? 'Please wait…'
                    : setup != null
                    ? 'Finish setup'
                    : action == 'delete'
                    ? 'Delete account'
                    : 'Confirm',
              ),
            ),
          ),
      ],
    ),
  );
}
