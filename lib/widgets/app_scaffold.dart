import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// Scaffold with the palette's gradient background and a transparent app bar.
/// Every screen uses this so the background is consistent across the app.
class AppScaffold extends StatelessWidget {
  final String? title;
  final List<Widget>? actions;
  final Widget body;
  final bool showBack;
  final Widget? leading;
  final double? leadingWidth;

  const AppScaffold({
    super.key,
    this.title,
    this.actions,
    required this.body,
    this.showBack = true,
    this.leading,
    this.leadingWidth,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: p.bgGradient,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: title == null
            ? null
            : AppBar(
                automaticallyImplyLeading: showBack && leading == null,
                leading: leading,
                leadingWidth: leadingWidth,
                title: Text(title!),
                actions: actions,
              ),
        body: SafeArea(top: title == null, child: body),
      ),
    );
  }
}
