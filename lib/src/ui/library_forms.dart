import 'package:flutter/material.dart';

import '../copy/zh.dart';
import '../failure.dart';
import '../format.dart';
import '../model/models.dart';
import '../state/app_controller.dart';
import '../subsonic/url_rules.dart';

class LibraryFormPage extends StatefulWidget {
  const LibraryFormPage({super.key, required this.controller, this.existing});

  final AppController controller;
  final LibraryRecord? existing;

  @override
  State<LibraryFormPage> createState() => _LibraryFormPageState();
}

class _LibraryFormPageState extends State<LibraryFormPage> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _username;
  late final TextEditingController _password;
  bool _trust = false;
  bool _busy = false;
  bool _httpAccepted = false;
  bool _saved = false;
  String? _error;
  ProbeResult? _pending;
  String? _pendingPassword;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _address = TextEditingController(text: existing?.baseUrl ?? '');
    _username = TextEditingController(text: existing?.username ?? '');
    _password = TextEditingController();
    _trust = existing?.certFingerprint != null;
  }

  @override
  void dispose() {
    if (_pending != null && !_saved) widget.controller.rebind();
    _name.dispose();
    _address.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect({bool trust = false}) async {
    final username = _username.text.trim();
    if (username.isEmpty) {
      setState(() => _error = Zh.missingUsername);
      return;
    }
    var secret = _password.text;
    if (secret.isEmpty) {
      final existing = widget.existing;
      if (existing == null) {
        setState(() => _error = Zh.missingPassword);
        return;
      }
      secret = await widget.controller.passwordFor(existing.id) ?? '';
      if (secret.isEmpty) {
        setState(() => _error = Zh.missingPassword);
        return;
      }
    }
    late final NormalizedUrl normalized;
    try {
      normalized = normalizeBaseUrl(_address.text);
    } on AppFailure catch (error) {
      setState(() => _error = error.message);
      return;
    }
    if (!mounted) return;
    if (normalized.http && !_httpAccepted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(Zh.address),
          content: const Text(Zh.httpWarning),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(Zh.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text(Zh.continueAnyway)),
          ],
        ),
      );
      if (proceed != true) return;
      _httpAccepted = true;
    }
    setState(() {
      _busy = true;
      _error = null;
      _trust = trust || _trust;
    });
    try {
      final probe = await widget.controller.probe(
        url: normalized.base,
        username: username,
        password: secret,
        trustCertificate: _trust,
        pinnedFingerprint: _trust ? null : widget.existing?.certFingerprint,
      );
      if (!mounted) return;
      if (probe.folders.length > 1) {
        setState(() {
          _busy = false;
          _pending = probe;
          _pendingPassword = secret;
        });
        return;
      }
      await _save(probe, secret, null);
    } on AppFailure catch (error) {
      if (!mounted) return;
      widget.controller.rebind();
      if (error.kind == FailureKind.certificateUntrusted || error.kind == FailureKind.certificateChanged) {
        setState(() => _busy = false);
        final allow = await _askTrust(error);
        if (allow && mounted) await _connect(trust: true);
        return;
      }
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      widget.controller.rebind();
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  Future<bool> _askTrust(AppFailure error) async {
    final fingerprint = error.fingerprint == null ? '' : formatFingerprint(error.fingerprint!);
    final changed = error.kind == FailureKind.certificateChanged;
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(changed ? Zh.certChangedTitle : Zh.certUntrusted),
        content: Text(fingerprint.isEmpty ? error.message : '${error.message}\n\n${Zh.fingerprint}\n$fingerprint'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(Zh.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(Zh.trustNewCert),
          ),
        ],
      ),
    );
    return allow == true;
  }

  Future<void> _save(ProbeResult probe, String password, String? folderId) async {
    setState(() => _busy = true);
    try {
      await widget.controller.saveLibrary(
        id: widget.existing?.id,
        name: _name.text,
        url: probe.url,
        username: _username.text.trim(),
        password: password,
        info: probe.info,
        musicFolderId: folderId,
        fingerprint: probe.fingerprint,
        createdAt: widget.existing?.createdAt,
      );
      _saved = true;
      if (mounted) Navigator.of(context).pop();
    } on AppFailure catch (error) {
      if (!mounted) return;
      widget.controller.rebind();
      setState(() {
        _busy = false;
        _error = error.message;
        _pending = null;
      });
    } catch (error) {
      if (!mounted) return;
      widget.controller.rebind();
      setState(() {
        _busy = false;
        _error = describeError(error);
        _pending = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final pending = _pending;
    return Scaffold(
      appBar: AppBar(title: Text(existing == null ? Zh.addLibrary : Zh.editLibrary)),
      body: pending == null ? _form(existing) : _folders(pending),
    );
  }

  Widget _form(LibraryRecord? existing) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: Zh.displayName, hintText: Zh.displayNameHint)),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: Zh.address, hintText: Zh.addressHint),
        ),
        const SizedBox(height: 12),
        TextField(controller: _username, decoration: const InputDecoration(labelText: Zh.username)),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: InputDecoration(labelText: Zh.password, hintText: existing == null ? null : Zh.passwordKeep),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _trust,
          onChanged: _busy ? null : (value) => setState(() => _trust = value ?? false),
          title: const Text(Zh.trustCert),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, height: 1.4)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : () => _connect(),
          child: Text(_busy ? Zh.connecting : (existing == null ? Zh.connect : Zh.save)),
        ),
      ],
    );
  }

  Widget _folders(ProbeResult probe) {
    final notes = <Widget>[
      if (probe.info.unrecognized) const WarningLine(Zh.unrecognizedServer),
      if (!probe.info.hasTranscoding) const WarningLine(Zh.noTranscoding),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(Zh.chooseFolder, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...notes,
        ListTile(
          leading: const Icon(Icons.all_inclusive),
          title: const Text(Zh.allFolders),
          onTap: _busy ? null : () => _save(probe, _pendingPassword ?? '', null),
        ),
        for (final folder in probe.folders)
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(folder.name.isEmpty ? folder.id : folder.name),
            onTap: _busy ? null : () => _save(probe, _pendingPassword ?? '', folder.id),
          ),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      ],
    );
  }
}

