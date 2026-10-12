import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/widgets/platform_button.dart';

class RequestDeviceWidget extends StatefulWidget {
  final void Function(BleDevice device) onDeviceSelected;

  const RequestDeviceWidget({
    super.key,
    required this.onDeviceSelected,
  });

  @override
  State<RequestDeviceWidget> createState() => _RequestDeviceWidgetState();
}

class _RequestDeviceWidgetState extends State<RequestDeviceWidget> {
  final TextEditingController _serviceUuidController =
      TextEditingController(text: '180D');
  final TextEditingController _displayNameController =
      TextEditingController(text: 'Heart Rate Monitor');
  final TextEditingController _imageAssetController =
      TextEditingController(text: 'ble_device');
  final TextEditingController _nameSubstringController =
      TextEditingController();

  bool _requiresImmediateRange = false;
  bool _supportsBluetoothPairing = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _serviceUuidController.dispose();
    _displayNameController.dispose();
    _imageAssetController.dispose();
    _nameSubstringController.dispose();
    super.dispose();
  }

  void _applyPreset(String serviceUuid, String displayName) {
    setState(() {
      _serviceUuidController.text = serviceUuid;
      _displayNameController.text = displayName;
    });
  }

  Future<void> _requestDevice() async {
    final serviceUuid = _serviceUuidController.text.trim();
    if (serviceUuid.isEmpty) {
      setState(() {
        _errorMessage = 'Service UUID is required';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      PickerPlatformConfig? platformConfig;

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        platformConfig = PickerPlatformConfig(
          apple: AppleAccessorySetupOptions(
            items: [
              AppleAccessoryPickerItem(
                displayName: _displayNameController.text.trim().isEmpty
                    ? 'Bluetooth Device'
                    : _displayNameController.text.trim(),
                imageAsset: _imageAssetController.text.trim().isEmpty
                    ? 'ble_device'
                    : _imageAssetController.text.trim(),
                serviceUuid: serviceUuid,
                nameSubstring: _nameSubstringController.text.trim().isEmpty
                    ? null
                    : _nameSubstringController.text.trim(),
                requiresImmediateRange: _requiresImmediateRange ? true : null,
                supportsBluetoothPairing:
                    _supportsBluetoothPairing ? true : null,
              ),
            ],
          ),
        );
      } else if (kIsWeb) {
        platformConfig = PickerPlatformConfig(
          web: WebOptions(
            optionalServices: [serviceUuid],
          ),
        );
      }

      final device = await UniversalBle.requestDevice(
        scanFilter: ScanFilter(withServices: [serviceUuid]),
        platformConfig: platformConfig,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onDeviceSelected(device);
      }
    } on UniversalBleException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.code == UniversalBleErrorCode.operationCancelled
              ? 'Device selection cancelled'
              : 'BLE Error [${e.code.name}]: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isIOS
                      ? 'Request Device (AccessorySetupKit)'
                      : 'Request Device (Native Picker)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isIOS
                  ? 'Displays iOS 18+ AccessorySetupKit sheet to pair and authorize a nearby accessory.'
                  : 'Displays platform Bluetooth chooser to select a device.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ActionChip(
                  label: const Text('Heart Rate (180D)'),
                  onPressed: () =>
                      _applyPreset('180D', 'Heart Rate Monitor'),
                ),
                ActionChip(
                  label: const Text('Battery (180F)'),
                  onPressed: () =>
                      _applyPreset('180F', 'Battery Accessory'),
                ),
                ActionChip(
                  label: const Text('Device Info (180A)'),
                  onPressed: () =>
                      _applyPreset('180A', 'BLE Device'),
                ),
                ActionChip(
                  label: const Text('UART (FFE0)'),
                  onPressed: () =>
                      _applyPreset('FFE0', 'Serial Device'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serviceUuidController,
              decoration: const InputDecoration(
                labelText: 'Service UUID *',
                hintText: 'e.g. 180D or 128-bit UUID',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (isIOS) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name (iOS)',
                  hintText: 'Name shown in system picker',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _imageAssetController,
                decoration: const InputDecoration(
                  labelText: 'Image Asset Name (Assets.xcassets)',
                  hintText: 'ble_device or LaunchImage',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameSubstringController,
                decoration: const InputDecoration(
                  labelText: 'Name Substring Filter (Optional)',
                  hintText: 'Must match Info.plist if set',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Requires Immediate Range'),
                subtitle: const Text('Limit discovery to immediate proximity'),
                value: _requiresImmediateRange,
                onChanged: (val) =>
                    setState(() => _requiresImmediateRange = val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Supports Bluetooth Pairing'),
                subtitle: const Text('Allow AccessorySetupKit pairing'),
                value: _supportsBluetoothPairing,
                onChanged: (val) =>
                    setState(() => _supportsBluetoothPairing = val),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            _isLoading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : PlatformButton(
                    text: 'Open System Picker',
                    onPressed: _requestDevice,
                  ),
          ],
        ),
      ),
    );
  }
}
