import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../services/auth_service.dart';
import 'login_page.dart';

class ForgotPasswordOtpPage extends StatefulWidget {
  final int userId;

  const ForgotPasswordOtpPage({super.key, required this.userId});

  @override
  State<ForgotPasswordOtpPage> createState() => _ForgotPasswordOtpPageState();
}

class _ForgotPasswordOtpPageState extends State<ForgotPasswordOtpPage> {
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isResendLoading = false;
  int _secondsRemaining = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
  }

  Future<void> _submit() async {
    final otp = _otpController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (otp.length != 6) {
      Fluttertoast.showToast(
        msg: 'Enter the 6-digit OTP',
        backgroundColor: Colors.orange,
        textColor: Colors.white,
      );
      return;
    }

    if (newPassword.isEmpty || newPassword.length < 6) {
      Fluttertoast.showToast(
        msg: 'Password must be at least 6 characters',
        backgroundColor: Colors.orange,
        textColor: Colors.white,
      );
      return;
    }

    if (newPassword != confirmPassword) {
      Fluttertoast.showToast(
        msg: 'Passwords do not match',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      print('[ForgotOtp] Submitting OTP for user_id=${widget.userId}, otp=$otp');
      final response = await _authService.verifyForgotOtp(
        userId: widget.userId,
        otp: otp,
        newPassword: newPassword,
      );

      print('[ForgotOtp] Verify response: $response');
      setState(() => _isLoading = false);

      if (response['status'] == true) {
        Fluttertoast.showToast(
          msg: response['message'] ?? 'Password changed successfully',
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
        }
      } else {
        Fluttertoast.showToast(
          msg: response['message'] ?? 'OTP verification failed',
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      print('[ForgotOtp] Verify error: $e');
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

    print('[ForgotOtp] Resend OTP tapped. user_id=${widget.userId}');
    setState(() => _isResendLoading = true);

    try {
      final response = await _authService.resendForgotOtp(userId: widget.userId);

      print('[ForgotOtp] Resend response: $response');
      Fluttertoast.showToast(
        msg: response['message'] ?? 'OTP resent successfully',
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );

      _startResendCountdown();
    } catch (e) {
      print('[ForgotOtp] Resend error: $e');
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
                'Reset password',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Enter OTP and set a new password.',
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
              const SizedBox(height: 12),
              _inputCard(
                child: TextField(
                  controller: _newPasswordController,
                  obscureText: _obscureNewPassword,
                  decoration: InputDecoration(
                    hintText: 'New password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNewPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: Colors.grey.shade700,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureNewPassword = !_obscureNewPassword;
                        });
                      },
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _inputCard(
                child: TextField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    hintText: 'Confirm password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: Colors.grey.shade700,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
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
                          'Update password',
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







