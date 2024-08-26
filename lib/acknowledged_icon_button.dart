import 'package:flutter/material.dart';

class AcknowledgedIconButton extends StatefulWidget {
  final Icon icon;
  final IconData acknowledgedIcon;
  final VoidCallback onPressed;
  final double iconSize;
  final String? tooltip;
  final Duration resetDuration;

  const AcknowledgedIconButton({
    super.key,
    required this.icon,
    this.acknowledgedIcon = Icons.check,
    required this.onPressed,
    this.iconSize = 24.0,
    this.tooltip,
    this.resetDuration = const Duration(seconds: 3),
  });

  @override
  State<AcknowledgedIconButton> createState() => _AcknowledgedIconButtonState();
}

class _AcknowledgedIconButtonState extends State<AcknowledgedIconButton> {
  bool _isPressed = false;

  void _handlePress() {
    if (_isPressed) return; // Prevent double presses

    // Temporarily disable the button and change the icon
    setState(() {
      _isPressed = true;
    });

    // Call the provided onPressed function
    widget.onPressed();

    // Reset the button after the specified duration
    Future<void>.delayed(widget.resetDuration, () {
      setState(() {
        _isPressed = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_isPressed ? widget.acknowledgedIcon : widget.icon.icon),
      iconSize: widget.iconSize,
      tooltip: widget.tooltip,
      onPressed: _isPressed ? null : _handlePress, // Disable the button when pressed
    );
  }
}
