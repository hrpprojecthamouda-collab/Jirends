/// Onboarding — set your handle (nickname#tagline). The pair is globally unique
/// and case-insensitive; the DB enforces both. On success the router lets the
/// user into the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/onboarding_controller.dart';
import '../../auth/application/auth_controller.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  final _tagline = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Live preview of the handle as the user types.
    _nickname.addListener(() => setState(() {}));
    _tagline.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nickname.dispose();
    _tagline.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(onboardingControllerProvider.notifier).setHandle(
          nickname: _nickname.text,
          tagline: _tagline.text,
        );
    // On success the router redirects to home (myProfileProvider invalidated).
    if (ok && mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  String? _validatePart(String? v, String label) {
    final s = (v ?? '').trim();
    if (s.length < 2 || s.length > 24) return '$label must be 2–24 characters';
    if (s.contains('#')) return '$label cannot contain “#”';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingControllerProvider);
    final loading = state.isLoading;
    final nick = _nickname.text.trim();
    final tag = _tagline.text.trim();
    final preview = (nick.isEmpty && tag.isEmpty)
        ? 'nickname#tagline'
        : '${nick.isEmpty ? 'nickname' : nick}#${tag.isEmpty ? 'tagline' : tag}';

    ref.listen(onboardingControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(next.error!))));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose your handle'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Pick a nickname and a tagline. Together they form your unique '
                  'handle — this is how friends add you.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(preview,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontFeatures: const [], color: Theme.of(context).colorScheme.primary)),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nickname,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Nickname', prefixText: ''),
                  validator: (v) => _validatePart(v, 'Nickname'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tagline,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Tagline', prefixText: '#'),
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) => _validatePart(v, 'Tagline'),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: loading ? null : _submit,
                  child: loading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
