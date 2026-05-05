import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MachMateApp());
}

class MachMateApp extends StatelessWidget {
  const MachMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MachMate Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFFFA500),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFA500),
          primary: const Color(0xFFFFA500),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: const Color(0xFFFFA500).withOpacity(0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: const Color(0xFFFFA500).withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFFFA500), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFA500),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            elevation: 4,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFFFA500),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const AuthCheckWrapper(),
    );
  }
}

class AuthCheckWrapper extends StatefulWidget {
  const AuthCheckWrapper({super.key});

  @override
  State<AuthCheckWrapper> createState() => _AuthCheckWrapperState();
}

class _AuthCheckWrapperState extends State<AuthCheckWrapper> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await _checkPopup();
    await _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final isLoggedIn = await _authService.isLoggedIn();
    setState(() {
      _isLoggedIn = isLoggedIn;
      _isLoading = false;
    });
  }

  Future<void> _checkPopup() async {
    try {
      final resp = await http.get(
        Uri.parse('${ApiService.baseUrl}/popup/'),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;

        if (data['show'] == true) {
          final String message = (data['message'] ?? '').toString();
          final String buttonName = (data['button_name'] ?? 'OK').toString();
          final String buttonUrl = (data['button_url'] ?? '').toString();

          if (!mounted) return;
          await _showUpdatePopup(context, message, buttonName, buttonUrl);
        }
      }
    } catch (_) {
      // Silently ignore popup errors; app continues normally.
    }
  }

  Future<void> _showUpdatePopup(
    BuildContext context,
    String message,
    String btnName,
    String btnUrl,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Important Update',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          content: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () {
                SystemNavigator.pop();
              },
              child: Text(
                'Close App',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                if (btnUrl.isEmpty) {
                  Navigator.of(ctx).pop();
                } else {
                  final uri = Uri.parse(btnUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                  }
                  Navigator.of(ctx).pop();
                }
              },
              child: Text(
                btnName,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: AssemblyLogo(
            child: Image.asset(
              'assets/splash_logo.png',
              width: 200,
              height: 200,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    }

    return _isLoggedIn ? HomePage() : const LoginPage();
  }
}

class AssemblyLogo extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const AssemblyLogo({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<AssemblyLogo> createState() => _AssemblyLogoState();
}

class _AssemblyLogoState extends State<AssemblyLogo> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final int _strips = 10;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(_strips, (index) {
            final isEven = index % 2 == 0;
            final start = (index / _strips) * 0.4;
            final end = start + 0.6;
            final animation = CurvedAnimation(
              parent: _controller,
              curve: Interval(start, end, curve: Curves.easeOutCubic),
            );
            
            final offset = isEven ? (1.0 - animation.value) * -150 : (1.0 - animation.value) * 150;
            final opacity = animation.value.clamp(0.0, 1.0);

            return Transform.translate(
              offset: Offset(offset, 0),
              child: Opacity(
                opacity: opacity,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment(0, -1.0 + (index / (_strips - 1)) * 2.0),
                    heightFactor: 1.0 / _strips,
                    widthFactor: 1.0,
                    child: widget.child,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
