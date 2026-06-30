import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../alg_structs.dart';
import '../database_manager.dart';
import '../l10n/app_localizations.dart';
import '../utils.dart';

// Lists every recorded attempt for one (algType, alg)
class AlgResultDetailsScreen extends StatefulWidget {
  final AlgType algType;
  final String alg;
  final int? sinceMs;

  const AlgResultDetailsScreen({
    super.key,
    required this.algType,
    required this.alg,
    this.sinceMs,
  });

  @override
  State<AlgResultDetailsScreen> createState() => _AlgResultDetailsScreenState();
}

class _AlgResultDetailsScreenState extends State<AlgResultDetailsScreen> {
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd  HH:mm:ss');

  List<AlgResult> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<AlgResult> results = await DatabaseManager()
        .getAlgResults(widget.algType, widget.alg, sinceMs: widget.sinceMs);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  void _confirmDelete(AlgResult result) async {
    bool confirmed = false;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deleteTimeConfirmTitle),
        content: Text(AppLocalizations.of(context)!.deleteTimeConfirmMessage),
        actions: [
          TextButton(
            child: Text(AppLocalizations.of(context)!.cancel),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: Text(AppLocalizations.of(context)!.delete),
            onPressed: () {
              confirmed = true;
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );

    if (confirmed) {
      DatabaseManager().deleteResult(result.id);
      setState(() {
        _results.removeWhere((r) => r.id == result.id);
      });
    }
  }

  Widget _buildRow(ThemeData theme, AlgResult result) {
    final date = DateTime.fromMillisecondsSinceEpoch(result.timestamp);
    return ListTile(
      title: Text(_dateFormat.format(date), style: theme.textTheme.labelLarge),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(timeToString(result.resultMs, fractionDigits: 2),
              style: theme.textTheme.labelLarge),
          IconButton(
            icon: Icon(Icons.delete),
            color: Colors.white,
            onPressed: () => _confirmDelete(result),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content;
    if (_loading) {
      content = Center(child: CircularProgressIndicator());
    } else if (_results.isEmpty) {
      content = Center(
        child: Text(AppLocalizations.of(context)!.noRecordedTimes,
            style: theme.textTheme.labelLarge),
      );
    } else {
      content = Card(
        color: Colors.black12,
        child: ListView.builder(
          itemCount: _results.length,
          itemBuilder: (context, index) => _buildRow(theme, _results[index]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      appBar: AppBar(
        title: Text(widget.alg),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 15),
        child: content,
      ),
    );
  }
}
