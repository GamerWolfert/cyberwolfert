import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_logo.dart';
import '../widgets/made_by.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _register = false;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _display = TextEditingController();
  final _email = TextEditingController();
  bool _remember = true;
  String? _error;
  bool _busy = false;

  // Gebruikersnaam altijd klein (ook met Shift/Caps aan)
  static final _lower = TextInputFormatter.withFunction(
      (oldV, newV) => newV.copyWith(text: newV.text.toLowerCase()));

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final user = _user.text.trim().toLowerCase();
    if (_register) {
      if (_display.text.trim().isEmpty) {
        setState(() => _error = 'Vul een weergavenaam in.');
        return;
      }
      if (user.length < 3) {
        setState(() => _error = 'Gebruikersnaam minimaal 3 tekens.');
        return;
      }
      if (_pass.text.length < 6) {
        setState(() => _error = 'Wachtwoord minimaal 6 tekens.');
        return;
      }
      if (_pass.text != _pass2.text) {
        setState(() => _error = 'Wachtwoorden komen niet overeen.');
        return;
      }
      if (!_email.text.contains('@')) {
        setState(() => _error = 'Vul een geldig e-mailadres in.');
        return;
      }
    } else if (_pass.text.isEmpty) {
      setState(() => _error = 'Vul je wachtwoord in.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final device = await AuthProvider.deviceId();
    final err = _register
        ? await auth.register(
            user, _pass.text, _display.text.trim(), _email.text.trim(), device, _remember)
        : await auth.login(user, _pass.text, device, _remember);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      setState(() => _error = err);
    } else if (mounted) {
      if (_register) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Account gemaakt! Check je e-mail om te bevestigen.')));
      }
      context.read<SettingsProvider>().load();
      Navigator.pop(context, true);
    }
  }

  Future<void> _google() async {
    final auth = context.read<AuthProvider>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final status = await auth.googleStatus();
    if (status != null) {
      setState(() {
        _busy = false;
        _error = status;
      });
      return;
    }
    try {
      final account = await GoogleSignIn(scopes: ['email', 'profile']).signIn();
      if (account == null) {
        setState(() => _busy = false);
        return;
      }
      final gauth = await account.authentication;
      final idToken = gauth.idToken;
      if (idToken == null) throw Exception('geen id_token');
      final r = await http
          .post(Uri.parse('${AppConfig.baseUrl}/auth/google'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'id_token': idToken}))
          .timeout(const Duration(seconds: 12));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200) throw Exception((j['error'] ?? 'mislukt').toString());
      await AuthStore.set(j['token'] as String?);
      await auth.load();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error =
          'Google-login lukt niet vanaf dit apparaat. Zet een OAuth Client-ID in de app-config.');
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_register ? 'Account maken' : 'Inloggen')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(children: [
              const AppLogo(size: 90),
              const SizedBox(height: 16),
              Text(_register ? 'Maak je CyberWolfert-account' : 'Log in op CyberWolfert',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Per account: eigen instellingen, geschiedenis en AI-geheugen.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (_register)
                TextField(
                  controller: _display,
                  decoration: const InputDecoration(
                      labelText: 'Weergavenaam', border: OutlineInputBorder()),
                ),
              if (_register) const SizedBox(height: 12),
              TextField(
                controller: _user,
                textInputAction: TextInputAction.next,
                inputFormatters: [_lower],
                decoration: const InputDecoration(
                    labelText: 'Gebruikersnaam (kleine letters)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: true,
                textInputAction:
                    _register ? TextInputAction.next : TextInputAction.done,
                onSubmitted: (_) => _register ? null : _submit(),
                decoration: const InputDecoration(
                    labelText: 'Wachtwoord', border: OutlineInputBorder()),
              ),
              if (_register) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _pass2,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                      labelText: 'Wachtwoord bevestigen',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                      labelText: 'E-mailadres (voor bevestiging)',
                      border: OutlineInputBorder()),
                ),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Ingelogd blijven op dit apparaat',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text('Slaat gegevens voor dit apparaat op',
                    style: TextStyle(fontSize: 11, color: Colors.white54)),
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? true),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 12),
              _busy
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submit,
                        child: Text(_register ? 'Account maken' : 'Inloggen'),
                      ),
                    ),
              TextButton(
                onPressed: () => setState(() {
                  _register = !_register;
                  _error = null;
                }),
                child: Text(_register
                    ? 'Al een account? Log in'
                    : 'Nog geen account? Maak er een'),
              ),
              const Divider(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _google,
                  icon: const Text('G',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF29B6F6))),
                  label: const Text('Inloggen met Google'),
                ),
              ),
              const SizedBox(height: 16),
              const MadeBy(),
            ]),
          ),
        ),
      ),
    );
  }
}
