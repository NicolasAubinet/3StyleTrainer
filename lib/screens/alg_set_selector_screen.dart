import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:three_style_trainer/alg_structs.dart';

import '../alg_provider.dart';
import 'timer_screen.dart';

class AlgSetSelectorScreen extends StatefulWidget {
  final double targetTime;
  final AlgType algType;

  AlgSetSelectorScreen(this.targetTime, this.algType);

  @override
  State<AlgSetSelectorScreen> createState() => _AlgSetSelectorScreenState();
}

class _AlgSetSelectorScreenState extends State<AlgSetSelectorScreen> {
  List<String> selectableAlgSets = [];
  Set<int> selectedIndexes = {};

  @override
  void initState() {
    super.initState();
    selectableAlgSets = getAlgSetWithoutBuffers();
  }

  AlgProvider getAlgProvider() {
    List<String> allAlgSets = getAlgSets(widget.algType);
    List<int> algSetIndices = [];
    // Convert indices to original alg set list that contains buffers
    for (int selectedIndex in selectedIndexes) {
      String algSet = selectableAlgSets[selectedIndex];
      int index = allAlgSets.indexOf(algSet);
      assert(index >= 0);
      algSetIndices.add(index);
    }
    return widget.algType == AlgType.Corner
        ? CornersAlgProvider(algSetIndices)
        : EdgesAlgProvider(algSetIndices);
  }

  void onAlgSetTap(int index) {
    setState(() {
      if (selectedIndexes.contains(index)) {
        selectedIndexes.remove(index);
      } else {
        selectedIndexes.add(index);
      }
    });
  }

  String getBuffer() {
    return widget.algType == AlgType.Corner ? "UFR" : "UF";
  }

  List<String> getAlgSetWithoutBuffers() {
    List<String> algSets = List.from(getAlgSets(widget.algType));

    List<int> bufferIndices = getBufferIndices(widget.algType, getBuffer());
    bufferIndices.sort((e1, e2) => e1.compareTo(e2));

    int deletedCount = 0;
    for (int bufferIndex in bufferIndices) {
      algSets.removeAt(bufferIndex - deletedCount);
      deletedCount++;
    }

    return algSets;
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.algSet),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppLocalizations.of(context)!.selectSetsToPractice,
              style: theme.textTheme.labelSmall,
            ),
            Expanded(
              child: ListView.builder(
                itemCount: selectableAlgSets.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Center(
                      child: Text(
                        selectableAlgSets[index],
                        style: selectedIndexes.contains(index)
                            ? theme.textTheme.displayMedium
                                ?.copyWith(color: Colors.black)
                            : theme.textTheme.displayMedium,
                      ),
                    ),
                    onTap: () => onAlgSetTap(index),
                    selected: selectedIndexes.contains(index),
                    selectedTileColor: theme.colorScheme.onPrimary,
                  );
                },
              ),
            ),
            ElevatedButton(
              child: Text(AppLocalizations.of(context)!.start),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TimerScreen(
                      widget.targetTime,
                      getAlgProvider(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
