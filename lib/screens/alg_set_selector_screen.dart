import 'package:flutter/material.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/practice_type.dart';
import 'package:three_style_trainer/widgets/custom_set_dialog.dart';

import '../alg_provider.dart';
import '../database_manager.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_palette.dart';
import '../theme/theme_scope.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/glass_panel.dart';
import 'timer_screen.dart';

class AlgSetSelectorScreen extends StatefulWidget {
  final double targetTime;
  final double raceTime;
  final AlgType algType;
  final List<CustomSet> customSets;
  final int algsShownInAdvance;
  final bool repeatUntilUnderTarget;

  AlgSetSelectorScreen(
      this.targetTime, this.raceTime, this.algType, this.algsShownInAdvance,
      {this.customSets = const [], this.repeatUntilUnderTarget = false});

  @override
  State<AlgSetSelectorScreen> createState() => _AlgSetSelectorScreenState();
}

class _AlgSetSelectorScreenState extends State<AlgSetSelectorScreen> {
  List<String> selectableAlgSets = [];
  Set<int> selectedIndices = {};
  bool invertedAlgs = false;

  // How many algs each set would drill, shown on its tile. Inverting doubles
  // them, so this is recomputed whenever the selection inputs change.
  List<int> algCountsPerSet = [];

  @override
  void initState() {
    super.initState();
    if (widget.algType == AlgType.Custom) {
      selectableAlgSets = widget.customSets.map((e) => e.name).toList();
    } else {
      selectableAlgSets = getAlgSetWithoutBuffers();
    }
    _recomputeAlgCounts();
  }

