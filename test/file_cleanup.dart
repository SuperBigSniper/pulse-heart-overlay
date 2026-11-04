import 'dart:io';

/// Removes a temporary test directory, tolerating the transient file locks
/// Windows applies to freshly written files.
///
/// On Windows CI runners, antivirus real-time scanning keeps a handle open on
/// newly created files for a moment, and Windows cannot delete a file that is
/// open in another process (`errno = 32`). Retrying briefly turns that flaky
/// teardown into a reliable one without weakening any assertion.
Future<void> deleteDirectoryWithRetry(Directory directory) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    try {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
  // Best effort: a still-locked temp directory must not fail the whole run.
}
