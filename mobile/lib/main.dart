import 'package:flutter/material.dart';

import 'screens.dart';
import 'state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  app.init();
  runApp(const ShopLiteApp());

}

class ShopLiteApp extends StatelessWidget {
  const ShopLiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShopLite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1F6F5C), useMaterial3: true),
      home: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (!app.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          // Not const on purpose: a new widget each time makes the screen redraw when app changes.
          return app.loggedIn ? HomeScreen() : LoginScreen();
        },
      ),
    );
  }
}
