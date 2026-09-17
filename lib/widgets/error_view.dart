import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_theme.dart';
import '../core/models.dart';
import '../features/linuxdo_auth_page.dart';
import '../features/providers.dart';

/// Shown wherever a load fails. An [AuthRequiredException] carries how to
/// recover, so this widget offers the right fix without knowing the site.
class ErrorView extends ConsumerWidget {
  const ErrorView({super.key, required this.error, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final auth = error is AuthRequiredException ? error as AuthRequiredException : null;
    final message = auth?.message ?? error.toString().replaceFirst('Exception: ', '');

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32, vertical: compact ? 20 : 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: p.raised,
                borderRadius: BorderRadius.circular(Radii.block),
              ),
              // A site that wrote its own hint is not telling a credentials
              // story — an unreachable forum gets the same cloud as any other
              // failure to connect, not a key.
              child: Icon(
                  auth != null && auth.hint == null
                      ? Icons.key_rounded
                      : Icons.cloud_off_rounded,
                  size: 19,
                  color: auth != null ? p.cream : p.inkMuted),
            ),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            if (auth != null) ...[
              const SizedBox(height: 6),
              Text(
                auth.hint ??
                    switch (auth.recovery) {
                      AuthRecovery.browser => '在内置浏览器里过一次验证，凭据会自动保存。',
                      AuthRecovery.settings => '到设置里更新这个站点的凭据。',
                    },
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 18),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              if (auth != null)
                FilledButton(
                  onPressed: () => _recover(context, ref, auth),
                  child: Text(switch (auth.recovery) {
                    AuthRecovery.browser => '打开内置浏览器',
                    AuthRecovery.settings => '前往设置',
                  }),
                ),
              if (onRetry != null)
                OutlinedButton(onPressed: onRetry, child: const Text('重试')),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _recover(
      BuildContext context, WidgetRef ref, AuthRequiredException auth) async {
    switch (auth.recovery) {
      case AuthRecovery.browser:
        final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const LinuxDoAuthPage(),
        ));
        if (ok == true) {
          ref.invalidate(sectionsProvider(auth.site));
          onRetry?.call();
        }
      case AuthRecovery.settings:
        // Land on the forums half, which is where every per-site fix lives.
        ref.read(settingsTabProvider.notifier).state = SettingsTab.forums;
        ref.read(navProvider.notifier).state = NavTarget.settings;
    }
  }
}
