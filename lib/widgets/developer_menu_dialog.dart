import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/repositories/progress_repository.dart';

class DeveloperMenuDialog extends StatefulWidget {
  const DeveloperMenuDialog({super.key});

  @override
  State<DeveloperMenuDialog> createState() => _DeveloperMenuDialogState();
}

class _DeveloperMenuDialogState extends State<DeveloperMenuDialog> {
  final _keyController = TextEditingController();
  late final TextEditingController _levelController;
  late final TextEditingController _sandboxLevelController;
  int _gridSize = 20;
  String? _keyError;

  @override
  void initState() {
    super.initState();
    final currentLevel = context.read<ProgressRepository>().currentLevel;
    _levelController = TextEditingController(text: '$currentLevel');
    _sandboxLevelController = TextEditingController(text: '$currentLevel');
  }

  @override
  void dispose() {
    _keyController.dispose();
    _levelController.dispose();
    _sandboxLevelController.dispose();
    super.dispose();
  }

  int? _readLevel(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    return value != null && value > 0 ? value : null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF21143A),
      title: Text(
        'DEVELOPER MENU',
        style: GoogleFonts.nunito(fontWeight: FontWeight.w900),
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: _keyError == null && _keyController.text == '764462'
              ? _buildTools(context)
              : _buildLock(context),
        ),
      ),
      actions: _keyController.text == '764462'
          ? [TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE'))]
          : [TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL'))],
    );
  }

  Widget _buildLock(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Enter developer key to continue.'),
        const SizedBox(height: 14),
        TextField(
          controller: _keyController,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Developer key',
            errorText: _keyError,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _unlock(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _unlock,
          icon: const Icon(Icons.lock_open_rounded),
          label: const Text('UNLOCK'),
        ),
      ],
    );
  }

  void _unlock() {
    setState(() {
      _keyError = _keyController.text == '764462' ? null : 'Incorrect key';
      if (_keyController.text != '764462') _keyController.clear();
    });
  }

  Widget _buildTools(BuildContext context) {
    final progress = context.watch<ProgressRepository>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Coins: ${progress.coins}    Hints: ${progress.hints}'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            if (kDebugMode)
              OutlinedButton.icon(
                onPressed: () => progress.addCoins(1000),
                icon: const Icon(Icons.monetization_on_outlined),
                label: const Text('+1,000 coins'),
              ),
            OutlinedButton.icon(
              onPressed: () => progress.addHints(10),
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('+10 hints'),
            ),
          ],
        ),
        const Divider(height: 28),
        TextField(
          controller: _levelController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Level number',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () {
            final level = _readLevel(_levelController);
            if (level == null) return;
            Navigator.pop(context, {'level': level});
          },
          icon: const Icon(Icons.skip_next_rounded),
          label: const Text('PLAY LEVEL'),
        ),
        const Divider(height: 28),
        TextField(
          controller: _sandboxLevelController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Sandbox level (4+)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          initialValue: _gridSize,
          decoration: const InputDecoration(
            labelText: 'Board size',
            border: OutlineInputBorder(),
          ),
          items: [
            for (var size = 10; size <= 40; size++)
              DropdownMenuItem(value: size, child: Text('$size × $size')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _gridSize = value);
          },
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () {
            final level = _readLevel(_sandboxLevelController);
            if (level == null || level < 4) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sandbox level must be 4 or higher.')),
              );
              return;
            }
            Navigator.pop(context, {'level': level, 'gridSize': _gridSize});
          },
          icon: const Icon(Icons.science_outlined),
          label: const Text('PLAY SANDBOX'),
        ),
      ],
    );
  }
}