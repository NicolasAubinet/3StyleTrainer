import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/practice_type.dart';
import 'package:three_style_trainer/widgets/custom_set_dialog.dart';

import '../alg_provider.dart';
import '../database_manager.dart';
import 'timer_screen.dart';

class AlgSetSelectorScreen extends StatefulWidget {
  final double targetTime;
  final AlgType algType;
  final List<CustomSet> customSets;

  AlgSetSelectorScreen(this.targetTime, this.algType,
      {this.customSets = const []});

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
    if (widget.algType == AlgType.Custom) {
      selectableAlgSets = widget.customSets.map((e) => e.name).toList();
    } else {
      selectableAlgSets = getAlgSetWithoutBuffers();
    }
  }

  AlgProvider getAlgProvider() {
    if (widget.algType == AlgType.Custom) {
      List<String> algs = [];
      for (int selectedIndex in selectedIndices) {
        String setName = selectableAlgSets[selectedIndex];
        List<String> setAlgs = getCustomAlgSet(setName);
        algs.addAll(setAlgs);
      }
      return CustomProvider(algs);
    }

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

  List<String> getCustomAlgSet(String customSetName) {
    assert(widget.algType == AlgType.Custom);
    for (CustomSet set in widget.customSets) {
      if (set.name == customSetName) {
        return set.algs;
      }
    }
    return [];
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

  void _refreshSelectableAlgSets() {
    selectableAlgSets = widget.customSets.map((e) => e.name).toList();
    selectedIndices.clear();
  }

  bool _onCustomSetCreated(CustomSet customSet) {
    String errorMessage = "";
    if (customSet.name.isEmpty) {
      errorMessage = AppLocalizations.of(context)!.emptyCustomSetName;
    }
    if (selectableAlgSets.contains(customSet.name)) {
      errorMessage = AppLocalizations.of(context)!.customSetNameAlreadyExists;
    }
    if (customSet.algs.isEmpty) {
      errorMessage = AppLocalizations.of(context)!.customSetNoAlgs;
    }

    if (errorMessage.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
        ),
      );
      return false;
    }

    setState(() {
      DatabaseManager().insertCustomSet(customSet);
      widget.customSets.add(customSet);
      _refreshSelectableAlgSets();
    });

    return true;
  }

  bool _onCustomSetEdited(String oldName, CustomSet customSet) {
    String errorMessage = "";
    if (customSet.name.isEmpty) {
      errorMessage = AppLocalizations.of(context)!.emptyCustomSetName;
    }
    if (customSet.algs.isEmpty) {
      errorMessage = AppLocalizations.of(context)!.customSetNoAlgs;
    }

    if (errorMessage.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
        ),
      );
      return false;
    }

    setState(() {
      DatabaseManager().updateCustomSet(oldName, customSet);
      for (CustomSet set in widget.customSets) {
        if (set.name == oldName) {
          set.name = customSet.name;
          set.algs = customSet.algs;
        }
      }
      _refreshSelectableAlgSets();
    });

    return true;
  }

  void _onDeleteCustomSet(BuildContext context, int index) async {
    String setName = selectableAlgSets[index];
    bool confirmed = false;

    await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title:
                Text(AppLocalizations.of(context)!.deleteCustomSetConfirmTitle),
            content: Text(AppLocalizations.of(context)!
                .deleteCustomSetConfirmMessage(setName)),
            actions: <Widget>[
              TextButton(
                style: TextButton.styleFrom(
                  textStyle: Theme.of(context).textTheme.labelLarge,
                ),
                child: Text(AppLocalizations.of(context)!.cancel),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                style: TextButton.styleFrom(
                  textStyle: Theme.of(context).textTheme.labelLarge,
                ),
                child: Text(AppLocalizations.of(context)!.delete),
                onPressed: () {
                  confirmed = true;
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        });

    if (confirmed) {
      setState(() {
        DatabaseManager().deleteCustomSet(setName);
        widget.customSets.removeWhere((set) {
          return set.name == setName;
        });
        _refreshSelectableAlgSets();
      });
    }
  }

  void _editCustomSet(BuildContext context, int index) async {
    CustomSet set = widget.customSets[index];
    String oldName = set.name;
    return showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return CustomSetDialog.edit((set) {
            return _onCustomSetEdited(oldName, set);
          }, set);
        });
  }

  Future<void> _createCustomSet(BuildContext context) {
    return showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return CustomSetDialog.create(_onCustomSetCreated);
        });
  }

  Widget getAlgSetsItemBuilder(BuildContext context, int index) {
    var theme = Theme.of(context);
    return ListTile(
      title: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Center(
                child: Text(
                  selectableAlgSets[index],
                  style: selectedIndices.contains(index)
                      ? theme.textTheme.displayMedium
                          ?.copyWith(color: Colors.black)
                      : theme.textTheme.displayMedium,
                ),
              ),
            ),
            widget.algType == AlgType.Custom
                ? IconButton(
                    onPressed: () => {_editCustomSet(context, index)},
                    icon: Icon(Icons.edit),
                    color: selectedIndices.contains(index)
                        ? Colors.black
                        : Colors.white,
                  )
                : Container(),
            widget.algType == AlgType.Custom
                ? IconButton(
                    onPressed: () => {_onDeleteCustomSet(context, index)},
                    icon: Icon(Icons.delete),
                    color: selectedIndices.contains(index)
                        ? Colors.black
                        : Colors.white,
                  )
                : Container(),
          ],
        ),
      ),
      onTap: () => onAlgSetTap(index),
      selected: selectedIndices.contains(index),
      selectedTileColor: theme.colorScheme.onPrimary,
    );
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
                  itemBuilder: getAlgSetsItemBuilder,
                ),
              ),
            ),
            widget.algType == AlgType.Custom
                ? Container()
                : Row(
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
            SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    fixedSize: Size(270, 60),
                    padding: EdgeInsets.all(2),
                  ),
                  onPressed: () {
                    if (selectedIndices.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLocalizations.of(context)!
                              .selectAtLeastOneSet),
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
                widget.algType == AlgType.Custom
                    ? IconButton(
                        onPressed: () => _createCustomSet(context),
                        icon: const Icon(Icons.add_box_outlined),
                        color: Colors.white,
                      )
                    : Container(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
