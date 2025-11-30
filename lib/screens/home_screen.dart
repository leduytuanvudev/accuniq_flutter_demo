import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../providers/accuniq_provider.dart';
import '../models/member_info.dart';
import '../models/measurement_result.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accuniq Body Composition Analyzer'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.bluetooth), text: 'Connection'),
            Tab(icon: Icon(Icons.person), text: 'Member'),
            Tab(icon: Icon(Icons.monitor_weight), text: 'Measurement'),
            Tab(icon: Icon(Icons.terminal), text: 'Logs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ConnectionTab(),
          MemberTab(),
          MeasurementTab(),
          LogsTab(),
        ],
      ),
    );
  }
}

// ==================== Connection Tab ====================

class ConnectionTab extends StatefulWidget {
  const ConnectionTab({super.key});

  @override
  State<ConnectionTab> createState() => _ConnectionTabState();
}

class _ConnectionTabState extends State<ConnectionTab> {
  dynamic _selectedDevice;

  @override
  Widget build(BuildContext context) {
    return Consumer<AccuniqProvider>(
      builder: (context, provider, child) {
        final isConnected = provider.isConnected;
        final isConnecting = provider.isConnecting;
        final isScanning = provider.isScanning;
        final isAutoConnecting = provider.isAutoConnecting;
        final autoConnectEnabled = provider.autoConnectEnabled;
        final deviceInfo = provider.deviceInfo;
        final isAndroid = provider.isAndroid;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Platform indicator
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.android, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      'Android - HC-05-USB (Bluetooth Classic)',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Auto-Connect Toggle
            Card(
              child: SwitchListTile(
                title: const Text('Auto-connect on startup'),
                subtitle: const Text(
                  'Automatically connect to last device when app starts',
                ),
                value: autoConnectEnabled,
                onChanged: (value) {
                  provider.setAutoConnectEnabled(value);
                },
                secondary: const Icon(Icons.auto_fix_high),
              ),
            ),
            const SizedBox(height: 16),

            // Auto-Connect Loading Indicator
            if (isAutoConnecting)
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Auto-connecting to device...',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (isAutoConnecting) const SizedBox(height: 16),

            // Status Card
            Card(
              color: isConnected ? Colors.green.shade50 : Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      isConnected ? Icons.check_circle : Icons.cancel,
                      size: 64,
                      color: isConnected ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isConnected ? 'Connected' : 'Disconnected',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (deviceInfo != null) ...[
                      const SizedBox(height: 8),
                      Text(deviceInfo.toString()),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Connection UI
            if (!isConnected) ...[
              // Bluetooth Classic UI (HC-05-USB)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Bluetooth Classic Devices (HC-05-USB)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: isScanning
                        ? null
                        : () => provider.refreshBluetoothDevices(),
                    icon: isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bluetooth_searching),
                    label: Text(isScanning ? 'Scanning...' : 'Scan'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildBluetoothDeviceList(provider),
              const SizedBox(height: 16),

              // Connect Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed:
                      isConnecting ||
                          isAutoConnecting ||
                          _selectedDevice == null
                      ? null
                      : () => _connect(provider),
                  icon: isConnecting || isAutoConnecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: Text(
                    isConnecting || isAutoConnecting
                        ? 'Connecting...'
                        : 'Connect',
                  ),
                ),
              ),
            ] else ...[
              // Disconnect Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => provider.disconnect(),
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => provider.syncTime(),
                  icon: const Icon(Icons.access_time),
                  label: const Text('Sync Time'),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Instructions
            _buildInstructions(isAndroid),
          ],
        );
      },
    );
  }

  /// Helper to get device name (Bluetooth Classic only)
  String _getDeviceName(dynamic device) {
    try {
      if (device is BluetoothDevice) {
        return device.name ?? 'Unknown';
      }
      return 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }

  /// Helper to get device address (Bluetooth Classic only)
  String _getDeviceAddress(dynamic device) {
    try {
      if (device is BluetoothDevice) {
        return device.address;
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  Widget _buildBluetoothDeviceList(AccuniqProvider provider) {
    final devices = provider.availableDevices;

    if (devices.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(
                Icons.bluetooth_disabled,
                size: 48,
                color: Colors.grey,
              ),
              const SizedBox(height: 8),
              const Text('No paired Bluetooth devices'),
              const SizedBox(height: 8),
              const Text(
                'Please pair your HC-05 in Android Bluetooth settings first',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => provider.refreshBluetoothDevices(),
                child: const Text('Scan Again'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: devices.map((device) {
        final name = _getDeviceName(device);
        final address = _getDeviceAddress(device);
        final isHC05 = name.toLowerCase().contains('hc') ||
            name.toLowerCase().contains('hc-05') ||
            name.toLowerCase().contains('accuniq');
        final isSelected = _selectedDevice == device;

        return Card(
          color: isSelected ? Colors.blue.shade50 : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isHC05 ? Colors.green : Colors.blue,
              child: Icon(
                isHC05 ? Icons.check : Icons.bluetooth,
                color: Colors.white,
              ),
            ),
            title: Text(name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(address),
                const Text(
                  'Bluetooth Classic (HC-05-USB)',
                  style: TextStyle(fontSize: 11, color: Colors.blue),
                ),
              ],
            ),
            trailing: isSelected
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
            onTap: () {
              setState(() => _selectedDevice = device);
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInstructions(bool isAndroid) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Instructions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Pair HC-05-USB module in Android Bluetooth settings (PIN: 1234)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('2. Tap "Scan" to find paired Bluetooth Classic devices'),
            const Text('3. Select your HC-05-USB device'),
            const Text('4. Tap "Connect"'),
            const SizedBox(height: 8),
            const Text(
              'ℹ️  NOTE:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
            ),
            const Text(
              '• Only Bluetooth Classic (SPP) devices are supported',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.blue),
            ),
            const Text(
              '• HC-05-USB is Bluetooth Classic and will work',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.green),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connect(AccuniqProvider provider) async {
    if (_selectedDevice == null) return;

    final success = await provider.connect(_selectedDevice!);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Connected successfully!' : 'Connection failed',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }
}

// ==================== Member Tab ====================

class MemberTab extends StatefulWidget {
  const MemberTab({super.key});

  @override
  State<MemberTab> createState() => _MemberTabState();
}

class _MemberTabState extends State<MemberTab> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController(text: '001');
  final _nameController = TextEditingController(text: 'John Doe');
  final _ageController = TextEditingController(text: '30');
  final _heightController = TextEditingController(text: '175');
  String _gender = 'M';

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AccuniqProvider>(
      builder: (context, provider, child) {
        final isConnected = provider.isConnected;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Member Information',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _idController,
                        decoration: const InputDecoration(
                          labelText: 'ID',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge),
                        ),
                        validator: (v) =>
                            v?.isEmpty == true ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (v) =>
                            v?.isEmpty == true ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _ageController,
                              decoration: const InputDecoration(
                                labelText: 'Age',
                                border: OutlineInputBorder(),
                                suffixText: 'years',
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) =>
                                  v?.isEmpty == true ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _gender,
                              decoration: const InputDecoration(
                                labelText: 'Gender',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'M',
                                  child: Text('Male'),
                                ),
                                DropdownMenuItem(
                                  value: 'F',
                                  child: Text('Female'),
                                ),
                              ],
                              onChanged: (v) => setState(() => _gender = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _heightController,
                        decoration: const InputDecoration(
                          labelText: 'Height',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.height),
                          suffixText: 'cm',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            v?.isEmpty == true ? 'Required' : null,
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: isConnected
                              ? () => _sendMemberInfo(provider)
                              : null,
                          icon: const Icon(Icons.send),
                          label: const Text('Send to Device'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            if (!isConnected)
              const Card(
                color: Colors.orange,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.white),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Please connect to device first',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _sendMemberInfo(AccuniqProvider provider) async {
    if (!_formKey.currentState!.validate()) return;

    final member = MemberInfo(
      id: _idController.text,
      name: _nameController.text,
      age: int.parse(_ageController.text),
      gender: _gender,
      height: double.parse(_heightController.text),
    );

    final success = await provider.sendMemberInfo(member);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Member info sent!' : 'Failed to send'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }
}

// ==================== Measurement Tab ====================

class MeasurementTab extends StatelessWidget {
  const MeasurementTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AccuniqProvider>(
      builder: (context, provider, child) {
        final state = provider.currentState;
        final isConnected = provider.isConnected;
        final lastMeasurement = provider.lastMeasurement;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // State Card
            Card(
              color: _getStateColor(state),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(_getStateIcon(state), size: 64, color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      state.displayName,
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Manual request button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: isConnected
                    ? () => provider.requestMeasurement()
                    : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Request Measurement'),
              ),
            ),
            const SizedBox(height: 24),

            // Results
            if (lastMeasurement != null) ...[
              Text(
                'Measurement Results',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),

              // Personal Info Section
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Personal Information',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.blue.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const Divider(),
                      _buildInfoRow(
                        'Gender',
                        lastMeasurement.gender,
                        Icons.person,
                      ),
                      _buildInfoRow(
                        'Age',
                        '${lastMeasurement.age} years',
                        Icons.cake,
                      ),
                      _buildInfoRow(
                        'Height',
                        '${lastMeasurement.height.toStringAsFixed(1)} cm',
                        Icons.height,
                      ),
                      _buildInfoRow(
                        'Body Type',
                        lastMeasurement.bodyType,
                        Icons.accessibility_new,
                      ),
                      _buildInfoRow(
                        'Biological Age',
                        '${lastMeasurement.biologicalAge} years',
                        Icons.biotech,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Body Composition Section
              Text(
                'Body Composition',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _buildResultCard(
                'Weight',
                '${lastMeasurement.weight.toStringAsFixed(1)} kg',
                Icons.monitor_weight,
              ),
              _buildResultCard(
                'PBF (Body Fat %)',
                '${lastMeasurement.bodyFatPercent.toStringAsFixed(1)}%',
                Icons.water_drop,
              ),
              _buildResultCard(
                'Body Fat Mass',
                '${lastMeasurement.bodyFatMass.toStringAsFixed(2)} kg',
                Icons.opacity,
              ),
              _buildResultCard(
                'Soft Lean Mass',
                '${lastMeasurement.softLeanMass.toStringAsFixed(1)} kg',
                Icons.trending_up,
              ),
              _buildResultCard(
                'Skeletal Muscle Mass',
                '${lastMeasurement.skeletalMuscleMass.toStringAsFixed(1)} kg',
                Icons.fitness_center,
              ),
              _buildResultCard(
                'Body Water',
                '${lastMeasurement.bodyWater.toStringAsFixed(1)} kg',
                Icons.water,
              ),

              const SizedBox(height: 16),

              // Health Metrics Section
              Text(
                'Health Metrics',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _buildResultCard(
                'BMI',
                lastMeasurement.bmi.toStringAsFixed(1),
                Icons.analytics,
              ),
              _buildResultCard(
                'Basal Metabolic Rate',
                '${lastMeasurement.bmr.toStringAsFixed(0)} kcal',
                Icons.local_fire_department,
              ),
              _buildResultCard(
                'Body Cell Mass',
                '${lastMeasurement.bodyCellMass.toStringAsFixed(1)} kg',
                Icons.science,
              ),
            ] else ...[
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.info_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No measurement data yet'),
                      Text('Complete a measurement to see results'),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Instructions
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Measurement Steps',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text('1. Send member information'),
                    const Text('2. Step on the device'),
                    const Text('3. Wait for measurement to complete'),
                    const Text('4. Results will appear automatically'),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResultCard(String label, String value, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.blue.shade900,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStateColor(DeviceState state) {
    switch (state) {
      case DeviceState.ready:
        return Colors.blue;
      case DeviceState.measuringWeight:
      case DeviceState.measuringBodyComposition:
        return Colors.orange;
      case DeviceState.completeDisplay:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getStateIcon(DeviceState state) {
    switch (state) {
      case DeviceState.ready:
        return Icons.check_circle;
      case DeviceState.measuringWeight:
      case DeviceState.measuringBodyComposition:
        return Icons.hourglass_empty;
      case DeviceState.completeDisplay:
        return Icons.done_all;
      default:
        return Icons.help_outline;
    }
  }
}

// ==================== Logs Tab ====================

class LogsTab extends StatelessWidget {
  const LogsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AccuniqProvider>(
      builder: (context, provider, child) {
        final logs = provider.logs;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${logs.length} logs',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => provider.clearLogs(),
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: logs.isEmpty
                  ? const Center(child: Text('No logs yet'))
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(8),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[logs.length - 1 - index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Text(
                              log,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
