import 'package:flutter/material.dart';
import 'dart:math' as math;

class PowerCircleDisplay extends StatefulWidget {
  final double power;
  final String label;
  final Color textColor;
  final Color subtextColor;

  const PowerCircleDisplay({
    super.key,
    required this.power,
    this.label = "Solar Power Now",
    this.textColor = Colors.white,
    this.subtextColor = Colors.white70,
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
      duration: const Duration(seconds: 3),
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
          width: 170,
          height: 170,
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
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: widget.textColor,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    "W/h",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: widget.subtextColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.textColor.withOpacity(0.8),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
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
    final radius = size.width / 2 - 12;

    // Background circle track
    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, bgPaint);

    // Animated outer glow ring (only if power > 0)
    if (power > 0) {
      final pulseValue = (math.sin(animationValue * math.pi * 2) + 1) / 2;
      final glowPaint = Paint()
        ..color = const Color(0xFF4ADE80).withOpacity(0.15 + pulseValue * 0.15)
        ..strokeWidth = 6 + (pulseValue * 6)
        ..style = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + pulseValue * 4);
      canvas.drawCircle(center, radius + 2, glowPaint);
    }

    // Power progress arc with gradient
    final maxPower = 100.0;
    final sweepAngle = (power / maxPower).clamp(0.0, 1.0) * 2 * math.pi;

    if (sweepAngle > 0) {
      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + sweepAngle,
          colors: const [
            Color(0xFF4ADE80),
            Color(0xFF22D3EE),
            Color(0xFF4ADE80),
          ],
          stops: const [0.0, 0.5, 1.0],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        progressPaint,
      );

      // Dot at the end of the arc
      final dotAngle = -math.pi / 2 + sweepAngle;
      final dotX = center.dx + radius * math.cos(dotAngle);
      final dotY = center.dy + radius * math.sin(dotAngle);
      
      final dotPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(dotX, dotY), 5, dotPaint);
      
      final dotGlow = Paint()
        ..color = const Color(0xFF4ADE80).withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(dotX, dotY), 8, dotGlow);
    }

    // Inner subtle ring
    final innerPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius - 12, innerPaint);
  }

  @override
  bool shouldRepaint(PowerCirclePainter oldDelegate) =>
      oldDelegate.power != power || oldDelegate.animationValue != animationValue;
}
