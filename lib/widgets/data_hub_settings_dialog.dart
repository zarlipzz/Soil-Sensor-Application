import 'dart:async';

import '../utils/app_language.dart';

import 'package:flutter/material.dart';

import '../services/home_assistant_service.dart';

class DataHubSettingsDialog extends StatefulWidget {
  const DataHubSettingsDialog({
    super.key,
    required this.service,
    required this.settings,
  });

  final HomeAssistantService service;
  final DataHubSettings settings;

  @override
  State<DataHubSettingsDialog> createState() => _DataHubSettingsDialogState();
}

class _DataHubSettingsDialogState extends State<DataHubSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _url = TextEditingController(text: widget.settings.url);
  late final _apiKey = TextEditingController(text: widget.settings.apiKey);
  bool _saving = false;
  bool _testing = false;
  String? _error;
  String? _success;

  bool get _busy => _saving || _testing;
  DataHubSettings get _settings =>
      DataHubSettings(url: _url.text.trim(), apiKey: _apiKey.text.trim());

  void _clearFeedback() {
    if (_error == null && _success == null) return;
    setState(() {
      _error = null;
      _success = null;
    });
  }

  Future<void> _test() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _error = null;
      _success = null;
    });

    String? error;
    String? success;
    try {
      final status = await widget.service.testConnection(_settings);
      if (!mounted) return;
      if (status >= 200 && status < 300) {
        success = context.tr(
          'Data Hub รับค่าทดสอบแล้ว (HTTP $status)',
          'Data Hub received the test reading (HTTP $status)',
        );
      } else {
        error = switch (status) {
          401 || 403 => context.tr(
            'Data Hub ไม่อนุญาตให้ส่งข้อมูล กรุณาตรวจ API key',
            'Data Hub rejected the request. Check the API key.',
          ),
          404 => context.tr(
            'ไม่พบปลายทาง กรุณาตรวจ URL ของ Device API',
            'Endpoint not found. Check the Device API URL.',
          ),
          _ => context.tr(
            'Data Hub ไม่รับค่าทดสอบ (HTTP $status)',
            'Data Hub rejected the test reading (HTTP $status)',
          ),
        };
      }
    } on TimeoutException {
      if (!mounted) return;
      error = context.tr(
        'หมดเวลารอคำตอบจาก Data Hub',
        'Data Hub did not respond in time',
      );
    } catch (_) {
      if (!mounted) return;
      error = context.tr(
        'เชื่อมต่อ Data Hub ไม่ได้ กรุณาตรวจ URL และเครือข่าย',
        'Could not connect to Data Hub. Check the URL and connection.',
      );
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _error = error;
      _success = success;
    });
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final settings = _settings;
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    var saved = false;
    try {
      saved = await widget.service.saveCredentials(settings);
    } catch (_) {
      // Show a local save error without exposing the credentials.
    }
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = context.tr(
        'บันทึกการตั้งค่าไม่สำเร็จ',
        'Could not save settings',
      );
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PopScope(canPop: !_saving, child: _buildDialog(context));

  Widget _buildDialog(BuildContext context) => AlertDialog(
    title: Text(context.tr('ตั้งค่า Data Hub', 'Data Hub settings')),
    scrollable: true,
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _url,
            enabled: !_busy,
            onChanged: (_) => _clearFeedback(),
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Device API URL'),
            validator: (value) =>
                DataHubSettings.parseEndpoint(value ?? '') == null
                ? context.tr(
                    'ระบุ URL ที่ขึ้นต้นด้วย http:// หรือ https://',
                    'Enter a URL beginning with http:// or https://',
                  )
                : null,
          ),
          TextFormField(
            controller: _apiKey,
            enabled: !_busy,
            onChanged: (_) => _clearFeedback(),
            keyboardType: TextInputType.visiblePassword,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'API key'),
            validator: (value) => (value ?? '').trim().isEmpty
                ? context.tr(
                    'ระบุ API key จากหน้า Device API',
                    'Enter the API key from the Device API page',
                  )
                : null,
          ),
          if ((_error ?? _success) case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  style: TextStyle(
                    color: _error == null
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: Text(context.tr('ยกเลิก', 'Cancel')),
      ),
      OutlinedButton(
        onPressed: _busy ? null : _test,
        child: Text(
          _testing
              ? context.tr('กำลังทดสอบ…', 'Testing…')
              : context.tr('ทดสอบการเชื่อมต่อ', 'Test connection'),
        ),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(context.tr('บันทึก', 'Save')),
      ),
    ],
  );
}
