import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ConfigHelper {
  static Future<String> get _localPath async {
    final Directory directory = await getApplicationDocumentsDirectory();
    return path.join(directory.path, 'adb-wrapper');
  }

  static Future<File> get _localFile async {
    final String localPath = await _localPath;

    // Ensure the directory exists
    final Directory dir = Directory(localPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final String filePath = path.join(localPath, 'config.json');
    final File file = File(filePath);

    // Ensure the file exists
    if (!await file.exists()) {
      await file.create();
    }

    return file;
  }

  static Future<Map<String, dynamic>> readConfig() async {
    try {
      final File file = await _localFile;
      String contents = await file.readAsString();
      return jsonDecode(contents);
    } catch (e) {
      return <String, dynamic>{};
    }
  }

  static Future<File> writeConfig(Map<String, dynamic> config) async {
    final File file = await _localFile;
    return file.writeAsString(jsonEncode(config));
  }
}
