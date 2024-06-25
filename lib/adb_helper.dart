import 'dart:io';

class AdbHelper {
  /// Runs the `adb devices` command and returns a list of connected devices.
  Future<Map<String, dynamic>> getConnectedDevices() async {
    try {
      final ProcessResult result = await Process.run('adb', <String>['devices']);

      if (result.exitCode != 0) {
        return <String, dynamic>{
          'success': false,
          'error': 'Failed to get connected devices: ${result.stderr}',
        };
      }

      final String output = result.stdout as String;
      final List<String> devices = _parseDevices(output);
      return <String, dynamic>{
        'success': true,
        'devices': devices,
      };
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'error': 'Error running adb command: $e',
      };
    }
  }

  /// Parses the output of `adb devices` command and extracts the list of devices.
  List<String> _parseDevices(String output) {
    final List<String> lines = output.split('\n');
    final List<String> devices = <String>[];

    for (String line in lines) {
      if (line.contains('\tdevice')) {
        final String device = line.split('\t')[0];
        devices.add(device);
      }
    }

    return devices;
  }

  /// Pairs with a device given the IP, port, and pairing code.
  Future<Map<String, dynamic>> pairDevice(String ipAddress, String port, String pairingCode) async {
    try {
      // Start the adb pair process
      final Process process = await Process.start('adb', <String>['pair', '$ipAddress:$port']);

      // Listen to stdout
      final StringBuffer stdoutBuffer = StringBuffer();
      process.stdout.transform(const SystemEncoding().decoder).listen((String data) {
        stdoutBuffer.write(data);
        if (data.contains('Enter pairing code:')) {
          // Send pairing code when prompted
          process.stdin.writeln(pairingCode);
        }
      });

      // Listen to stderr
      final StringBuffer stderrBuffer = StringBuffer();
      process.stderr.transform(const SystemEncoding().decoder).listen((String data) {
        stderrBuffer.write(data);
      });

      // Wait for the process to complete
      final int exitCode = await process.exitCode;

      if (exitCode == 0) {
        return <String, dynamic>{
          'success': true,
        };
      } else {
        return <String, dynamic>{
          'success': false,
          'error': stderrBuffer.isEmpty ? stdoutBuffer.toString() : stderrBuffer.toString(),
        };
      }
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'error': 'Error running adb pair command: $e',
      };
    }
  }

  /// Disconnects a device given the IP address.
  Future<Map<String, dynamic>> disconnectDevice(String ipAddress) async {
    try {
      final ProcessResult result = await Process.run(
        'adb',
        <String>['disconnect', ipAddress],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        return <String, dynamic>{
          'success': false,
          'error': 'Failed to disconnect device: ${result.stderr}',
        };
      }

      return <String, dynamic>{
        'success': true,
      };
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'error': 'Error running adb disconnect command: $e',
      };
    }
  }

  /// Connects to a device given the IP address and port.
  Future<Map<String, dynamic>> connectDevice(String ipAddress, String port) async {
    try {
      final ProcessResult result = await Process.run(
        'adb',
        <String>['connect', '$ipAddress:$port'],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        return <String, dynamic>{
          'success': false,
          'error': 'Failed to connect to device: ${result.stderr}',
        };
      }

      return <String, dynamic>{
        'success': true,
      };
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'error': 'Error running adb connect command: $e',
      };
    }
  }
}
