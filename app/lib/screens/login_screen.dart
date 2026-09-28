import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../providers/auth_provider.dart';
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
  final _display = TextEditingController();
  final _email = TextEditingController();
  bool _remember = true;
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final device = await AuthProvider.deviceId();
    final err = _register
        ? await auth.register(_user.text.trim(), _pass.text,
            _display.text.trim(), _email.text.trim(), device, _remember)
        : await auth.login(
            _user.text.trim(), _pass.text, device, _remember);
    setState(() => _busy = false);
    if (err != null) {
      setState(() => _error = err);
    } else if (mounted) {
      if (_register) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Account gemaakt! Check je e-mail om te bevestigen.')));
      }
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
                decoration: const InputDecoration(
                    labelText: 'Gebruikersnaam of e-mailadres',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: true,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                    labelText: 'Wachtwoord', border: OutlineInputBorder()),
              ),
              if (_register) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
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
