import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/scope.dart';
import '../state/app_controller.dart';
import '../state/chat.dart';
import 'background.dart';
import 'devices_page.dart' show sinceLabel;
import 'glass.dart';
import 'theme.dart';

/// Messages tab: one thread per trusted device.
class MessagesTab extends StatelessWidget {
  const MessagesTab({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final threads = controller.chat.sorted;
    Color dot(String fp) => controller.isOnline(fp)
        ? AppColors.mint
        : controller.isRecent(fp)
            ? AppColors.amber
            : AppColors.muted;
    final startable = controller.trust.all.where((d) => !controller.chat.threads.containsKey(d.fingerprint)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SectionTitle(context.tr('tab_messages')),
        if (threads.isEmpty && startable.isEmpty)
          Glass(
            child: Column(
              children: [
                const IconBadge(icon: Icons.forum_rounded, color: AppColors.cyan, size: 52),
                const SizedBox(height: 12),
                Text(context.tr('chat_empty'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                const SizedBox(height: 6),
                Text(context.tr('chat_empty_sub'),
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
        for (final t in threads)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ThreadTile(
              name: controller.displayName(t.fingerprint, t.peerName),
              preview: t.messages.isEmpty ? '' : t.messages.last.text,
              unread: t.unread,
              dot: dot(t.fingerprint),
              onTap: () => _open(context, t.fingerprint, controller.displayName(t.fingerprint, t.peerName)),
            ),
          ),
        if (startable.isNotEmpty) ...[
          const SizedBox(height: 8),
          SectionTitle(context.tr('chat_new')),
          for (final d in startable)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ThreadTile(
                name: controller.displayName(d.fingerprint, d.name),
                preview: context.tr('chat_start'),
                unread: 0,
                dot: dot(d.fingerprint),
                onTap: () => _open(context, d.fingerprint, controller.displayName(d.fingerprint, d.name)),
              ),
            ),
        ],
      ],
    );
  }

  void _open(BuildContext context, String fp, String name) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatThreadPage(controller: controller, fingerprint: fp, name: name),
    ));
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.name,
    required this.preview,
    required this.unread,
    required this.dot,
    required this.onTap,
  });

  final String name;
  final String preview;
  final int unread;
  final Color dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Glass(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              const IconBadge(icon: Icons.person_rounded, color: AppColors.cyan, size: 44),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dot,
                    border: Border.all(color: AppColors.bgTop, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ],
            ),
          ),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.pink, borderRadius: BorderRadius.circular(10)),
              child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}

class ChatThreadPage extends StatefulWidget {
  const ChatThreadPage({super.key, required this.controller, required this.fingerprint, required this.name});
  final AppController controller;
  final String fingerprint;
  final String name;

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();

