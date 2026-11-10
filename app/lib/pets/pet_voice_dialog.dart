// Foreground fallback when Android refuses/silences the overlay microphone.
// Product no longer ships on-device SenseVoice ASR, so this dialog only
// offers typed input (no engine transcription).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../ui/theme/app_icons.dart';

class PetVoiceDialog extends ConsumerStatefulWidget {
  const PetVoiceDialog({super.key, required this.text});
  final String text;
  @override
  ConsumerState<PetVoiceDialog> createState() => _PetVoiceDialogState();
}

class _PetVoiceDialogState extends ConsumerState<PetVoiceDialog> {
  late final TextEditingController _input;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.text)..selection = TextSelection.collapsed(offset: widget.text.length);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      icon: const Icon(AppIcons.voice),
      title: Text(l10n.petActionVoiceTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.petActionVoiceMissing),
          const SizedBox(height: 12),
          TextField(controller: _input, autofocus: true, maxLines: 4),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(_input.text), child: Text(l10n.commonDone)),
      ],
    );
  }
}
