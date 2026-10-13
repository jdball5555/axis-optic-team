import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/app_version.dart';

class AuthView extends ConsumerStatefulWidget {
  final String? setupEmail;
  final String? setupFirstName;
  final String? setupLastName;
  final String? setupMemberId;
  final String? setupStoreId;

  const AuthView({
    super.key,
    this.setupEmail,
    this.setupFirstName,
    this.setupLastName,
    this.setupMemberId,
    this.setupStoreId,
  });

  @override
  ConsumerState<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends ConsumerState<AuthView> {
  bool _isLogin = true;
  bool _rememberDevice = false;

  // Login controllers
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Signup controllers
  final _signupFirstController = TextEditingController();
  final _signupLastController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _signupConfirmPasswordController = TextEditingController();

  // Temp Stores
  List<String> _selectedStores = [];
  bool _isLoading = false;
  String? _errorMessage;

  bool _needsPasswordReset = false;
  String _resetUserId = '';
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.setupEmail != null || widget.setupMemberId != null) {
      _isLogin = false;
      _signupEmailController.text = widget.setupEmail ?? '';
      _signupFirstController.text = widget.setupFirstName ?? '';
      _signupLastController.text = widget.setupLastName ?? '';
    } else {
      _checkRememberedUser();
    }
  }

  Future<void> _checkRememberedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email');
    final savedPassword = prefs.getString('saved_password');
    if (savedEmail != null && savedPassword != null) {
      if (mounted) {
        setState(() {
          _loginEmailController.text = savedEmail;
          _loginPasswordController.text = savedPassword;
          _rememberDevice = true;
        });
      }
      _handleLogin();
    }
  }

  @override
  void dispose() {
    _signupFirstController.dispose();
    _signupLastController.dispose();
    _signupEmailController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _signupPasswordController.dispose();
    _signupConfirmPasswordController.dispose();
    super.dispose();
  }

  String _sanitizeError(dynamic error, [String? defaultMessage]) {
    final errorString = error.toString();
    debugPrint('Authentication error: $errorString');
    if (errorString.contains('pigeon') ||
        errorString.contains('PlatformException')) {
      return 'Sign-in service error: $errorString';
    }
    return defaultMessage ?? errorString;
  }

  Future<void> _handleLogin() async {
    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter both email and password');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final uid = userCredential.user!.uid;

      // Fetch user role from Firestore by uid
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!doc.exists) {
        if (mounted)
          setState(() => _errorMessage = 'User profile not found in database');
        return;
      }

      final data = doc.data()!;

      // Temporarily bypass needs_password_reset since we're using Firebase Auth now
      // (You can still implement custom forced-reset flows later if desired)

      ref.read(currentUserProvider.notifier).state = {'id': uid, ...data};

      // Auto select store to 'All Stores'
      ref.read(currentStoreIdProvider.notifier).state = null;

      final prefs = await SharedPreferences.getInstance();
      if (_rememberDevice) {
        await prefs.setString('saved_email', email);
        await prefs.setString('saved_password', password);
      } else {
        await prefs.remove('saved_email');
        await prefs.remove('saved_password');
      }

      if (mounted) {
        if (data['role'] == 'team_member') {
          context.go('/team_member_dashboard');
        } else {
          context.go('/dashboard');
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code == 'invalid-email') {
          setState(() => _errorMessage = 'The email address is invalid.');
        } else if (e.code == 'invalid-credential' ||
            e.code == 'wrong-password' ||
            e.code == 'user-not-found') {
          setState(() => _errorMessage = 'Invalid email or password.');
        } else {
          setState(
            () => _errorMessage = _sanitizeError(
              e,
              e.message ?? 'Authentication failed',
            ),
          );
        }
      }
    } catch (e) {
      if (mounted)
        setState(() => _errorMessage = _sanitizeError(e, 'Error: $e'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePasswordResetSubmit() async {
    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;

    if (newPass.isEmpty || newPass != confirmPass) {
      setState(() => _errorMessage = 'Passwords do not match or are empty.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_resetUserId)
          .update({'password': newPass, 'needs_password_reset': false});

      // Fetch the updated user data
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_resetUserId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        ref.read(currentUserProvider.notifier).state = {
          'id': _resetUserId,
          ...data,
        };

        ref.read(currentStoreIdProvider.notifier).state = null;

        if (mounted) {
          if (data['role'] == 'team_member') {
            context.go('/team_member_dashboard');
          } else {
            context.go('/dashboard');
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignup() async {
    final first = _signupFirstController.text.trim();
    final last = _signupLastController.text.trim();
    final email = _signupEmailController.text.trim();
    final pass = _signupPasswordController.text;
    final confirmPass = _signupConfirmPasswordController.text;

    if (first.isEmpty || last.isEmpty || email.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields');
      return;
    }

    if (pass != confirmPass) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Create user in Firebase Auth
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass);
      final uid = userCredential.user!.uid;

      // Create user globally
      final isTeamMemberSetup =
          widget.setupMemberId != null && widget.setupStoreId != null;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'first_name': first,
        'last_name': last,
        'email': email,
        'role': isTeamMemberSetup ? 'team_member' : 'owner',
        if (isTeamMemberSetup) 'storeId': widget.setupStoreId,
        if (isTeamMemberSetup) 'userId': widget.setupMemberId,
        if (!isTeamMemberSetup) 'owned_stores': _selectedStores,
      });

      if (isTeamMemberSetup) {
        await FirebaseFirestore.instance
            .collection('stores')
            .doc(widget.setupStoreId)
            .collection('users')
            .doc(widget.setupMemberId)
            .update({'email': email});
      }

      if (mounted) {
        setState(() {
          _isLogin = true;
          _loginEmailController.text = email;
          _loginPasswordController.text = pass;
        });
        _handleLogin(); // Auto login after signup
      }
    } on FirebaseAuthException catch (e) {
      if (mounted)
        setState(
          () => _errorMessage = _sanitizeError(e, e.message ?? 'Signup failed'),
        );
    } catch (e) {
      if (mounted)
        setState(() => _errorMessage = _sanitizeError(e, 'Error: $e'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _loginEmailController.text.trim();
    if (email.isEmpty) {
      setState(
        () => _errorMessage =
            'Please enter your email address to reset your password.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email sent! Please check your inbox.')),
        );
        setState(() => _errorMessage = 'Password reset email sent to $email');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(
          () => _errorMessage = _sanitizeError(
            e,
            e.message ?? 'Failed to send reset email',
          ),
        );
      }
    } catch (e) {
      if (mounted)
        setState(() => _errorMessage = _sanitizeError(e, 'Error: $e'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showStoreSelector() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: const Text('Select Stores to be added to'),
          content: SizedBox(
            width: 400,
            child: Consumer(
              builder: (context, ref, _) {
                final allStoresAsync = ref.watch(allStoresStreamProvider);
                return allStoresAsync.when(
                  data: (stores) {
                    return StatefulBuilder(
                      builder: (context, setDialogState) {
                        return ListView(
                          shrinkWrap: true,
                          children: stores.map((s) {
                            final storeId = s['id'] as String;
                            final storeName = s['name'] as String? ?? 'Unknown';
                            return CheckboxListTile(
                              title: Text(storeName),
                              value: _selectedStores.contains(storeId),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) {
                                    _selectedStores.add(storeId);
                                  } else {
                                    _selectedStores.remove(storeId);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, st) => Text('Error: $e'),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_needsPasswordReset) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              color: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Theme.of(context).dividerColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Create Your Password',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Please set a permanent password for your account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm Password',
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : _handlePasswordResetSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Update Password & Login',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        // Scrolls on short / phone screens (and above the keyboard).
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isLogin ? 'Login' : 'Create Account',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              const SizedBox(height: 24),
              if (_isLogin) ...[
                TextField(
                  controller: _loginEmailController,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _loginPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _rememberDevice,
                          onChanged: (val) {
                            setState(() => _rememberDevice = val ?? false);
                          },
                          activeColor: AppTheme.redLight,
                        ),
                        const Text('Remember this device'),
                      ],
                    ),
                    TextButton(
                      onPressed: _isLoading ? null : _handleForgotPassword,
                      child: const Text('Forgot Password?'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.redLight,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Login'),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _signupFirstController,
                  readOnly:
                      widget.setupFirstName != null &&
                      widget.setupFirstName!.isNotEmpty,
                  decoration: InputDecoration(
                    labelText: 'First Name',
                    border: const OutlineInputBorder(),
                    filled:
                        widget.setupFirstName != null &&
                        widget.setupFirstName!.isNotEmpty,
                    fillColor: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.05),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _signupLastController,
                  readOnly:
                      widget.setupLastName != null &&
                      widget.setupLastName!.isNotEmpty,
                  decoration: InputDecoration(
                    labelText: 'Last Name',
                    border: const OutlineInputBorder(),
                    filled:
                        widget.setupLastName != null &&
                        widget.setupLastName!.isNotEmpty,
                    fillColor: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.05),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _signupEmailController,
                  readOnly:
                      widget.setupEmail != null &&
                      widget.setupEmail!.isNotEmpty,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    border: const OutlineInputBorder(),
                    filled:
                        widget.setupEmail != null &&
                        widget.setupEmail!.isNotEmpty,
                    fillColor: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.05),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _signupPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _signupConfirmPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _showStoreSelector,
                    child: Text(
                      'Add user to stores (${_selectedStores.length} selected)',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSignup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.redLight,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Create Account'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(
                  _isLogin
                      ? 'Need an account? Create one'
                      : 'Already have an account? Login',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'v$appVersion',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
