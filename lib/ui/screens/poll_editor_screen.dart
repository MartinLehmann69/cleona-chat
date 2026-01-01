import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_types.dart';

/// Full-screen poll composer (§24.6). Launched from the chat action menu
/// of a group or channel. Submits via [ICleonaService.createPoll] and
/// pops once the poll has been created locally.
class PollEditorScreen extends StatefulWidget {
  final String conversationId;
  final bool isGroup;
  final bool isChannel;

  const PollEditorScreen({
    super.key,
    required this.conversationId,
    required this.isGroup,
    required this.isChannel,
  });

  @override
  State<PollEditorScreen> createState() => _PollEditorScreenState();
}

class _PollEditorScreenState extends State<PollEditorScreen> {
  final _question = TextEditingController();
  final _description = TextEditingController();
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<_DateOption> _dateOptions = [];

  PollType _type = PollType.singleChoice;
  bool _anonymous = false;
  bool _allowChange = true;
  bool _showResultsBeforeClose = true;
  DateTime? _deadline;
  int _scaleMin = 1;
  int _scaleMax = 5;
  int _maxChoices = 0;

  bool _submitting = false;

  @override
  void dispose() {
    _question.dispose();
    _description.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(locale.get('poll_create_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _submitting ? null : _submit,
            tooltip: locale.get('poll_create'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _question,
              decoration: InputDecoration(
                labelText: locale.get('poll_question'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: locale.get('poll_description_optional'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _typeSelector(locale),
            const SizedBox(height: 16),
            if (_type == PollType.singleChoice ||
                _type == PollType.multipleChoice)
              _choiceEditor(locale),
            if (_type == PollType.datePoll) _dateEditor(locale),
            if (_type == PollType.scale) _scaleEditor(locale),
            const SizedBox(height: 24),
            _settingsBlock(locale),
          ],
        ),
      ),
    );
  }

  Widget _typeSelector(AppLocale locale) {
    return Wrap(
      spacing: 8,
      children: [
        for (final t in PollType.values)
          ChoiceChip(
            label: Text(locale.get(_typeLabelKey(t))),
            selected: _type == t,
            onSelected: (_) => setState(() => _type = t),
          ),
      ],
    );
  }

  Widget _choiceEditor(AppLocale locale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(locale.get('poll_options'), style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (var i = 0; i < _options.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _options[i],
                    decoration: InputDecoration(
                      labelText: locale.tr('poll_option_label', {'index': '${i + 1}'}),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_options.length > 2)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() {
                      _options[i].dispose();
                      _options.removeAt(i);
                    }),
                  ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: Text(locale.get('poll_add_option')),
            onPressed: () => setState(() => _options.add(TextEditingController())),
          ),
        ),
      ],
    );
  }

  Widget _dateEditor(AppLocale locale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(locale.get('poll_date_slots'), style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (var i = 0; i < _dateOptions.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(_dateOptions[i].label),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() => _dateOptions.removeAt(i)),
                ),
              ],
            ),
          ),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: Text(locale.get('poll_add_date_slot')),
          onPressed: _pickDateSlot,
        ),
      ],
    );
  }

  Future<void> _pickDateSlot() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    if (!mounted) return;
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (start == null) return;
    if (!mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute),
    );
    if (end == null) return;

    final startMs = DateTime(date.year, date.month, date.day, start.hour, start.minute).millisecondsSinceEpoch;
    final endMs = DateTime(date.year, date.month, date.day, end.hour, end.minute).millisecondsSinceEpoch;
    setState(() {
      _dateOptions.add(_DateOption(startMs: startMs, endMs: endMs));
    });
  }

  Widget _scaleEditor(AppLocale locale) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            decoration: InputDecoration(labelText: locale.get('poll_scale_min')),
            keyboardType: TextInputType.number,
            controller: TextEditingController(text: '$_scaleMin'),
            onChanged: (v) => _scaleMin = int.tryParse(v) ?? 1,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            decoration: InputDecoration(labelText: locale.get('poll_scale_max')),
            keyboardType: TextInputType.number,
            controller: TextEditingController(text: '$_scaleMax'),
            onChanged: (v) => _scaleMax = int.tryParse(v) ?? 5,
          ),
        ),
      ],
    );
  }

  Widget _settingsBlock(AppLocale locale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(locale.get('poll_settings'), style: const TextStyle(fontWeight: FontWeight.bold)),
        SwitchListTile(
          title: Text(locale.get('poll_anonymous')),
          subtitle: Text(locale.get('poll_anonymous_hint')),
          value: _anonymous,
          onChanged: (v) => setState(() => _anonymous = v),
        ),
        SwitchListTile(
          title: Text(locale.get('poll_allow_vote_change')),
          value: _allowChange,
          onChanged: (v) => setState(() => _allowChange = v),
        ),
        SwitchListTile(
          title: Text(locale.get('poll_show_results_before_close')),
          value: _showResultsBeforeClose,
          onChanged: (v) => setState(() => _showResultsBeforeClose = v),
        ),
        ListTile(
          title: Text(locale.get('poll_deadline')),
          subtitle: Text(_deadline == null
              ? locale.get('poll_no_deadline')
              : '${_deadline!.day}.${_deadline!.month}.${_deadline!.year}'),
          trailing: const Icon(Icons.event),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: DateTime.now().add(const Duration(days: 7)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (d != null) setState(() => _deadline = d);
          },
        ),
        if (_type == PollType.multipleChoice)
          TextField(
            decoration: InputDecoration(labelText: locale.get('poll_max_choices')),
            keyboardType: TextInputType.number,
            controller: TextEditingController(text: '$_maxChoices'),
            onChanged: (v) => _maxChoices = int.tryParse(v) ?? 0,
          ),
      ],
    );
  }

  Future<void> _submit() async {
    final locale = AppLocale.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final service = context.read<CleonaAppState>().service;
    if (service == null) return;

    final q = _question.text.trim();
    if (q.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(locale.get('poll_question_required'))));
      return;
    }

    List<PollOption> options;
    switch (_type) {
      case PollType.singleChoice:
      case PollType.multipleChoice:
        options = [
          for (var i = 0; i < _options.length; i++)
            if (_options[i].text.trim().isNotEmpty)
              PollOption(optionId: i, label: _options[i].text.trim()),
        ];
        if (options.length < 2) {
          messenger.showSnackBar(SnackBar(content: Text(locale.get('poll_needs_two_options'))));
          return;
        }
        break;
      case PollType.datePoll:
        options = [
          for (var i = 0; i < _dateOptions.length; i++)
            PollOption(
              optionId: i,
              label: _dateOptions[i].label,
              dateStart: _dateOptions[i].startMs,
              dateEnd: _dateOptions[i].endMs,
            ),
        ];
        if (options.isEmpty) {
          messenger.showSnackBar(SnackBar(content: Text(locale.get('poll_needs_date_slot'))));
          return;
        }
        break;
      case PollType.scale:
        if (_scaleMin >= _scaleMax) {
          messenger.showSnackBar(SnackBar(content: Text(locale.get('poll_scale_invalid'))));
          return;
        }
        options = [
          for (var v = _scaleMin; v <= _scaleMax; v++)
            PollOption(optionId: v, label: '$v'),
        ];
        break;
      case PollType.freeText:
        options = [];
        break;
    }

    setState(() => _submitting = true);
    try {
      await service.createPoll(
        question: q,
        description: _description.text.trim(),
        pollType: _type,
        options: options,
        settings: PollSettings(
          anonymous: _anonymous,
          deadline: _deadline == null ? 0 : _deadline!.millisecondsSinceEpoch,
          allowVoteChange: _allowChange,
          showResultsBeforeClose: _showResultsBeforeClose,
          maxChoices: _maxChoices,
          scaleMin: _scaleMin,
          scaleMax: _scaleMax,
        ),
        groupIdHex: widget.conversationId,
      );
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _typeLabelKey(PollType t) {
    switch (t) {
      case PollType.singleChoice: return 'poll_type_single';
      case PollType.multipleChoice: return 'poll_type_multiple';
      case PollType.datePoll: return 'poll_type_date';
      case PollType.scale: return 'poll_type_scale';
      case PollType.freeText: return 'poll_type_free_text';
    }
  }
}

class _DateOption {
  final int startMs;
  final int endMs;
  _DateOption({required this.startMs, required this.endMs});

  String get label {
    final s = DateTime.fromMillisecondsSinceEpoch(startMs);
    final e = DateTime.fromMillisecondsSinceEpoch(endMs);
    String fmt(DateTime d) => '${d.day}.${d.month}. ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${fmt(s)} – ${fmt(e)}';
  }
}
