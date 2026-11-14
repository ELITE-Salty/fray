import '../l10n/localization.dart';
import 'preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'app.dart' show Brand;
import 'data.dart';

class LoginScreen extends StatefulWidget {
  final FrayStore store;
  const LoginScreen({super.key, required this.store});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with LocalizedState {
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController(),
      confirmation = TextEditingController(),
      code = TextEditingController();
  String stage = 'credentials';
  bool signingUp = false, busy = true, savedCodes = false;
  String? error, notice;
  Map<String, dynamic> challenge = {}, completed = {};

  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    try {
      final result = await widget.store.authStatus();
      if (mounted) setState(() => applyChallenge(result));
    } catch (_) {
      // The credential form remains usable when the API is temporarily offline.
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void applyChallenge(Map<String, dynamic> result) {
    challenge = result;
    stage = result['stage'] ?? 'credentials';
    if (result['email'] != null) email.text = result['email'];
    code.clear();
  }

  @override
  void dispose() {
    for (final controller in [email, password, name, confirmation, code]) {
      controller.dispose();
    }
    challenge.clear();
    completed.clear();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() => perform(() async {
    if (stage == 'credentials') {
      if (email.text.trim().isEmpty || password.text.isEmpty) {
        throw ApiException(tr('Enter your email and password.'));
      }
      if (signingUp && password.text != confirmation.text) {
        throw ApiException(tr('The passwords do not match.'));
      }
      final result = signingUp
          ? await widget.store.beginSignUp(
              name.text.trim(),
              email.text.trim(),
              password.text,
            )
          : await widget.store.beginSignIn(email.text.trim(), password.text);
      password.clear();
      confirmation.clear();
      if (mounted) setState(() => applyChallenge(result));
    } else if (stage == 'email') {
      final result = await widget.store.verifyEmail(code.text.trim());
      if (mounted) setState(() => applyChallenge(result));
    } else if (stage == 'mfa' || stage == 'enroll') {
      final enrolling = stage == 'enroll';
      final result = await widget.store.verifySecurityCode(
        code.text.trim(),
        enrolling: enrolling,
      );
      code.clear();
      if (!mounted) return;
      if (enrolling) {
        setState(() {
          completed = result;
          challenge = {};
          stage = 'recovery';
        });
      } else {
        widget.store.completeAuth(result);
      }
    }
  });

  Future<void> back() => perform(() async {
    await widget.store.cancelAuth();
    if (mounted) {
      setState(() {
        stage = 'credentials';
        signingUp = false;
        challenge = {};
        code.clear();
      });
    }
  });

  String get title => switch (stage) {
    'email' => tr('Check your email'),
    'enroll' => tr('Protect your account'),
    'mfa' => tr('Enter your security code'),
    'recovery' => tr('Keep a way back in'),
    _ =>
      signingUp
          ? tr('Make time for yourself.')
          : tr('A little clarity.\nA lot more focus.'),
  };

  String get subtitle => switch (stage) {
    'email' => tr(
      'Enter the six-digit code sent to {email}. Check your spam folder too.',
      {'email': email.text},
    ),
    'enroll' => tr(
      'Your email is verified. Add Fray to your authenticator, then enter its code.',
    ),
    'mfa' => tr(
      'Use your authenticator or a recovery code to finish signing in as {email}.',
      {'email': email.text},
    ),
    'recovery' => tr(
      'Save these codes somewhere private. Each works once if you lose access to your authenticator. They are shown only now.',
    ),
    _ =>
      signingUp
          ? tr(
              'Create your account, verify your email, and set up two-factor authentication.',
            )
          : tr(
              'Your time, projects, and everyday progress.\nAll in one quiet place.',
            ),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerRight,
                child: PreferencesButton(),
              ),
              const Center(child: Brand()),
              const SizedBox(height: 32),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontSize: 32),
              ),
              const SizedBox(height: 14),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: 28),
              if (stage == 'credentials') ...[
                if (signingUp) ...[
                  TextField(
                    controller: name,
                    enabled: !busy,
                    autofillHints: const [AutofillHints.name],
                    decoration: InputDecoration(
                      labelText: tr('Name (optional)'),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: tr('Email'),
                    prefixIcon: const Icon(Icons.mail_outline_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: password,
                  enabled: !busy,
                  obscureText: true,
                  autofillHints: [
                    signingUp
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  onSubmitted: (_) {
                    if (!busy && !signingUp) submit();
                  },
                  decoration: InputDecoration(
                    labelText: tr('Password'),
                    helperText: signingUp ? tr('At least 12 characters') : null,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                  ),
                ),
                if (signingUp) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: confirmation,
                    enabled: !busy,
                    obscureText: true,
                    onSubmitted: (_) {
                      if (!busy) submit();
                    },
                    decoration: InputDecoration(
                      labelText: tr('Confirm password'),
                    ),
                  ),
                ],
              ],
              if (stage == 'enroll') ...[
                Center(
                  child: QrImageView(
                    data: challenge['uri'] as String,
                    size: 200,
                    backgroundColor: Colors.white,
                    semanticsLabel: tr('Authenticator setup QR code'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    'On the same phone? Copy this setup key and add it manually in your authenticator as a time-based account.',
                  ),
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  challenge['secret'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'monospace', color: ink),
                ),
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: challenge['secret'] as String),
                          );
                          if (mounted) {
                            setState(
                              () =>
                                  notice = 'Setup key copied. Keep it private.',
                            );
                          }
                        },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(tr('Copy setup key')),
                ),
                const SizedBox(height: 14),
              ],
              if (['email', 'mfa', 'enroll'].contains(stage))
                TextField(
                  controller: code,
                  enabled: !busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: stage == 'mfa'
                      ? TextInputType.text
                      : TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  onSubmitted: (_) {
                    if (!busy) submit();
                  },
                  decoration: InputDecoration(
                    labelText: stage == 'email'
                        ? tr('Email verification code')
                        : stage == 'enroll'
                        ? tr('Authenticator code')
                        : tr('Authenticator or recovery code'),
                    prefixIcon: const Icon(Icons.shield_outlined),
                  ),
                ),
              if (stage == 'recovery') ...[
                SelectableText(
                  (completed['recoveryCodes'] as List).join('\n'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'monospace', height: 1.8),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: (completed['recoveryCodes'] as List).join('\n'),
                      ),
                    );
                    if (mounted) {
                      setState(
                        () => notice =
                            'Recovery codes copied. Store them privately.',
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(tr('Copy recovery codes')),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: savedCodes,
                  onChanged: (value) =>
                      setState(() => savedCodes = value ?? false),
                  title: Text(tr('I have saved my recovery codes')),
                ),
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
              const SizedBox(height: 22),
              FilledButton(
                onPressed: busy
                    ? null
                    : stage == 'recovery'
                    ? (savedCodes
                          ? () => widget.store.completeAuth(completed)
                          : null)
                    : submit,
                child: Text(
                  busy
                      ? tr('Please wait…')
                      : switch (stage) {
                          'email' => tr('Verify email'),
                          'enroll' => tr('Finish setup'),
                          'mfa' => tr('Verify and sign in'),
                          'recovery' => tr('Open my workspace'),
                          _ => signingUp ? tr('Create account') : tr('Sign in'),
                        },
                ),
              ),
              if (stage == 'email')
                TextButton(
                  onPressed: busy
                      ? null
                      : () => perform(() async {
                          await widget.store.resendEmail();
                          if (mounted) {
                            setState(
                              () => notice = 'A new code was sent. Use the most recent email.',
                            );
                          }
                        }),
                  child: Text(tr('Resend email code')),
                ),
              if (['email', 'mfa', 'enroll'].contains(stage))
                TextButton(
                  onPressed: busy ? null : back,
                  child: Text(tr('Back to sign in')),
                ),
              if (stage == 'credentials') ...[
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          signingUp = !signingUp;
                          error = null;
                          password.clear();
                          confirmation.clear();
                        }),
                  child: Text(
                    signingUp
                        ? tr('Already have an account? Sign in')
                        : tr('Create an account'),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: busy ? null : widget.store.startDemo,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(18),
                  ),
                  child: Text(tr('Explore the demo')),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                tr(
                  'Private by default. Protected with two-factor authentication.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 12, height: 1.7),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
