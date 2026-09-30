import 'package:flutter/material.dart';

/// Web/iOS-macOS-variant: updaten-in-place bestaat alleen op Windows
/// (zie windows_update.dart, dat dart:io gebruikt).
class WindowsUpdate {
  static bool get canReplaceInPlace => false;

  static Future<bool> install(
      BuildContext context, String url, String versie, String notes) async {
    return false;
  }
}
