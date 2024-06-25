import 'dart:async';
import 'dart:io';
import 'package:adb_wrapper/adb_helper.dart';
import 'package:adb_wrapper/config_helper.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 950),
    center: true,
    skipTaskbar: false,
    title: 'adb wrapper',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setBrightness(Brightness.light);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'adb wrapper',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'adb wrapper'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String title;

  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WindowListener {
  Timer? _configSaveTimer;
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _pairingCodeController = TextEditingController();
  final TextEditingController _pairingPortController = TextEditingController();
  final TextEditingController _scrcpyPathController = TextEditingController();

  final AdbHelper _adbHelper = AdbHelper();
  List<String> _devices = <String>[];
  bool _areDevicesLoading = true;
  String? _errorMessage;

  void _loadConfig() async {
    final Map<String, dynamic> config = await ConfigHelper.readConfig();
    setState(() {
      _ipController.text = config['device_ip'] ?? '';
      _portController.text = config['port'] ?? '';
      _pairingCodeController.text = config['pairing_code'] ?? '';
      _pairingPortController.text = config['pairing_port'] ?? '';
      _scrcpyPathController.text = config['scrcpy_path'] ?? '';
    });
  }

  void _saveConfig() async {
    final Map<String, String> config = <String, String>{
      'device_ip': _ipController.text,
      'port': _portController.text,
      'pairing_code': _pairingCodeController.text,
      'pairing_port': _pairingPortController.text,
      'scrcpy_path': _scrcpyPathController.text,
    };
    await ConfigHelper.writeConfig(config);
  }

  void _onTextChanged() {
    if (_configSaveTimer?.isActive == true) {
      _configSaveTimer!.cancel();
    }
    _configSaveTimer = Timer(const Duration(milliseconds: 500), () {
      _saveConfig();
    });
  }

  Future<void> _loadConnectedDevices() async {
    setState(() {
      _areDevicesLoading = true;
    });

    try {
      final Map<String, dynamic> result = await _adbHelper.getConnectedDevices();
      setState(() {
        _devices = result['devices'] as List<String>;
        _errorMessage = result['error'] as String?;
        _areDevicesLoading = false;
      });
    } catch (e) {
      _errorMessage = e.toString();
      _areDevicesLoading = false;
    } finally {
      setState(() {
        _areDevicesLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _ipController.addListener(_onTextChanged);
    _portController.addListener(_onTextChanged);
    _pairingCodeController.addListener(_onTextChanged);
    _pairingPortController.addListener(_onTextChanged);
    _scrcpyPathController.addListener(_onTextChanged);
    windowManager.addListener(this);
    _loadConnectedDevices();
  }

  @override
  void dispose() {
    _configSaveTimer?.cancel();
    _saveConfig();
    _ipController.dispose();
    _portController.dispose();
    _pairingCodeController.dispose();
    _pairingPortController.dispose();
    _scrcpyPathController.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    _saveConfig();
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 25),
                Text(
                  'Connected Devices',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 25),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _areDevicesLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _devices.isEmpty
                                ? const Text('No devices connected')
                                : ListView.builder(
                                    physics: const NeverScrollableScrollPhysics(),
                                    shrinkWrap: true,
                                    itemCount: _devices.length,
                                    itemBuilder: (BuildContext context, int index) {
                                      return Card(
                                        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                                        elevation: 4,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: ListTile(
                                          title: Text(_devices[index]),
                                          trailing: PopupMenuButton<String>(
                                            onSelected: (String result) async {
                                              if (result == 'disconnect') {
                                                final Map<String, dynamic> result = await _adbHelper.disconnectDevice(_devices[index]);
                                                setState(() {
                                                  _errorMessage = result['error'];
                                                });
                                                await _loadConnectedDevices();
                                              } else if (result.startsWith('scrcpy')) {
                                                final ProcessResult processResult = await Process.run(
                                                  _scrcpyPathController.text,
                                                  <String>[
                                                    '--serial=${_ipController.text}:${_portController.text}',
                                                    if (result.endsWith('noaudio')) '--no-audio',
                                                  ],
                                                  runInShell: true,
                                                );
                                                debugPrint(processResult.exitCode.toString());
                                              }
                                            },
                                            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                              const PopupMenuItem<String>(
                                                value: 'disconnect',
                                                child: Text('Disconnect'),
                                              ),
                                              const PopupMenuItem<String>(
                                                value: 'scrcpy_audio',
                                                child: Text('scrcpy (audio)'),
                                              ),
                                              const PopupMenuItem<String>(
                                                value: 'scrcpy_noaudio',
                                                child: Text('scrcpy (no audio)'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                Text(
                  'Add Device',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 25),
                TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Device IP Address',
                  ),
                  controller: _ipController,
                ),
                const SizedBox(height: 25),
                TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Port',
                  ),
                  controller: _portController,
                ),
                const SizedBox(height: 25),
                TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Pairing Code',
                  ),
                  controller: _pairingCodeController,
                ),
                const SizedBox(height: 25),
                TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Pairing Port',
                  ),
                  controller: _pairingPortController,
                ),
                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    ElevatedButton(
                      onPressed: () async {
                        final Map<String, dynamic> result = await _adbHelper.pairDevice(_ipController.text, _pairingPortController.text, _pairingCodeController.text);
                        setState(() {
                          _errorMessage = result['error'];
                        });

                        await _loadConnectedDevices();
                      },
                      child: const Text('Pair'),
                    ),
                    const SizedBox(width: 15),
                    ElevatedButton(
                      onPressed: () async {
                        final Map<String, dynamic> result = await _adbHelper.connectDevice(_ipController.text, _portController.text);
                        setState(() {
                          _errorMessage = result['error'];
                        });

                        await _loadConnectedDevices();
                      },
                      child: const Text('Connect'),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                if (_errorMessage?.isNotEmpty == true)
                  Text(
                    _errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                const SizedBox(height: 25),
                Text(
                  'Settings',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 25),
                TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'scrcpy Path',
                  ),
                  controller: _scrcpyPathController,
                ),
                const SizedBox(height: 25),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
