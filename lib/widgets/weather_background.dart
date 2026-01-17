import 'package:flutter/material.dart';
import 'dart:math' as math;

class WeatherBackground extends StatefulWidget {
  final int weatherCode;
  final Widget child;

  const WeatherBackground({
    super.key,
    required this.weatherCode,
    required this.child,
  });

  @override
  State<WeatherBackground> createState() => _WeatherBackgroundState();
}

class _WeatherBackgroundState extends State<WeatherBackground>
    with TickerProviderStateMixin {
  late AnimationController _cloudController;
  late List<Cloud> _clouds;
  bool _isNight = false;

  @override
  void initState() {
    super.initState();
    _cloudController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 90), // Slower for more realistic
    )..repeat();
    
    _checkDayNight();
    _generateClouds();
  }

  void _checkDayNight() {
    final hour = DateTime.now().hour;
    _isNight = hour < 6 || hour >= 19; // Night from 7 PM to 6 AM
  }

  void _generateClouds() {
    final cloudCount = _getCloudCount(widget.weatherCode);
    final random = math.Random();
    
    _clouds = List.generate(cloudCount, (index) {
      return Cloud(
        x: random.nextDouble(),
        y: 0.1 + random.nextDouble() * 0.5, // Upper 60% of screen
        size: 70 + random.nextDouble() * 100,
        opacity: _isNight ? 0.08 + random.nextDouble() * 0.12 : 0.15 + random.nextDouble() * 0.20, // Reduced opacity
        speed: 0.0002 + random.nextDouble() * 0.0003,
        layer: random.nextInt(3), // 3 layers for depth
      );
    });
  }

  int _getCloudCount(int weatherCode) {
    // WMO Weather interpretation codes
    if (weatherCode == 0) return 3; // Clear sky - few clouds
    if (weatherCode <= 3) return 6; // Partly cloudy
    if (weatherCode <= 48) return 12; // Cloudy/Foggy
    return 15; // Rainy/Stormy - many clouds
  }

  @override
  void didUpdateWidget(WeatherBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weatherCode != widget.weatherCode) {
      _checkDayNight();
      _generateClouds();
    }
  }

  @override
  void dispose() {
    _cloudController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _getGradientColors(widget.weatherCode),
        ),
      ),
      child: AnimatedBuilder(
        animation: _cloudController,
        builder: (context, child) {
          return CustomPaint(
            painter: CloudPainter(
              clouds: _clouds,
              animationValue: _cloudController.value,
              showSun: widget.weatherCode <= 2 && !_isNight,
              showMoon: _isNight,
              weatherCode: widget.weatherCode,
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }

  List<Color> _getGradientColors(int weatherCode) {
    if (_isNight) {
      // Night colors
      if (weatherCode == 0) {
        return [
          const Color(0xFF0F2027),
          const Color(0xFF203A43),
          const Color(0xFF2C5364),
        ];
      } else if (weatherCode <= 3) {
        return [
          const Color(0xFF0F2027),
          const Color(0xFF1C3644),
          const Color(0xFF2C4A5C),
        ];
      } else {
        return [
          const Color(0xFF0A1828),
          const Color(0xFF152238),
          const Color(0xFF1E3248),
        ];
      }
    } else {
      // Day colors
      if (weatherCode == 0) {
        // Clear/Sunny - bright blue
        return [
          const Color(0xFF4A90E2),
          const Color(0xFF5BA3F5),
          const Color(0xFF2E5C8A),
        ];
      } else if (weatherCode <= 3) {
        // Partly cloudy
        return [
          const Color(0xFF3D7AB8),
          const Color(0xFF4A89C9),
          const Color(0xFF1E3A5F),
        ];
      } else {
        // Cloudy/Rainy - darker
        return [
          const Color(0xFF2C5F8D),
          const Color(0xFF3A6F9D),
          const Color(0xFF1A3A5C),
        ];
      }
    }
  }
}

class Cloud {
  double x;
  final double y;
  final double size;
  final double opacity;
  final double speed;
  final int layer;

  Cloud({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.speed,
    required this.layer,
  });
}

class CloudPainter extends CustomPainter {
  final List<Cloud> clouds;
  final double animationValue;
  final bool showSun;
  final bool showMoon;
  final int weatherCode;

  CloudPainter({
    required this.clouds,
    required this.animationValue,
    required this.showSun,
    required this.showMoon,
    required this.weatherCode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw sun or moon
    if (showSun) {
      _drawSun(canvas, size);
    } else if (showMoon) {
      _drawMoon(canvas, size);
    }

    // Draw stars if night
    if (showMoon && weatherCode <= 3) {
      _drawStars(canvas, size);
    }

    // Sort clouds by layer for depth effect
    final sortedClouds = List<Cloud>.from(clouds)
      ..sort((a, b) => a.layer.compareTo(b.layer));

    // Draw clouds with depth
    for (var cloud in sortedClouds) {
      final layerBlur = cloud.layer * 2.0;
      _drawRealisticCloud(canvas, size, cloud, layerBlur);
    }
  }

  void _drawSun(Canvas canvas, Size size) {
    final sunPaint = Paint()
      ..color = Colors.orange.withOpacity(0.9)
      ..style = PaintingStyle.fill;

    final sunPosition = Offset(size.width * 0.85, size.height * 0.12);
    
    // Sun glow
    final glowPaint = Paint()
      ..color = Colors.orange.withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawCircle(sunPosition, 55, glowPaint);
    
    // Sun circle
    canvas.drawCircle(sunPosition, 35, sunPaint);
    
    // Sun rays
    final rayPaint = Paint()
      ..color = Colors.orange.withOpacity(0.6)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 12; i++) {
      final angle = (i * math.pi / 6) + (animationValue * math.pi * 0.5);
      final start = sunPosition + Offset(
        math.cos(angle) * 45,
        math.sin(angle) * 45,
      );
      final end = sunPosition + Offset(
        math.cos(angle) * 65,
        math.sin(angle) * 65,
      );
      canvas.drawLine(start, end, rayPaint);
    }
  }

  void _drawMoon(Canvas canvas, Size size) {
    final moonPosition = Offset(size.width * 0.85, size.height * 0.12);
    
    // Moon glow
    final glowPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(moonPosition, 50, glowPaint);
    
    // Moon
    final moonPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(moonPosition, 30, moonPaint);
    
    // Moon craters
    final craterPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(moonPosition + const Offset(-8, -5), 6, craterPaint);
    canvas.drawCircle(moonPosition + const Offset(10, 8), 4, craterPaint);
    canvas.drawCircle(moonPosition + const Offset(5, -12), 5, craterPaint);
  }

  void _drawStars(Canvas canvas, Size size) {
    final starPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final random = math.Random(42); // Fixed seed for consistent stars
    for (int i = 0; i < 50; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height * 0.6;
      final twinkle = (math.sin((animationValue * math.pi * 2) + i) + 1) / 2;
      canvas.drawCircle(
        Offset(x, y),
        1 + random.nextDouble(),
        starPaint..color = Colors.white.withOpacity(0.3 + twinkle * 0.4),
      );
    }
  }

  void _drawRealisticCloud(Canvas canvas, Size size, Cloud cloud, double blur) {
    // Move cloud based on animation
    double x = (cloud.x + (animationValue * cloud.speed)) % 1.2 - 0.1;
    double y = cloud.y;

    final cloudX = x * size.width;
    final cloudY = y * size.height;

    final baseSize = cloud.size * (1.0 + cloud.layer * 0.12);

    // Create more realistic cloud with varied opacity
    final circles = [
      // Main body - larger circles
      CloudCircle(Offset(0, 0), baseSize * 0.55, 1.0),
      CloudCircle(Offset(baseSize * 0.45, -baseSize * 0.18), baseSize * 0.65, 0.95),
      CloudCircle(Offset(baseSize * 0.85, -baseSize * 0.08), baseSize * 0.50, 0.90),
      CloudCircle(Offset(baseSize * 1.15, baseSize * 0.05), baseSize * 0.42, 0.85),
      
      // Fill in gaps
      CloudCircle(Offset(baseSize * 0.22, -baseSize * 0.05), baseSize * 0.48, 0.92),
      CloudCircle(Offset(baseSize * 0.65, baseSize * 0.05), baseSize * 0.52, 0.88),
      
      // Bottom soft edges
      CloudCircle(Offset(-baseSize * 0.28, baseSize * 0.08), baseSize * 0.38, 0.80),
      CloudCircle(Offset(baseSize * 0.15, baseSize * 0.15), baseSize * 0.40, 0.75),
      CloudCircle(Offset(baseSize * 0.92, baseSize * 0.12), baseSize * 0.35, 0.78),
    ];

    // Draw circles with proper blending
    for (var circle in circles) {
      final paint = Paint()
        ..color = Colors.white.withOpacity(cloud.opacity * circle.opacityMultiplier)
        ..style = PaintingStyle.fill;

      if (blur > 0) {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur + 1.5);
      } else {
        // Even foreground clouds get slight blur for soft edges
        paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
      }

      canvas.drawCircle(
        Offset(cloudX + circle.offset.dx, cloudY + circle.offset.dy),
        circle.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CloudPainter oldDelegate) => true;
}

class CloudCircle {
  final Offset offset;
  final double radius;
  final double opacityMultiplier;

  CloudCircle(this.offset, this.radius, this.opacityMultiplier);
}

