import 'package:flutter/material.dart';
import 'package:three_style_trainer/alg_provider.dart';
import 'package:three_style_trainer/alg_structs.dart';

import '../l10n/app_localizations.dart';

class LetterPairsListScreen extends StatefulWidget {
  final AlgProvider algProvider;

  const LetterPairsListScreen(this.algProvider, {super.key});

  @override
  State<LetterPairsListScreen> createState() => _LetterPairsListScreenState();
}

class _LetterPairsListScreenState extends State<LetterPairsListScreen> {
  final List<Alg> _algs = [];

  @override
  void initState() {
    super.initState();
    Alg? alg;
    while ((alg = widget.algProvider.getNextAlg()) != null) {
      _algs.add(alg!);
    }
    widget.algProvider.reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.practiceTypeLetterPairsList),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
        child: Card(
          color: Colors.black12,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 80.0,
              childAspectRatio: 2.0,
            ),
            itemCount: _algs.length,
            itemBuilder: (context, index) {
              return Center(
                child: Text(
                  _algs[index].name,
                  style: theme.textTheme.displaySmall,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
