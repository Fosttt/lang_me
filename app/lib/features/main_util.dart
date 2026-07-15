import 'package:flutter/material.dart';

import '../main.dart';

/// Replace the whole navigation stack with the home shell.
void goHome(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const HomeShell()),
    (_) => false,
  );
}
