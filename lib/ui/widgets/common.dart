import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../theme.dart';

class SearchField extends ConsumerStatefulWidget {
  const SearchField({super.key, required this.section});

  final AppSection section;

  @override
  ConsumerState<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<SearchField> {
  late final _controller = TextEditingController(text: ref.read(searchQueryProvider(widget.section)));

  @override
  void didUpdateWidget(SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      _controller.text = ref.read(searchQueryProvider(widget.section));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(searchQueryProvider(widget.section).notifier);
    return TextField(
      controller: _controller,
      onChanged: notifier.set,
      decoration: InputDecoration(
        hintText: '${widget.section.label} durchsuchen',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => _controller.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _controller.clear();
                    notifier.set('');
                  },
                ),
        ),
      ),
    );
  }
}

/// Lade- und Fehlerzustände für Kataloge, mit „Erneut laden“.
class AsyncStateView extends StatelessWidget {
  const AsyncStateView.loading({super.key})
      : error = null,
        onRetry = null;

  const AsyncStateView.error({super.key, required Object this.error, required this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text('$error', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Erneut laden')),
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
