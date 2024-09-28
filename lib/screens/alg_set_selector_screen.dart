import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/practice_type.dart';

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
  Set<int> selectedIndices = {};
  bool inversedAlgs = false;

  @override
  void initState() {
    super.initState();
    selectableAlgSets = getAlgSetWithoutBuffers();
  }

  AlgProvider getAlgProvider() {
    List<String> allAlgSets = getAlgSets(widget.algType);
    List<int> algSetIndices = [];
    // Convert indices to original alg set list that contains buffers
    for (int selectedIndex in selectedIndices) {
      String algSet = selectableAlgSets[selectedIndex];
      int index = allAlgSets.indexOf(algSet);
      assert(index >= 0);
      algSetIndices.add(index);
    }
    return widget.algType == AlgType.Corner
        ? CornersAlgProvider(
            setIndices: algSetIndices,
            inversedAlgs: inversedAlgs,
          )
        : EdgesAlgProvider(
            setIndices: algSetIndices,
            inversedAlgs: inversedAlgs,
          );
  }

  void onAlgSetTap(int index) {
    setState(() {
      if (selectedIndices.contains(index)) {
        selectedIndices.remove(index);
      } else {
        selectedIndices.add(index);
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
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppLocalizations.of(context)!
                  .selectSetsToPractice(selectedIndices.length),
              style: theme.textTheme.labelSmall,
            ),
            SizedBox(height: 5),
            Expanded(
              child: Card(
                color: Colors.black12,
                child: ListView.builder(
                  itemCount: selectableAlgSets.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      title: Center(
                        child: Text(
                          selectableAlgSets[index],
                          style: selectedIndices.contains(index)
                              ? theme.textTheme.displayMedium
                                  ?.copyWith(color: Colors.black)
                              : theme.textTheme.displayMedium,
                        ),
                      ),
                      onTap: () => onAlgSetTap(index),
                      selected: selectedIndices.contains(index),
                      selectedTileColor: theme.colorScheme.onPrimary,
                    );
                  },
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  AppLocalizations.of(context)!.inversedAlgs,
                  style: theme.textTheme.labelSmall,
                ),
                Checkbox(
                    value: inversedAlgs,
                    onChanged: (bool? newValue) {
                      setState(() {
                        inversedAlgs = newValue!;
                      });
                    }),
              ],
            ),
            SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                fixedSize: Size(315, 60),
                padding: EdgeInsets.all(2),
              ),
              onPressed: () {
                if (selectedIndices.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          AppLocalizations.of(context)!.selectAtLeastOneSet),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TimerScreen(
                        PracticeType.sets,
                        widget.targetTime,
                        getAlgProvider(),
                        widget.algType,
                      ),
                    ),
                  );
                }
              },
              child: Text(
                AppLocalizations.of(context)!.start,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
