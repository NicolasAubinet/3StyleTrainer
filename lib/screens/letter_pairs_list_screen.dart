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
    const double crossAxisExtent = 80.0;
    const double childAspectRatio = 2.0;

    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.practiceTypeLetterPairsList),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
        child: Card(
          clipBehavior: Clip.antiAlias,
          color: Colors.black12,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final crossAxisCount =
                  (constraints.maxWidth / crossAxisExtent).ceil();
              final rowCount = (_algs.length / crossAxisCount).ceil();
              final itemHeight =
                  (constraints.maxWidth / crossAxisCount) / childAspectRatio;

              return ListView.builder(
                itemCount: rowCount,
                itemBuilder: (context, rowIndex) {
                  final List<Widget> rowChildren = [];
                  final startIndex = rowIndex * crossAxisCount;

                  for (int i = 0; i < crossAxisCount; i++) {
                    final itemIndex = startIndex + i;
                    if (itemIndex < _algs.length) {
                      rowChildren.add(
                        Expanded(
                          child: Center(
                            child: Text(
                              _algs[itemIndex].name,
                              style: theme.textTheme.displaySmall,
                            ),
                          ),
                        ),
                      );
                    } else {
                      rowChildren.add(Expanded(child: Container()));
                    }
                  }

                  return Container(
                    color:
                        rowIndex.isEven ? Colors.transparent : Colors.black26,
                    height: itemHeight,
                    child: Row(
                      children: rowChildren,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
