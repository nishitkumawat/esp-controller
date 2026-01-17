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
      size: const Size(double.infinity, 200),
      painter: HousePainter(currentPower: currentPower),
    );
  }
}

class HousePainter extends CustomPainter {
  final double currentPower;

  HousePainter({required this.currentPower});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final groundY = size.height * 0.85;

    // Draw house
    _drawHouse(canvas, centerX, groundY);
    
    // Draw solar panels on roof
    _drawSolarPanels(canvas, centerX, groundY);
    
    // Draw power transmission tower
    _drawPowerTower(canvas, size.width * 0.8, groundY);
    
    // Draw ground
    _drawGround(canvas, size, groundY);
    
    // Draw power flow if generating
    if (currentPower > 0) {
      _drawPowerFlow(canvas, centerX, groundY, size);
    }
  }

  void _drawHouse(Canvas canvas, double centerX, double groundY) {
    final housePaint = Paint()
      ..color = const Color(0xFF2C3E50)
      ..style = PaintingStyle.fill;

    // House body
    final houseRect = Rect.fromCenter(
      center: Offset(centerX, groundY - 40),
      width: 140,
      height: 80,
    );
    canvas.drawRect(houseRect, housePaint);

    // Roof
    final roofPaint = Paint()
      ..color = const Color(0xFF34495E)
      ..style = PaintingStyle.fill;

    final roofPath = Path();
    roofPath.moveTo(centerX - 80, groundY - 80);
    roofPath.lineTo(centerX, groundY - 120);
    roofPath.lineTo(centerX + 80, groundY - 80);
    roofPath.close();
    canvas.drawPath(roofPath, roofPaint);

    // Window
    final windowPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    
    canvas.drawRect(
      Rect.fromLTWH(centerX - 20, groundY - 50, 15, 20),
      windowPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(centerX + 5, groundY - 50, 15, 20),
      windowPaint,
    );
  }

  void _drawSolarPanels(Canvas canvas, double centerX, double groundY) {
    final panelPaint = Paint()
      ..color = const Color(0xFF2980B9)
      ..style = PaintingStyle.fill;

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Panel 1
    final panel1 = Rect.fromLTWH(centerX - 60, groundY - 110, 50, 25);
    canvas.drawRect(panel1, panelPaint);
    
    // Grid lines
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(centerX - 60 + (i * 12.5), groundY - 110),
        Offset(centerX - 60 + (i * 12.5), groundY - 85),
        gridPaint,
      );
    }

    // Panel 2
    final panel2 = Rect.fromLTWH(centerX - 5, groundY - 110, 50, 25);
    canvas.drawRect(panel2, panelPaint);
    
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(centerX - 5 + (i * 12.5), groundY - 110),
        Offset(centerX - 5 + (i * 12.5), groundY - 85),
        gridPaint,
      );
    }
  }

  void _drawPowerTower(Canvas canvas, double x, double groundY) {
    final towerPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Tower structure
    canvas.drawLine(
      Offset(x - 15, groundY),
      Offset(x - 5, groundY - 60),
      towerPaint,
    );
    canvas.drawLine(
      Offset(x + 15, groundY),
      Offset(x + 5, groundY - 60),
      towerPaint,
    );
    canvas.drawLine(
      Offset(x - 5, groundY - 60),
      Offset(x + 5, groundY - 60),
      towerPaint,
    );

    // Cross beams
    for (int i = 0; i < 3; i++) {
      final y = groundY - (i * 20);
      canvas.drawLine(
        Offset(x - 15 + (i * 3), y),
        Offset(x + 15 - (i * 3), y),
        towerPaint,
      );
    }

    // Power lines
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(x - 10, groundY - 60),
      Offset(x - 100, groundY - 50),
      linePaint,
    );
  }

  void _drawGround(Canvas canvas, Size size, double groundY) {
    final groundPaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(0, groundY, size.width, size.height - groundY),
      groundPaint,
    );

    // Grass
    final grassPaint = Paint()
      ..color = const Color(0xFF27AE60).withOpacity(0.1)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 20; i++) {
      canvas.drawLine(
        Offset(i * (size.width / 20), groundY),
        Offset(i * (size.width / 20) + 5, groundY + 10),
        grassPaint..strokeWidth = 2,
      );
    }
  }

  void _drawPowerFlow(Canvas canvas, double centerX, double groundY, Size size) {
    final flowPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Animated flow lines from solar panel to house
    final dashPaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.6)
      ..strokeWidth = 2;

    // Vertical flow from panels
    canvas.drawLine(
      Offset(centerX - 30, groundY - 85),
      Offset(centerX - 30, groundY - 70),
      dashPaint,
    );
    
    // Arrow
    final arrowPath = Path();
    arrowPath.moveTo(centerX - 30, groundY - 70);
    arrowPath.lineTo(centerX - 35, groundY - 75);
    arrowPath.lineTo(centerX - 25, groundY - 75);
    arrowPath.close();
    canvas.drawPath(arrowPath, Paint()..color = Colors.greenAccent);
  }

  @override
  bool shouldRepaint(HousePainter oldDelegate) =>
      oldDelegate.currentPower != currentPower;
}
