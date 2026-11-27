import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/nostr/blossom.dart';
import '../../core/nostr/identity_service.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/relay_service.dart';
import '../../ui/widgets/molstr_avatar.dart';

class ProfileEditorPage extends StatefulWidget {
  const ProfileEditorPage({
    super.key,
    required this.identityService,
    required this.relayService,
    required this.relays,
    required this.current,
    required this.loadImages,
  });

  final IdentityService identityService;
  final RelayService relayService;
  final List<String> relays;
  final ProfileMetadata? current;
  final bool loadImages;

  @override
  State<ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<ProfileEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _about;
  late final TextEditingController _picture;
  late final TextEditingController _banner;
  late final TextEditingController _nip05;
  late final TextEditingController _lud16;
  late final TextEditingController _monero;

  String _blossomServer = 'https://blossom.primal.net';
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _uploadingBanner = false;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    _name = TextEditingController(text: c?.bestName ?? '');
    _about = TextEditingController(text: c?.about ?? '');
    _picture = TextEditingController(text: c?.picture ?? '');
    _banner = TextEditingController(text: c?.banner ?? '');
    _nip05 = TextEditingController(text: c?.nip05 ?? '');
    _lud16 = TextEditingController(text: c?.lud16 ?? '');
    _monero = TextEditingController(text: c?.moneroAddress ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    _picture.dispose();
    _banner.dispose();
    _nip05.dispose();
    _lud16.dispose();
    _monero.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pickImage({required bool forAvatar}) async {
    if ((forAvatar && _uploadingAvatar) || (!forAvatar && _uploadingBanner)) {
      return;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final bytes = picked.bytes ??
        (picked.path != null ? await _readPath(picked.path!) : null);

    if (bytes == null) {
      _message('Could not read the image.');
      return;
    }
    if (bytes.length > 5 * 1024 * 1024) {
      _message('Image is larger than 5 MB.');
      return;
    }

    final mime = _mimeFromExtension(picked.name);
    if (mime == null) {
      _message('Choose a PNG, JPG, or WebP image.');
      return;
    }

    setState(() {
      if (forAvatar) {
        _uploadingAvatar = true;
      } else {
        _uploadingBanner = true;
      }
    });

    try {
      final url = await BlossomUpload.upload(
        bytes: bytes,
        filename: picked.name,
        mimeType: mime,
        server: _blossomServer,
        identityService: widget.identityService,
      );
      if (!mounted) return;
      setState(() {
        if (forAvatar) {
          _picture.text = url;
        } else {
          _banner.text = url;
        }
      });
      _message('Image uploaded.');
    } catch (error) {
      _message(
        'Upload failed: ${error.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      if (mounted) {
        setState(() {
          if (forAvatar) {
            _uploadingAvatar = false;
          } else {
            _uploadingBanner = false;
          }
        });
      }
    }
  }

  Future<List<int>?> _readPath(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  String? _mimeFromExtension(String name) {
    final ext = name.toLowerCase().split('.').last;
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => null,
    };
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final name = _name.text.trim();
    final content = jsonEncode({
      'name': name,
      'display_name': name,
      'about': _about.text.trim(),
      'picture': _picture.text.trim(),
      'banner': _banner.text.trim(),
      'nip05': _nip05.text.trim(),
      'lud16': _lud16.text.trim(),
      'monero_address': _monero.text.trim(),
    });

    try {
      final event =
          await widget.identityService.signEvent(kind: 0, content: content);
      final results =
          await widget.relayService.publishEvent(event, widget.relays);
      if (!mounted) return;
      final okCount = results.values.where((v) => v == 'ok').length;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(okCount > 0
              ? 'Profile published to $okCount of ${results.length} relays'
              : 'No relay accepted the update'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in results.entries)
                Text('${Uri.tryParse(e.key)?.host ?? e.key}: ${e.value}'),
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
      Navigator.of(context).pop(okCount > 0);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _message('Could not sign or publish the profile.');
    }
  }

  Widget _bannerPreview(ThemeData theme) {
    final url = _banner.text.trim();
    if (widget.loadImages && url.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          height: 160,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _bannerPlaceholder(),
        ),
      );
    }
    return _bannerPlaceholder();
  }

  Widget _bannerPlaceholder() {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF4C1D95)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        widget.loadImages ? 'No banner yet' : 'Preview disabled (Privacy)',
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _avatarPreview() {
    final name = _name.text.trim().isEmpty ? 'MolStr' : _name.text.trim();
    return MolStrAvatar(
      name: name,
      picture: _picture.text.trim(),
      loadImages: widget.loadImages,
      radius: 40,
    );
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String hint, {
    bool multiline = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: !_saving,
        minLines: multiline ? 2 : 1,
        maxLines: multiline ? 4 : 1,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Banner', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _bannerPreview(theme),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _uploadingBanner || _saving
                    ? null
                    : () => _pickImage(forAvatar: false),
                icon: _uploadingBanner
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload),
                label: Text(_uploadingBanner ? 'Uploading…' : 'Upload banner'),
              ),
              if (_banner.text.trim().isNotEmpty)
                TextButton(
                  onPressed:
                      _saving ? null : () => setState(() => _banner.clear()),
                  child: const Text('Clear banner URL'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Avatar', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              _avatarPreview(),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _uploadingAvatar || _saving
                          ? null
                          : () => _pickImage(forAvatar: true),
                      icon: _uploadingAvatar
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload),
                      label: Text(
                        _uploadingAvatar ? 'Uploading…' : 'Upload avatar',
                      ),
                    ),
                    if (_picture.text.trim().isNotEmpty)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _picture.clear()),
                        child: const Text('Clear avatar URL'),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _field('Display name', _name, 'e.g. MolStr'),
          _field('About', _about, 'A short bio', multiline: true),
          _field('Picture URL', _picture, 'https://…/avatar.png'),
          _field('Banner URL', _banner, 'https://…/banner.png'),
          _field('NIP-05 identifier', _nip05, 'molstr@rizful.com'),
          _field('Lightning address (lud16)', _lud16, 'molstr@rizful.com'),
          _field('Monero address', _monero, '4… or 8…'),
          const SizedBox(height: 8),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: const Text('Advanced'),
              initiallyExpanded: _showAdvanced,
              onExpansionChanged: (open) =>
                  setState(() => _showAdvanced = open),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextField(
                    controller: TextEditingController(text: _blossomServer),
                    enabled: !_saving && !_uploadingAvatar && !_uploadingBanner,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Blossom server for image uploads',
                      hintText: 'https://blossom.primal.net',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => _blossomServer = value.trim(),
                  ),
                ),
              ],
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Publishes a public kind-0 metadata event to: '
                '${widget.relays.join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.publish),
            label: Text(_saving ? 'Publishing…' : 'Save profile'),
          ),
        ],
      ),
    );
  }
}
