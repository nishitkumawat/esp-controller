import 'package:flutter/material.dart';
import 'dart:math' as math;

class SolarHouseIllustration extends StatelessWidget {
  final double currentPower;

  const SolarHouseIllustration({
    super.key,
    required this.currentPower,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 140),
      painter: _ModernHousePainter(currentPower: currentPower),
    );
  }
}

class _ModernHousePainter extends CustomPainter {
  final double currentPower;

  _ModernHousePainter({required this.currentPower});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final groundY = size.height * 0.88;

    _drawSkyline(canvas, size, groundY);
    _drawGround(canvas, size, groundY);
    _drawHouse(canvas, centerX, groundY);
    _drawSolarPanels(canvas, centerX, groundY);
    _drawPowerTower(canvas, size.width * 0.82, groundY);
    _drawTrees(canvas, size, groundY);

    if (currentPower > 0) {
      _drawPowerFlow(canvas, centerX, groundY, size);
      _drawSunRays(canvas, size);
    }
  }

  void _drawSkyline(Canvas canvas, Size size, double groundY) {
    // Distant buildings silhouette
    final skylinePaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.fill;

    final buildingWidths = [20.0, 15.0, 25.0, 12.0, 18.0, 22.0, 14.0, 20.0];
    final buildingHeights = [35.0, 50.0, 28.0, 45.0, 32.0, 40.0, 55.0, 30.0];
    double x = size.width * 0.05;

    for (int i = 0; i < buildingWidths.length; i++) {
      final w = buildingWidths[i];
      final h = buildingHeights[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, groundY - h, w, h),
          const Radius.circular(2),
        ),
        skylinePaint,
      );
      x += w + 8 + (i * 3);
    }
  }

  void _drawHouse(Canvas canvas, double centerX, double groundY) {
    // Modern house body with gradient
    final houseGradient = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2C3E50), Color(0xFF1A252F)],
      ).createShader(Rect.fromLTWH(centerX - 55, groundY - 55, 110, 55));
    
    final houseRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(centerX - 55, groundY - 55, 110, 55),
      const Radius.circular(4),
    );
    canvas.drawRRect(houseRRect, houseGradient);

    // Roof with subtle gradient
    final roofPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF4A6274), Color(0xFF34495E)],
      ).createShader(Rect.fromLTWH(centerX - 65, groundY - 82, 130, 27));

    final roofPath = Path();
    roofPath.moveTo(centerX - 65, groundY - 55);
    roofPath.lineTo(centerX - 10, groundY - 82);
    roofPath.lineTo(centerX + 65, groundY - 55);
    roofPath.close();
    canvas.drawPath(roofPath, roofPaint);

    // Second roof section (modern split roof)
    final roof2Path = Path();
    roof2Path.moveTo(centerX + 10, groundY - 55);
    roof2Path.lineTo(centerX + 40, groundY - 72);
    roof2Path.lineTo(centerX + 65, groundY - 55);
    roof2Path.close();
    canvas.drawPath(roof2Path, Paint()..color = const Color(0xFF3D566E));

    // Windows with warm glow
    final windowGlow = Paint()
      ..color = const Color(0xFFFFF3CD).withOpacity(0.7)
      ..style = PaintingStyle.fill;
    final windowFrame = Paint()
      ..color = const Color(0xFF1A252F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Left window
    final w1 = RRect.fromRectAndRadius(
      Rect.fromLTWH(centerX - 40, groundY - 42, 18, 22),
      const Radius.circular(2),
    );
    canvas.drawRRect(w1, windowGlow);
    canvas.drawRRect(w1, windowFrame);
    // Window cross
    canvas.drawLine(
      Offset(centerX - 31, groundY - 42),
      Offset(centerX - 31, groundY - 20),
      windowFrame,
    );
    canvas.drawLine(
      Offset(centerX - 40, groundY - 31),
      Offset(centerX - 22, groundY - 31),
      windowFrame,
    );

    // Right window
    final w2 = RRect.fromRectAndRadius(
      Rect.fromLTWH(centerX + 5, groundY - 42, 18, 22),
      const Radius.circular(2),
    );
    canvas.drawRRect(w2, windowGlow);
    canvas.drawRRect(w2, windowFrame);
    canvas.drawLine(
      Offset(centerX + 14, groundY - 42),
      Offset(centerX + 14, groundY - 20),
      windowFrame,
    );
    canvas.drawLine(
      Offset(centerX + 5, groundY - 31),
      Offset(centerX + 23, groundY - 31),
      windowFrame,
    );

    // Door
    final doorPaint = Paint()
      ..color = const Color(0xFFD35400).withOpacity(0.8)
      ..style = PaintingStyle.fill;
    final doorRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(centerX + 30, groundY - 35, 16, 35),
      topLeft: const Radius.circular(8),
      topRight: const Radius.circular(8),
    );
    canvas.drawRRect(doorRect, doorPaint);

    // Door knob
    canvas.drawCircle(
      Offset(centerX + 42, groundY - 17),
      1.5,
      Paint()..color = const Color(0xFFFFD700),
    );
  }

  void _drawSolarPanels(Canvas canvas, double centerX, double groundY) {
    final panelGradient = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2980B9), Color(0xFF1A5276)],
      ).createShader(Rect.fromLTWH(centerX - 50, groundY - 80, 80, 22));

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    final panelShine = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    // Panel 1
    final p1 = Rect.fromLTWH(centerX - 50, groundY - 78, 38, 20);
    canvas.drawRRect(RRect.fromRectAndRadius(p1, const Radius.circular(1.5)), panelGradient);
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(Offset(p1.left + (i * 9.5), p1.top), Offset(p1.left + (i * 9.5), p1.bottom), gridPaint);
    }
    canvas.drawLine(Offset(p1.left, p1.top + 10), Offset(p1.right, p1.top + 10), gridPaint);
    // Shine effect
    canvas.drawRect(Rect.fromLTWH(p1.left + 2, p1.top + 2, 8, 6), panelShine);

    // Panel 2
    final p2 = Rect.fromLTWH(centerX - 8, groundY - 78, 38, 20);
    canvas.drawRRect(RRect.fromRectAndRadius(p2, const Radius.circular(1.5)), panelGradient);
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(Offset(p2.left + (i * 9.5), p2.top), Offset(p2.left + (i * 9.5), p2.bottom), gridPaint);
    }
    canvas.drawLine(Offset(p2.left, p2.top + 10), Offset(p2.right, p2.top + 10), gridPaint);
    canvas.drawRect(Rect.fromLTWH(p2.left + 2, p2.top + 2, 8, 6), panelShine);
  }

  void _drawPowerTower(Canvas canvas, double x, double groundY) {
    final towerPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Tower legs
    canvas.drawLine(Offset(x - 12, groundY), Offset(x - 4, groundY - 50), towerPaint);
    canvas.drawLine(Offset(x + 12, groundY), Offset(x + 4, groundY - 50), towerPaint);
    
    // Tower top
    canvas.drawLine(Offset(x - 4, groundY - 50), Offset(x + 4, groundY - 50), towerPaint);

    // Cross beams
    final beamPaint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..strokeWidth = 1;
    for (int i = 0; i < 3; i++) {
      final y = groundY - (i * 16) - 5;
      final factor = i * 2.5;
      canvas.drawLine(Offset(x - 12 + factor, y), Offset(x + 12 - factor, y), beamPaint);
    }

    // Arms at top
    canvas.drawLine(Offset(x - 4, groundY - 50), Offset(x - 16, groundY - 52), towerPaint);
    canvas.drawLine(Offset(x + 4, groundY - 50), Offset(x + 16, groundY - 52), towerPaint);

    // Power lines
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 0.8;

    final path = Path();
    path.moveTo(x - 16, groundY - 52);
    path.quadraticBezierTo(x - 60, groundY - 40, x - 100, groundY - 48);
    canvas.drawPath(path, linePaint);

    final path2 = Path();
    path2.moveTo(x + 16, groundY - 52);
    path2.quadraticBezierTo(x + 50, groundY - 44, x + 80, groundY - 50);
    canvas.drawPath(path2, linePaint);
  }

  void _drawTrees(Canvas canvas, Size size, double groundY) {
    // Left tree
    _drawTree(canvas, size.width * 0.12, groundY, 32);
    _drawTree(canvas, size.width * 0.22, groundY, 22);
    // Right tree
    _drawTree(canvas, size.width * 0.68, groundY, 26);
  }

  void _drawTree(Canvas canvas, double x, double groundY, double height) {
    // Trunk
    canvas.drawLine(
      Offset(x, groundY),
      Offset(x, groundY - height * 0.4),
      Paint()
        ..color = Colors.white.withOpacity(0.08)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Canopy (triangle)
    final treePaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.fill;
    
    final treePath = Path();
    treePath.moveTo(x, groundY - height);
    treePath.lineTo(x - height * 0.35, groundY - height * 0.35);
    treePath.lineTo(x + height * 0.35, groundY - height * 0.35);
    treePath.close();
    canvas.drawPath(treePath, treePaint);
  }

  void _drawGround(Canvas canvas, Size size, double groundY) {
    // Ground with gradient fade
    final groundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.04),
          Colors.white.withOpacity(0.01),
        ],
      ).createShader(Rect.fromLTWH(0, groundY, size.width, size.height - groundY));

    canvas.drawRect(
      Rect.fromLTWH(0, groundY, size.width, size.height - groundY),
      groundPaint,
    );

    // Ground line
    canvas.drawLine(
      Offset(0, groundY),
      Offset(size.width, groundY),
      Paint()
        ..color = Colors.white.withOpacity(0.08)
        ..strokeWidth = 0.5,
    );
  }

  void _drawPowerFlow(Canvas canvas, double centerX, double groundY, Size size) {
    // Energy flow particles (dotted path from panels to house)
    final flowPaint = Paint()
      ..color = const Color(0xFF4ADE80).withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Flow line from panel center down to house
    final flowPath = Path();
    flowPath.moveTo(centerX - 20, groundY - 78);
    flowPath.quadraticBezierTo(centerX - 25, groundY - 65, centerX - 20, groundY - 55);
    canvas.drawPath(flowPath, flowPaint);

    // Small energy dots
    final dotPaint = Paint()
      ..color = const Color(0xFF4ADE80).withOpacity(0.6);
    
    canvas.drawCircle(Offset(centerX - 20, groundY - 72), 2, dotPaint);
    canvas.drawCircle(Offset(centerX - 22, groundY - 63), 1.5, dotPaint);

    // Arrow
    final arrowPath = Path();
    arrowPath.moveTo(centerX - 20, groundY - 56);
    arrowPath.lineTo(centerX - 24, groundY - 60);
    arrowPath.lineTo(centerX - 16, groundY - 60);
    arrowPath.close();
    canvas.drawPath(arrowPath, Paint()..color = const Color(0xFF4ADE80).withOpacity(0.6));
  }

  void _drawSunRays(Canvas canvas, Size size) {
    // Subtle sun rays from top-right
    final rayPaint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..strokeWidth = 1;
    
    final sunX = size.width * 0.9;
    const sunY = 10.0;

    for (int i = 0; i < 5; i++) {
      final angle = -math.pi / 4 + (i * math.pi / 12);
      final endX = sunX + math.cos(angle) * 80;
      final endY = sunY + math.sin(angle) * 80;
      canvas.drawLine(Offset(sunX, sunY), Offset(endX, endY), rayPaint);
    }
  }

  @override
  bool shouldRepaint(_ModernHousePainter oldDelegate) =>
      oldDelegate.currentPower != currentPower;
}
