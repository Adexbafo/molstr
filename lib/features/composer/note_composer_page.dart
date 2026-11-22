import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/relay_service.dart';
import '../../core/text/hashtags.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import '../../core/nostr/blossom.dart';
import 'dart:io';

// De facto poll format (kind 1068; votes are kind 1070). Zap polls are
// NIP-75 kind 6969. Verify against https://github.com/nostr-protocol/nips
// before relying on this in production.
const _pollKind = 1068;

class NoteComposerPage extends StatefulWidget {
  const NoteComposerPage({
    super.key,
    required this.identityService,
    required this.relayService,
    required this.relays,
  });

  final IdentityService identityService;
  final RelayService relayService;
  final List<String> relays;

  @override
  State<NoteComposerPage> createState() => _NoteComposerPageState();
}

class _NoteComposerPageState extends State<NoteComposerPage> {
  final _controller = TextEditingController();
  final _optionControllers = List.generate(
    2,
    (_) => TextEditingController(),
  );

  String _mode = 'note'; // 'note' | 'poll'
  bool _multipleChoice = false;
  int _pollDurationHours = 24;
  bool _publishing = false;
  bool _attaching = false;
  String _blossomServer = 'https://blossom.primal.net';

  List<String> _hashtags = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final next = Hashtags.extract(_controller.text);
      if (!_listEquals(next, _hashtags)) {
        setState(() => _hashtags = next);
      }
    });
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= 6) return;
    setState(() => _optionControllers.add(TextEditingController()));
  }

  Future<void> _attachImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;

    final bytes = picked.bytes ??
        (picked.path != null ? await _readPath(picked.path!) : null);
    if (bytes == null) {
      _showMessage('Could not read the image.');
      return;
    }
    if (bytes.length > 5 * 1024 * 1024) {
      _showMessage('Image is larger than 5 MB.');
      return;
    }

    setState(() => _attaching = true);
    try {
      final url = await BlossomUpload.upload(
        bytes: bytes,
        filename: picked.name,
        mimeType: _mimeFromExtension(picked.name),
        server: _blossomServer,
        identityService: widget.identityService,
      );
      final text = _controller.text;
      final sep = text.isEmpty || text.endsWith('\n') ? '' : '\n';
      _controller.text = '$text$sep$url';
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
      _showMessage('Image uploaded. URL added to your note.');
    } catch (error) {
      _showMessage(
          'Upload failed: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  Future<List<int>?> _readPath(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _mimeFromExtension(String name) {
    final ext = name.toLowerCase().split('.').last;
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _insertGif() async {
    final urlController = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insert GIF'),
        content: TextField(
          controller: urlController,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Direct image URL',
            hintText: 'https://example.com/animation.gif',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(urlController.text.trim()),
            child: const Text('Insert'),
          ),
        ],
      ),
    );
    urlController.dispose();

    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use a full https:// image URL.')),
      );
      return;
    }
    final text = _controller.text;
    final separator = text.isEmpty || text.endsWith('\n') ? '' : '\n';
    _controller.text = '$text$separator$url';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  Future<void> _publish() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;

    final hashtagTags = _hashtags.map((t) => <String>['t', t]).toList();

    List<List<String>> tags;
    int kind;

    if (_mode == 'poll') {
      final options = _optionControllers
          .map((c) => c.text.trim())
          .where((label) => label.isNotEmpty)
          .toList();
      if (options.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A poll needs at least 2 options.')),
        );
        return;
      }
      final endsAt = DateTime.now()
              .add(Duration(hours: _pollDurationHours))
              .millisecondsSinceEpoch ~/
          1000;
      kind = _pollKind;
      tags = [
        for (var i = 0; i < options.length; i++) ['option', '$i', options[i]],
        ['polltype', _multipleChoice ? 'multiplechoice' : 'singlechoice'],
        ['endsAt', '$endsAt'],
        ...hashtagTags,
      ];
    } else {
      kind = 1;
      tags = hashtagTags;
    }

    setState(() => _publishing = true);

    try {
      final event = await widget.identityService.signEvent(
        kind: kind,
        content: content,
        tags: tags,
      );
      final results =
          await widget.relayService.publishEvent(event, widget.relays);
      if (!mounted) return;

      final okCount = results.values.where((value) => value == 'ok').length;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            okCount > 0
                ? 'Published to $okCount of ${results.length} relays'
                : 'No relay accepted the note',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in results.entries)
                Text('${Uri.tryParse(entry.key)?.host ?? entry.key}: '
                    '${entry.value}'),
              if (okCount == 0) ...[
                const SizedBox(height: 12),
                const Text(
                  'The note was not distributed. Check relay URLs and '
                  'connection, then try again.',
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (okCount > 0) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _publishing = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _publishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not sign or publish. Is a local key connected?',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed:
              _publishing ? null : () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'note',
                  icon: Icon(Icons.notes),
                  label: Text('Note'),
                ),
                ButtonSegment(
                  value: 'poll',
                  icon: Icon(Icons.poll),
                  label: Text('Poll'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _publishing
                  ? null
                  : (selection) => setState(() => _mode = selection.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 10,
              autofocus: true,
              enabled: !_publishing,
              decoration: InputDecoration(
                hintText: _mode == 'poll'
                    ? 'Ask your question…'
                    : 'What’s happening? #hashtags',
                border: const OutlineInputBorder(),
              ),
            ),
            if (_hashtags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in _hashtags)
                    Chip(
                      avatar: tag == 'molstr'
                          ? SvgPicture.asset(
                              'assets/logo/molstr_icon.svg',
                              width: 16,
                              height: 16,
                            )
                          : null,
                      label: Text(
                        '#$tag',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: 'Attach image',
                  onPressed: _publishing || _attaching ? null : _attachImage,
                  icon: _attaching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.attach_file),
                ),
                TextButton.icon(
                  onPressed: _publishing ? null : _insertGif,
                  icon: const Icon(Icons.gif_box_outlined),
                  label: const Text('Image URL'),
                ),
                const Spacer(),
                Text('${_controller.text.length} chars',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              minLines: 1,
              maxLines: 1,
              enabled: !_publishing && !_attaching,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Blossom server',
                hintText: 'https://blossom.primal.net',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _blossomServer = v.trim(),
            ),
            if (_mode == 'poll') ...[
              const Divider(height: 32),
              Text('Options', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              for (var i = 0; i < _optionControllers.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Text('${i + 1}.'),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _optionControllers[i],
                          enabled: !_publishing,
                          decoration: InputDecoration(
                            labelText: 'Option ${i + 1}',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      if (_optionControllers.length > 2)
                        IconButton(
                          tooltip: 'Remove option',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: _publishing
                              ? null
                              : () => setState(
                                    () => _optionControllers
                                        .removeAt(i)
                                        .dispose(),
                                  ),
                        ),
                    ],
                  ),
                ),
              if (_optionControllers.length < 6)
                OutlinedButton.icon(
                  onPressed: _publishing ? null : _addOption,
                  icon: const Icon(Icons.add),
                  label: const Text('Add option'),
                ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Allow multiple choices'),
                value: _multipleChoice,
                onChanged: _publishing
                    ? null
                    : (value) => setState(() => _multipleChoice = value),
              ),
              DropdownButtonFormField<int>(
                value: _pollDurationHours,
                decoration: const InputDecoration(
                  labelText: 'Poll duration',
                  border: OutlineInputBorder(),
                ),
                items: const [1, 6, 24, 72, 168]
                    .map((h) => DropdownMenuItem(
                          value: h,
                          child: Text(
                            h < 24 ? '${h}h' : '${h ~/ 24}d',
                          ),
                        ))
                    .toList(),
                onChanged: _publishing
                    ? null
                    : (value) => setState(() => _pollDurationHours = value!),
              ),
            ],
            const Divider(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Publishes publicly to: ${widget.relays.join(', ')}\n'
                  'This is irreversible and visible to anyone reading these relays.',
                  style: textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _publishing || _controller.text.trim().isEmpty
                  ? null
                  : _publish,
              icon: _publishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_publishing ? 'Publishing…' : 'Publish'),
            ),
          ],
        ),
      ),
    );
  }
}