class WarningLine extends StatelessWidget {
  const WarningLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.tertiary)),
    );
  }
}

class MePage extends StatelessWidget {
  const MePage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final gainReady = controller.player.supportsReplayGain;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Row(
          children: [
            Expanded(child: Text(Zh.libraries, style: Theme.of(context).textTheme.titleMedium)),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => LibraryFormPage(controller: controller)),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text(Zh.addLibrary),
            ),
          ],
        ),
        if (controller.libraries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(Zh.noLibraryBody),
          ),
        for (final library in controller.libraries)
          Card(
            child: ListTile(
              leading: Icon(controller.current?.id == library.id ? Icons.check_circle : Icons.circle_outlined),
              title: Text(library.name),
              subtitle: Text(_subtitle(library)),
              onTap: () => controller.switchTo(library.id),
              trailing: PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'edit') {
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) => LibraryFormPage(controller: controller, existing: library),
                      ),
                    );
                  } else if (action == 'delete') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text(Zh.deleteLibraryTitle),
                        content: const Text(Zh.deleteLibraryBody),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(Zh.cancel)),
                          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text(Zh.delete)),
                        ],
                      ),
                    );
                    if (ok == true) await controller.deleteLibrary(library.id);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text(Zh.editLibrary)),
                  PopupMenuItem(value: 'delete', child: Text(Zh.delete)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 18),
        Text(Zh.quality, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(Zh.qualityHelp, style: Theme.of(context).textTheme.bodySmall),
        RadioGroup<QualityMode>(
          groupValue: settings.quality,
          onChanged: _quality,
          child: const Column(
            children: [
              RadioListTile<QualityMode>(value: QualityMode.auto, title: Text(Zh.qualityAuto)),
              RadioListTile<QualityMode>(value: QualityMode.original, title: Text(Zh.qualityOriginal)),
              RadioListTile<QualityMode>(value: QualityMode.saver, title: Text(Zh.qualitySaver)),
            ],
          ),
        ),
        const Divider(),
        SwitchListTile(
          title: const Text(Zh.replayGain),
          subtitle: Text(gainReady ? Zh.replayGainHelp : Zh.replayGainUnavailable),
          value: gainReady && settings.replayGain,
          onChanged: gainReady ? (value) => controller.updateSettings(settings.copyWith(replayGain: value)) : null,
        ),
        SwitchListTile(
          title: const Text(Zh.playbackCache),
          subtitle: const Text(Zh.playbackCacheHelp),
          value: settings.cacheEnabled,
          onChanged: (value) => controller.updateSettings(settings.copyWith(cacheEnabled: value)),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: controller.clearPlaybackCache, child: const Text(Zh.clearCache)),
        const SizedBox(height: 18),
        Text(Zh.lrcApi, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(Zh.lrcApiHelp, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        _LrcApiField(controller: controller),
      ],
    );
  }

  void _quality(QualityMode? value) {
    if (value == null) return;
    controller.updateSettings(controller.settings.copyWith(quality: value));
  }

  String _subtitle(LibraryRecord library) {
    final notes = <String>[library.baseUrl];
    if (controller.current?.id == library.id) notes.add(Zh.currentLibrary);
    if (library.unrecognized) notes.add(Zh.unrecognizedServer);
    if (!library.hasTranscoding) notes.add(Zh.noTranscoding);
    return notes.join(' · ');
  }
}

class _LrcApiField extends StatefulWidget {
  const _LrcApiField({required this.controller});

  final AppController controller;

  @override
  State<_LrcApiField> createState() => _LrcApiFieldState();
}

class _LrcApiFieldState extends State<_LrcApiField> {
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.controller.settings.lrcApiBase);
    widget.controller.addListener(_sync);
  }

  void _sync() {
    if (_focus.hasFocus) return;
    final next = widget.controller.settings.lrcApiBase;
    if (_text.text == next) return;
    _text.text = next;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _text.text.trim();
    _text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    final settings = widget.controller.settings;
    if (settings.lrcApiBase != value) {
      await widget.controller.updateSettings(settings.copyWith(lrcApiBase: value));
    }
    if (!mounted) return;
    widget.controller.toast(Zh.saved);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _text,
          focusNode: _focus,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(hintText: Zh.lrcApiHint),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(onPressed: _save, child: const Text(Zh.save)),
        ),
      ],
    );
  }
}
