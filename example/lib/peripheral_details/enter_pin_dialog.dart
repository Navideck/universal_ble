import 'package:flutter/material.dart';

class EnterPinDialog extends StatefulWidget {
  final Function(String) onPin;
  final VoidCallback onCancel;

  const EnterPinDialog({
    super.key,
    required this.onPin,
    required this.onCancel,
  });

  @override
  State<EnterPinDialog> createState() => _EnterPinDialogState();
}

class _EnterPinDialogState extends State<EnterPinDialog> {
  final GlobalKey<FormState> _pinFormKey = GlobalKey<FormState>();
  final TextEditingController _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: const Text('Enter PIN'),
      content: Form(
        key: _pinFormKey,
        child: TextFormField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter a pin';
            }
            return null;
          },
          decoration: const InputDecoration(
            labelText: 'Enter PIN',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onCancel();
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_pinFormKey.currentState!.validate()) {
              widget.onPin(_pinController.text);
              Navigator.of(context).pop();
            }
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
