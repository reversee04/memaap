import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _isResponderMode = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Submits the login form and calls the real backend login API.
  Future<void> _submitLogin() async {
    if (!_formKey.currentState!.validate()) return;

    // Prefix the country code if the user omitted it
    final rawPhone = _phoneController.text.trim();
    final phone = rawPhone.startsWith('+') ? rawPhone : '+265$rawPhone';

    await AuthService.loginUser(
      context,
      phone,
      _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),

                // ── Logo & header ────────────────────────────────────────────
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      LucideIcons.briefcase,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Malawi Medical SOS',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.mapPin, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'BLANTYRE • LILONGWE',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.grey[600],
                            letterSpacing: 1.2,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),

                // ── Guest (no account) shortcut ──────────────────────────────
                InkWell(
                  onTap: () => context.go('/home'),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'IMMEDIATE ACCESS',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Continue as Guest',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Icon(LucideIcons.arrowRight, color: Colors.white),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Divider ──────────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[300])),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'OR SECURE SIGN IN',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey[300])),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Role toggle ──────────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _isResponderMode = false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: !_isResponderMode
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  LucideIcons.user,
                                  size: 16,
                                  color: !_isResponderMode
                                      ? Colors.white
                                      : Colors.grey[600],
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Patient',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: !_isResponderMode
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
                          onTap: () =>
                              setState(() => _isResponderMode = true),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _isResponderMode
                                  ? Theme.of(context).colorScheme.secondary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  LucideIcons.shield,
                                  size: 16,
                                  color: _isResponderMode
                                      ? Colors.white
                                      : Colors.grey[600],
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Responder',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _isResponderMode
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
                const SizedBox(height: 20),

                // ── Sign-in card ─────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Phone field
                      Text(
                        'MOBILE NUMBER',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12.0),
                              child: Text(
                                '+265',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 24,
                              color: Colors.grey[300],
                            ),
                            Expanded(
                              child: TextFormField(
                                controller: _phoneController,
                                focusNode: _phoneFocus,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                onFieldSubmitted: (_) => FocusScope.of(context)
                                    .requestFocus(_passwordFocus),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  hintText: '990 000 000',
                                  hintStyle:
                                      TextStyle(color: Colors.grey[400]),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 14),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Phone number is required';
                                  }
                                  final digits =
                                      value.replaceAll(RegExp(r'\D'), '');
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

                      // Password field
                      Text(
                        'PASSWORD',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextFormField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submitLogin(),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: '••••••••',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                            prefixIcon: Icon(LucideIcons.lock,
                                size: 18, color: Colors.grey[500]),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? LucideIcons.eyeOff
                                    : LucideIcons.eye,
                                size: 18,
                                color: Colors.grey[500],
                              ),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
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
                      const SizedBox(height: 24),

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _submitLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isResponderMode
                                ? Theme.of(context).colorScheme.secondary
                                : Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: Icon(_isResponderMode
                              ? LucideIcons.shield
                              : LucideIcons.key),
                          label: Text(
                            _isResponderMode
                                ? 'Sign in as Responder'
                                : 'Sign in with Phone',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Register link
                      Center(
                        child: TextButton(
                          onPressed: () => context.go('/register'),
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 13),
                              children: [
                                const TextSpan(text: "Don't have an account? "),
                                TextSpan(
                                  text: 'Register',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
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
                const SizedBox(height: 32),

                // ── Feature highlights ───────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(LucideIcons.shieldCheck,
                                color: Colors.teal),
                            const SizedBox(height: 12),
                            const Text(
                              'Emergency Ready',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Instant routing to nearest hospitals',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(LucideIcons.headphones,
                                color:
                                    Theme.of(context).colorScheme.secondary),
                            const SizedBox(height: 12),
                            const Text(
                              '24/7 Dispatch',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Live operator support available',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 48),

                // ── Footer ────────────────────────────────────────────────────
                Center(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      children: [
                        const TextSpan(text: 'By continuing, you agree to our '),
                        TextSpan(
                          text: 'Emergency Protocols',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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
