import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../core/util.dart';

/// The box at the foot of a thread, for sites that can be written to.
///
/// One line until someone means it. A thread is for reading, and a composer
/// that claims four lines of the pane before anyone has typed anything is
/// four lines of reading gone; it grows with what is written in it, up to a
/// point, and then scrolls itself.
class ReplyBox extends StatefulWidget {
  const ReplyBox({super.key, required this.onSend, this.hint = '写下你的回复'});

  /// Throws with what to tell the reader when the forum refuses it. Whatever
  /// it throws is shown as it is written, so it should be a sentence.
  final Future<void> Function(String text) onSend;

  final String hint;

  @override
  State<ReplyBox> createState() => _ReplyBoxState();
}

class _ReplyBoxState extends State<ReplyBox> {
  final _text = TextEditingController();
  bool _sending = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _text.addListener(_typed);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// The button turns on and off with the field, and a complaint about what
  /// was written stops being about it the moment it is edited.
  void _typed() {
    if (!mounted) return;
    setState(() => _problem = null);
  }

  bool get _ready => _text.text.trim().isNotEmpty && !_sending;

  Future<void> _send() async {
    if (!_ready) return;
    final text = _text.text.trim();
    setState(() {
      _sending = true;
      _problem = null;
    });
    try {
      await widget.onSend(text);
      if (!mounted) return;
      // Clearing notifies the listener, which rebuilds; only the flag is left
      // to set here.
      _text.clear();
      setState(() => _sending = false);
    } catch (e) {
      if (!mounted) return;
      // What was written stays put. Whatever went wrong, typing it again is
      // not the fix.
      setState(() {
        _sending = false;
        _problem = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final mac = Theme.of(context).platform == TargetPlatform.macOS;
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_problem case final problem?) ...[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_outline_rounded, size: 13, color: p.rose),
              const SizedBox(width: 6),
              Expanded(
                child: Text(problem,
                    style:
                        TextStyle(fontSize: 12, height: 1.3, color: p.rose)),
              ),
            ]),
          ),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: CallbackShortcuts(
              // Enter is a new paragraph. A forum reply is not a chat message
              // and is worth sending on purpose, so the shortcut takes a
              // modifier and the button is always there for anyone who would
              // rather not learn one.
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                    _send,
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    _send,
              },
              child: TextField(
                controller: _text,
                enabled: !_sending,
                minLines: 1,
                maxLines: 6,
                style: const TextStyle(fontSize: 13, height: 1.45),
                decoration: InputDecoration(hintText: widget.hint),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: mac ? '发送（⌘ + ↵）' : '发送（Ctrl + ↵）',
            child: SizedBox(
              height: kControlHeight,
              child: FilledButton(
                onPressed: _ready ? _send : null,
                child: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('发送'),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}
