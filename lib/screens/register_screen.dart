import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/user_registration_model.dart';
import '../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String _selectedRole = 'patient'; // patient or responder

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  Future<void> _submitRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final rawPhone = _phoneController.text.trim();
    final phone = rawPhone.startsWith('+') ? rawPhone : '+265$rawPhone';

    final registrationModel = UserRegistrationModel(
      name: _nameController.text.trim(),
      phone: phone,
      email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      password: _passwordController.text,
      confirmPassword: _confirmPasswordController.text,
      role: _selectedRole,
    );

    await AuthService.registerUser(context, registrationModel);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final secondaryColor = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),

                // Back Button
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(LucideIcons.arrowLeft),
                    onPressed: () => context.go('/login'),
                  ),
                ),
                const SizedBox(height: 10),

                // Header
                Text(
                  'Create Account',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Join Malawi Medical SOS as a patient or a medical responder.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 32),

                // Role Selector Switcher
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedRole = 'patient'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _selectedRole == 'patient'
                                  ? primaryColor
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  LucideIcons.user,
                                  size: 16,
                                  color: _selectedRole == 'patient'
                                      ? Colors.white
                                      : Colors.grey[600],
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Patient',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _selectedRole == 'patient'
                                        ? Colors.white
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedRole = 'responder'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _selectedRole == 'responder'
                                  ? secondaryColor
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  LucideIcons.shield,
                                  size: 16,
                                  color: _selectedRole == 'responder'
                                      ? Colors.white
                                      : Colors.grey[600],
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Responder',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _selectedRole == 'responder'
                                        ? Colors.white
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Form Fields Container
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Full Name
                      Text(
                        'FULL NAME',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextFormField(
                          controller: _nameController,
                          focusNode: _nameFocus,
                          keyboardType: TextInputType.name,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_phoneFocus),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'John Doe',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            prefixIcon: Icon(LucideIcons.user, size: 18, color: Colors.grey[500]),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Full name is required';
                            }
                            if (value.trim().length < 2) {
                              return 'Name must be at least 2 characters';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Phone Number
                      Text(
                        'MOBILE NUMBER',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14.0),
                              child: Text(
                                '+265',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                            Container(width: 1, height: 24, color: Colors.grey[300]),
                            Expanded(
                              child: TextFormField(
                                controller: _phoneController,
                                focusNode: _phoneFocus,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_emailFocus),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  hintText: '990 000 000',
                                  hintStyle: TextStyle(color: Colors.grey[400]),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Phone number is required';
                                  }
                                  final digits = value.replaceAll(RegExp(r'\D'), '');
                                  if (digits.length < 9) {
                                    return 'Enter a valid phone number';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Email Address (Optional)
                      Text(
                        'EMAIL ADDRESS (OPTIONAL)',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextFormField(
                          controller: _emailController,
                          focusNode: _emailFocus,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_passwordFocus),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'name@example.com',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            prefixIcon: Icon(LucideIcons.mail, size: 18, color: Colors.grey[500]),
                          ),
                          validator: (value) {
                            if (value != null && value.trim().isNotEmpty) {
                              final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                              if (!emailRegex.hasMatch(value.trim())) {
                                return 'Enter a valid email address';
                              }
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Password
                      Text(
                        'PASSWORD',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextFormField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_confirmPasswordFocus),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: '••••••••',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            prefixIcon: Icon(LucideIcons.lock, size: 18, color: Colors.grey[500]),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                                size: 18,
                                color: Colors.grey[500],
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Password is required';
                            }
                            if (value.length < 8) {
                              return 'Password must be at least 8 characters';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Confirm Password
                      Text(
                        'CONFIRM PASSWORD',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextFormField(
                          controller: _confirmPasswordController,
                          focusNode: _confirmPasswordFocus,
                          obscureText: _obscureConfirmPassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submitRegister(),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: '••••••••',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            prefixIcon: Icon(LucideIcons.lock, size: 18, color: Colors.grey[500]),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword ? LucideIcons.eyeOff : LucideIcons.eye,
                                size: 18,
                                color: Colors.grey[500],
                              ),
                              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Confirm your password';
                            }
                            if (value != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _submitRegister,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _selectedRole == 'responder' ? secondaryColor : primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(LucideIcons.userPlus),
                          label: const Text(
                            'Register Now',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Back to Login link
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/login'),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        children: [
                          const TextSpan(text: 'Already have an account? '),
                          TextSpan(
                            text: 'Login',
                            style: TextStyle(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
