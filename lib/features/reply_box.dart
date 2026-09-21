import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../core/models.dart';
import '../core/util.dart';
import '../widgets/chrome.dart';

/// The box at the foot of a thread, for sites that can be written to.
///
/// One line until someone means it. A thread is for reading, and a composer
/// that claims four lines of the pane before anyone has typed anything is
/// four lines of reading gone; it grows with what is written in it, up to a
/// point, and then scrolls itself.
class ReplyBox extends StatefulWidget {
  const ReplyBox({
    super.key,
    required this.onSend,
    this.to,
    this.onCancelTarget,
    this.onAttach,
    this.hint = '写下你的回复',
  });

  /// Throws with what to tell the reader when the forum refuses it. Whatever
  /// it throws is shown as it is written, so it should be a sentence.
  final Future<void> Function(String text) onSend;

  /// The post being answered, where the reader picked one out of the thread
  /// rather than writing to the thread as a whole.
  final ReplyTarget? to;

  /// Called when they take that back.
  final VoidCallback? onCancelTarget;

  /// Hands back what to write into the box for the pictures the reader
  /// chooses — null when they choose none. Throws with what to tell them when
  /// the forum will not take one. Null where the site takes no pictures.
  final Future<String?> Function()? onAttach;

  final String hint;

  @override
  State<ReplyBox> createState() => _ReplyBoxState();
}

class _ReplyBoxState extends State<ReplyBox> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;
  bool _attaching = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _text.addListener(_typed);
  }

  @override
  void didUpdateWidget(covariant ReplyBox old) {
    super.didUpdateWidget(old);
    // Answering someone is done from up in the thread, and what happens next
    // is typing. Landing in the box saves the trip back down to it.
    if (widget.to?.postId != old.to?.postId && widget.to != null) {
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The button turns on and off with the field, and a complaint about what
  /// was written stops being about it the moment it is edited.
  void _typed() {
    if (!mounted) return;
    setState(() => _problem = null);
  }

  bool get _busy => _sending || _attaching;

  bool get _ready => _text.text.trim().isNotEmpty && !_busy;

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
      // Emptied only now, once the forum has it. Clearing notifies the
      // listener, which rebuilds; only the flag is left to set here.
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

  /// Picks pictures, hands them over, and writes in what came back.
  Future<void> _attach() async {
    final ask = widget.onAttach;
    if (ask == null || _busy) return;
    setState(() {
      _attaching = true;
      _problem = null;
    });
    try {
      final written = await ask();
      if (!mounted) return;
      setState(() => _attaching = false);
      if (written != null && written.isNotEmpty) _insert(written);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _attaching = false;
        _problem = errorText(e);
      });
    }
  }

  /// Writes [markdown] in where the cursor was, on a line of its own.
  ///
  /// Where the cursor was rather than at the end: someone who wrote a
  /// paragraph, went back up and then asked for a picture meant it there.
  void _insert(String markdown) {
    final value = _text.value;
    final at = value.selection.isValid ? value.selection.start : value.text.length;
    final until = value.selection.isValid ? value.selection.end : value.text.length;
    final before = value.text.substring(0, at);
    final after = value.text.substring(until);
    final lead = before.isEmpty || before.endsWith('\n') ? '' : '\n';
    final trail = after.isEmpty || after.startsWith('\n') ? '' : '\n';
    final written = '$lead$markdown$trail';
    _text.value = TextEditingValue(
      text: '$before$written$after',
      selection: TextSelection.collapsed(offset: before.length + written.length),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final mac = Theme.of(context).platform == TargetPlatform.macOS;
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.to case final to?) _TargetLine(to: to, onCancel: widget.onCancelTarget),
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
                focusNode: _focus,
                // Read-only rather than disabled while it is on its way.
                // What was written has to stay both there and legible until
                // the forum has taken it: Material paints a disabled field at
                // 38% opacity, which on this canvas reads as the box having
                // emptied itself the moment 发送 was pressed.
                readOnly: _sending,
                minLines: 1,
                maxLines: 6,
                style: const TextStyle(fontSize: 13, height: 1.45),
                decoration: InputDecoration(hintText: widget.hint),
              ),
            ),
          ),
          if (widget.onAttach != null) ...[
            const SizedBox(width: 4),
            SizedBox(
              width: 30,
              height: kControlHeight,
              child: Center(
                // In the button's own place rather than over the box: what is
                // on its way is one picture, not the reply.
                child: _attaching
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : QuietIconButton(
                        icon: Icons.image_outlined,
                        tooltip: '插入图片',
                        size: 16,
                        box: 30,
                        onPressed: _sending ? null : _attach,
                      ),
              ),
            ),
          ],
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

/// Who is being answered, over the box.
///
/// Small print rather than a banner: it is a fact about the reply, and the
/// reply is the thing being written.
class _TargetLine extends StatelessWidget {
  const _TargetLine({required this.to, this.onCancel});

  final ReplyTarget to;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final floor = to.floor == null ? '' : ' #${to.floor}';
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Row(children: [
        Icon(Icons.reply_rounded, size: 13, color: p.inkFaint),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '回复 ${to.author ?? '楼主'}$floor',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: p.inkMuted),
          ),
        ),
        if (onCancel != null) ...[
          const SizedBox(width: 2),
          QuietIconButton(
            icon: Icons.close_rounded,
            tooltip: '改回复整个帖子',
            size: 12,
            box: 22,
            onPressed: onCancel,
          ),
        ],
      ]),
    );
  }
}