  void _recomputeAlgCounts() {
    if (widget.algType == AlgType.Custom) {
      algCountsPerSet =
          selectableAlgSets.map((name) => getCustomAlgSet(name).length).toList();
      return;
    }
    final allAlgSets = getAlgSets(widget.algType);
    algCountsPerSet = selectableAlgSets
        .map((set) => enumerateAlgs(widget.algType,
            setIndices: [allAlgSets.indexOf(set)],
            invertedAlgs: invertedAlgs).length)
        .toList();
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

    AlgProvider? algProvider;
    if (widget.algType == AlgType.Corner) {
      algProvider = CornersAlgProvider(
        setIndices: algSetIndices,
        invertedAlgs: invertedAlgs,
      );
    } else if (widget.algType == AlgType.Edge) {
      algProvider = EdgesAlgProvider(
        setIndices: algSetIndices,
        invertedAlgs: invertedAlgs,
      );
    } else if (widget.algType == AlgType.TwoFlip) {
      algProvider = TwoFlipsAlgProvider(
        setIndices: algSetIndices,
        invertedAlgs: invertedAlgs,
      );
    } else if (widget.algType == AlgType.TwoTwist) {
      algProvider = TwoTwistsAlgProvider(
        setIndices: algSetIndices,
        invertedAlgs: invertedAlgs,
      );
    } else if (widget.algType == AlgType.Parity) {
      algProvider = ParityAlgProvider(setIndices: algSetIndices);
    }
    assert(algProvider != null, "Alg type not supported");
    return algProvider!;
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

  bool get _allSelected =>
      selectableAlgSets.isNotEmpty &&
      selectedIndices.length == selectableAlgSets.length;

  // Number of algs the current selection would drill (nothing selected → 0).
  int get _algCount => selectedIndices.isEmpty ? 0 : getAlgProvider().totalAlgs;

  void _toggleSelectAll() {
    setState(() {
      if (_allSelected) {
        selectedIndices.clear();
      } else {
        selectedIndices = {
          for (int i = 0; i < selectableAlgSets.length; i++) i
        };
      }
    });
  }

  List<String> getAlgSetWithoutBuffers() {
    List<String> algSets = List.from(getAlgSets(widget.algType));

    Set<int> indicesToRemove = getBufferIndices(widget.algType).toSet();
    if (widget.algType == AlgType.TwoTwist) {
      // U/D facelets (0-3, 20-23) are the solved orientation, not twist targets.
      indicesToRemove.addAll([0, 1, 2, 3, 20, 21, 22, 23]);
    }

    final sortedIndices = indicesToRemove.toList()..sort();
    int deletedCount = 0;
    for (int index in sortedIndices) {
      algSets.removeAt(index - deletedCount);
      deletedCount++;
    }

    return algSets;
  }

  void _refreshSelectableAlgSets() {
    selectableAlgSets = widget.customSets.map((e) => e.name).toList();
    selectedIndices.clear();
    _recomputeAlgCounts();
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

  // The selected-row fill. With no checkbox, this tint is the whole selected
  // state, so the rows and the dividers between them must share it exactly.
  Color get _selectedTint => context.palette.accent.withValues(alpha: 0.22);

  /// One set as a row: its name and the algs it would drill. The accent tint is
  /// the whole selected state; custom sets also carry edit/delete.
  Widget _setRow(int index) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final selected = selectedIndices.contains(index);
    final isCustom = widget.algType == AlgType.Custom;
    return Material(
      color: selected ? _selectedTint : Colors.transparent,
      child: InkWell(
        onTap: () => onAlgSetTap(index),
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, isCustom ? 4 : 18, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectableAlgSets[index],
                    style: TextStyle(
                        fontFamily: isCustom ? null : MONO_FONT,
                        fontSize: isCustom ? 16 : 20,
                        fontWeight: FontWeight.w600,
                        color: selected ? p.textPrimary : p.textMuted),
                  ),
                ),
                Text(
                  l10n.setAlgCount(algCountsPerSet[index]),
                  style: TextStyle(
                      fontSize: 13,
                      color: selected ? p.textMuted : p.textFaint),
                ),
                if (isCustom) ...[
                  IconButton(
                    tooltip: l10n.editCustomSet,
                    onPressed: () => _editCustomSet(context, index),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    color: p.textMuted,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: l10n.delete,
                    onPressed: () => _onDeleteCustomSet(context, index),
                    icon: const Icon(Icons.delete_rounded, size: 18),
                    color: p.textMuted,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _blockButton(AppPalette p,
      {required String label,
      required bool filled,
      required VoidCallback onPressed}) {
    return Material(
      color: filled ? p.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: filled
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  border:
                      Border.all(color: p.accent.withValues(alpha: 0.55))),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: filled ? p.onAccent : p.accent)),
        ),
      ),
    );
  }

  void _onStartPressed() {
    if (selectedIndices.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.selectAtLeastOneSet),
        ));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TimerScreen(
          PracticeType.sets,
          widget.targetTime,
          widget.raceTime,
          getAlgProvider(),
          widget.algType,
          widget.algsShownInAdvance,
          repeatUntilUnderTarget: widget.repeatUntilUnderTarget,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final isCustom = widget.algType == AlgType.Custom;
    // Only letter-pair types have a direction to invert.
    final showInvertedOption =
        widget.algType == AlgType.Corner || widget.algType == AlgType.Edge;

    return AppScaffold(
      title: "${l10n.algSet} · ${widget.algType.getLocalizedName(context)}",
      actions: [
        IconButton(
          tooltip: _allSelected ? l10n.deselectAll : l10n.selectAll,
          icon: Icon(_allSelected
              ? Icons.remove_done_rounded
              : Icons.done_all_rounded),
          onPressed: _toggleSelectAll,
        ),
        const SizedBox(width: 4),
      ],
      // Capped and centred: full-desktop-width rows would strand the set name
      // an arm's length from its checkbox.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    l10n.selectSetsToPractice(
                        selectedIndices.length, _algCount),
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: GlassPanel(
                      padding: EdgeInsets.zero,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: selectableAlgSets.length,
                        // The divider is inset, so between two selected rows its
                        // margins would show untinted panel — carry the tint
                        // across the whole strip to keep the block continuous.
                        separatorBuilder: (_, index) => Container(
                          color: selectedIndices.contains(index) &&
                                  selectedIndices.contains(index + 1)
                              ? _selectedTint
                              : Colors.transparent,
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: p.panelBorder,
                            indent: 16,
                            endIndent: 16,
                          ),
                        ),
                        itemBuilder: (_, index) => _setRow(index),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // A side-setting, not a headline: a small trailing toggle rather
                // than a panel competing with Start.
                if (showInvertedOption)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.invertedAlgs,
                            style:
                                TextStyle(fontSize: 13, color: p.textMuted)),
                        const SizedBox(width: 4),
                        Transform.scale(
                          scale: 0.75,
                          child: Switch(
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            value: invertedAlgs,
                            onChanged: (value) => setState(() {
                              invertedAlgs = value;
                              _recomputeAlgCounts();
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _blockButton(p,
                          label: l10n.start,
                          filled: true,
                          onPressed: _onStartPressed),
                    ),
                    if (isCustom) ...[
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: l10n.createCustomSet,
                        onPressed: () => _createCustomSet(context),
                        icon: const Icon(Icons.add_box_rounded),
                        color: p.accent,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
