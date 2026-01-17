import 'package:flutter/material.dart';
import 'dart:math' as math;

class PowerCircleDisplay extends StatefulWidget {
  final double power;
  final String label;

  const PowerCircleDisplay({
    super.key,
    required this.power,
    this.label = "Solar Power Now",
  });

  @override
  State<PowerCircleDisplay> createState() => _PowerCircleDisplayState();
}

class _PowerCircleDisplayState extends State<PowerCircleDisplay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 180,
          height: 180,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: PowerCirclePainter(
                  power: widget.power,
                  animationValue: _controller.value,
                ),
                child: child,
              );
            },
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.power.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    "W/h",
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class PowerCirclePainter extends CustomPainter {
  final double power;
  final double animationValue;

  PowerCirclePainter({
    required this.power,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Background circle
    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, bgPaint);

    // Animated glow ring (only if power > 0)
    if (power > 0) {
      final glowPaint = Paint()
        ..color = Colors.greenAccent.withOpacity(0.3 * (1 - animationValue))
        ..strokeWidth = 8 + (animationValue * 12)
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(center, radius + (animationValue * 8), glowPaint);
    }

    // Power progress circle
    final progressPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.greenAccent,
          Colors.lightGreenAccent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Calculate sweep angle based on power (assuming max 100W)
    final maxPower = 100.0;
    final sweepAngle = (power / maxPower).clamp(0.0, 1.0) * 2 * math.pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // Start from top
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(PowerCirclePainter oldDelegate) =>
      oldDelegate.power != power || oldDelegate.animationValue != animationValue;
}
