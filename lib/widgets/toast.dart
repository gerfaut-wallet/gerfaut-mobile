import 'package:flutter/material.dart';

/// A benign confirmation — "Copied", "Setting saved" — gone after three
/// seconds, as on the desktop app. Never for an error or an alert: what
/// matters does not go away by itself.
class Toast extends SnackBar {
  Toast(String message, {super.key})
    : super(content: Text(message), duration: toastDuration);
}

/// How long a toast stays.
const Duration toastDuration = Duration(seconds: 3);
