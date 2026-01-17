import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../services/auth_service.dart';
import 'login_page.dart';

class SignupOtpPage extends StatefulWidget {
  final int userId;

  const SignupOtpPage({super.key, required this.userId});

  @override
  State<SignupOtpPage> createState() => _SignupOtpPageState();
}

class _SignupOtpPageState extends State<SignupOtpPage> {
  final TextEditingController _otpController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _isResendLoading = false;
  int _secondsRemaining = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      Fluttertoast.showToast(
        msg: 'Enter the 6-digit OTP',
        backgroundColor: Colors.orange,
        textColor: Colors.white,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      print('[SignupOtp] Verifying OTP for pending_user_id=${widget.userId}, otp=$otp');
      final response = await _authService.verifySignupOtp(
        userId: widget.userId,
        otp: otp,
      );

      print('[SignupOtp] Verify response: $response');
      setState(() => _isLoading = false);

      if (response['status'] == true) {
        if (mounted) {
          Fluttertoast.showToast(
            msg: response['message'] ?? 'Verification Successful',
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
        }
      } else {
        Fluttertoast.showToast(
          msg: response['message'] ?? 'Invalid OTP',
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      print('[SignupOtp] Verify error: $e');
      setState(() => _isLoading = false);
      Fluttertoast.showToast(
        msg: e
            .toString()
            .replaceAll('Exception: ', '')
            .replaceAll('Network error: ', ''),
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() {
      _secondsRemaining = 30;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _secondsRemaining = 0;
        });
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  Future<void> _resendOtp() async {
    if (_secondsRemaining > 0 || _isResendLoading) return;

    print('[SignupOtp] Resend OTP tapped. pending_user_id=${widget.userId}');
    setState(() => _isResendLoading = true);

    try {
      final response = await _authService.resendSignupOtp(userId: widget.userId);

      print('[SignupOtp] Resend response: $response');
      Fluttertoast.showToast(
        msg: response['message'] ?? 'OTP resent successfully',
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );

      _startResendCountdown();
    } catch (e) {
      print('[SignupOtp] Resend error: $e');
      Fluttertoast.showToast(
        msg: e
            .toString()
            .replaceAll('Exception: ', '')
            .replaceAll('Network error: ', ''),
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      if (mounted) {
        setState(() => _isResendLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7FA),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2C3E50)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Text(
                'OTP verification',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Enter the 6-digit code sent to your phone.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 18),
              _inputCard(
                child: TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    hintText: 'OTP',
                    counterText: '',
                    prefixIcon: Icon(Icons.password),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB8C1CC),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed:
                    (_secondsRemaining > 0 || _isResendLoading) ? null : _resendOtp,
                child: Text(
                  _secondsRemaining > 0
                      ? 'Resend OTP ($_secondsRemaining s)'
                      : 'Resend OTP',
                  style: const TextStyle(
                    color: Color(0xFF2C3E50),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            isDense: true,
          ),
        ),
        child: child,
      ),
    );
  }
}