  Timer? _knock;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.openThread = widget.fingerprint;
    c.markThreadRead(widget.fingerprint);
    c.addListener(_onChange);
    // Don't trust a missed beacon: knock on the device's last address now and
    // every few seconds while the thread is open.
    c.pingDevice(widget.fingerprint);
    unawaited(c.rescan());
    _knock = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!c.isOnline(widget.fingerprint)) c.pingDevice(widget.fingerprint);
    });
  }

  @override
  void dispose() {
    _knock?.cancel();
    c.removeListener(_onChange);
    if (c.openThread == widget.fingerprint) c.openThread = null;
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChange() {
    if (c.chat.threads[widget.fingerprint]?.unread case final n? when n > 0) {
      c.chat.markRead(widget.fingerprint);
    }
  }

  void _send() {
    final text = _text.text;
    if (text.trim().isEmpty) return;
    _text.clear();
    unawaited(c.sendChat(widget.fingerprint, widget.name, text));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackground()),
          SafeArea(
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) {
                final online = c.isOnline(widget.fingerprint);
                final recent = !online && c.isRecent(widget.fingerprint);
                final seen = c.lastSeenOf(widget.fingerprint);
                final status = online
                    ? context.tr('online')
                    : [
                        context.tr(recent ? 'chat_reachable' : 'chat_offline'),
                        if (seen != null) context.tr('last_seen', {'t': sinceLabel(context, seen)}),
                      ].join(' · ');
                final statusColor = online ? AppColors.mint : recent ? AppColors.amber : AppColors.muted;
                final messages = c.chat.threads[widget.fingerprint]?.messages ?? const <ChatMessage>[];
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const BackButtonIcon(),
                            color: AppColors.text,
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                                Text(status,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: statusColor, fontSize: 12)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: context.tr('chat_clear'),
                            onPressed: messages.isEmpty ? null : () => _confirmClear(context),
                            icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: ListView.builder(
                            controller: _scroll,
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            itemCount: messages.length,
                            itemBuilder: (context, i) {
                              final idx = messages.length - 1 - i;
                              final m = messages[idx];
                              final bubble = _Bubble(
                                message: m,
                                onRetry: m.state == ChatState.failed
                                    ? () => unawaited(c.sendChat(widget.fingerprint, widget.name, m.text, retry: m))
                                    : null,
                              );
                              final newDay = idx == 0 || !_sameDay(messages[idx - 1].at, m.at);
                              if (!newDay) return bubble;
                              return Column(children: [_DayChip(at: m.at), bubble]);
                            },
                          ),
                        ),
                      ),
                    ),
                    if (!online)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.schedule_send_rounded, size: 14, color: statusColor),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(context.tr('chat_deliver_later'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: statusColor, fontSize: 11.5)),
                            ),
                          ],
                        ),
                      ),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          child: Glass(
                            radius: 24,
                            padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _text,
                                    minLines: 1,
                                    maxLines: 5,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _send(),
                                    decoration: InputDecoration(
                                      hintText: context.tr('chat_hint'),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      filled: false,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.tr('send'),
                                  onPressed: _send,
                                  icon: const Icon(Icons.send_rounded, color: AppColors.cyan),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => GlassDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('chat_clear_confirm'), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: GhostButton(label: context.tr('cancel'), expand: true, onPressed: () => Navigator.pop(ctx, false))),
                const SizedBox(width: 12),
                Expanded(
                  child: GhostButton(
                    label: context.tr('chat_clear'),
                    color: AppColors.danger,
                    expand: true,
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok == true) c.clearThread(widget.fingerprint);
  }
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// "Today" / "Yesterday" / a date, centred above the first message of a day.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.at});
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = _sameDay(at, now)
        ? context.tr('today')
        : _sameDay(at, now.subtract(const Duration(days: 1)))
            ? context.tr('yesterday')
            : MaterialLocalizations.of(context).formatMediumDate(at);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.onRetry});
  final ChatMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final out = message.outgoing;
    final time = TimeOfDay.fromDateTime(message.at).format(context);
    final icon = switch (message.state) {
      ChatState.sending => Icons.schedule_rounded,
      ChatState.sent => Icons.done_all_rounded,
      ChatState.failed => Icons.error_outline_rounded,
      ChatState.received => null,
    };
    return Align(
      alignment: out ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: message.text));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
          },
          onTap: onRetry,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: out ? kAccentGradient : null,
              color: out ? null : Colors.white.withValues(alpha: 0.08),
              border: out ? null : Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(message.text,
                    style: TextStyle(color: out ? AppColors.ink : AppColors.text, fontSize: 14.5, height: 1.35)),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(time, style: TextStyle(color: out ? AppColors.ink.withValues(alpha: 0.7) : AppColors.muted, fontSize: 10.5)),
                    if (icon != null) ...[
                      const SizedBox(width: 4),
                      Icon(icon, size: 13, color: message.state == ChatState.failed ? AppColors.danger : AppColors.ink.withValues(alpha: 0.7)),
                    ],
                    if (onRetry != null) ...[
                      const SizedBox(width: 4),
                      Text(context.tr('chat_retry'),
                          style: TextStyle(
                              color: out ? AppColors.ink : AppColors.danger,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              decoration: TextDecoration.underline)),
                    ],
                  ],
                ),
                if (message.state == ChatState.failed && message.error != null) ...[
                  const SizedBox(height: 2),
                  Text(message.error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: out ? AppColors.ink.withValues(alpha: 0.8) : AppColors.muted, fontSize: 10.5)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
