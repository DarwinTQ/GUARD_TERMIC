import 'package:flutter/material.dart';

import 'pantallas/pantalla_principal.dart';

void main() => runApp(const AppTermicGuard());

/// Monitor de temperaturas de nodos ESP32 en tiempo real.
///
/// Un solo codigo para movil, desktop y web: el tiempo real entra por MQTT
/// sobre WebSocket (ver `servicios/mqtt/`) y el historial por la API REST.
/// La navegacion entre vistas vive en `pantallas/pantalla_principal.dart`.
class AppTermicGuard extends StatelessWidget {
  const AppTermicGuard({super.key});

  static const Color _semilla = Color(0xFF1864AB);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TermicGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: _semilla,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: _semilla,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      // Sigue el tema del sistema: en desktop y web se nota.
      themeMode: ThemeMode.system,
      home: const PantallaPrincipal(),
    );
  }
}
