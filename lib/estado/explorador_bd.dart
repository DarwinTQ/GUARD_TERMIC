import 'package:flutter/foundation.dart';

import '../config/ajustes.dart';
import '../modelos/estadistica_nodo.dart';
import '../modelos/lectura.dart';
import '../modelos/resumen_bd.dart';
import '../servicios/api_rest.dart';

/// Estado de la vista de base de datos: lo que hay realmente persistido.
///
/// Vive aparte de `MonitorControlador` a proposito. El monitor no puede
/// bloquearse ni perder tiempo real por una consulta pesada a Mongo, y esta
/// vista no necesita refrescarse a 1 Hz: se carga bajo demanda y se queda
/// quieta hasta que el usuario pide otra pagina.
///
/// Usa su propio cliente HTTP, de modo que una consulta lenta aqui no ocupa
/// la conexion que el monitor usa para sondear la API.
class ExploradorBd extends ChangeNotifier {
  ExploradorBd({ApiRest? api}) : _api = api ?? ApiRest();

  final ApiRest _api;

  bool _cargando = false;
  bool _liberado = false;
  String? _error;

  ResumenBd? _resumen;
  List<EstadisticaNodo> _estadisticas = const [];
  List<Lectura> _lecturas = const [];
  int _total = 0;
  int _pagina = 0;
  String? _dispositivo;
  DateTime? _consultadoEn;

  // ------------------------------------------------------------- lectura UI

  bool get cargando => _cargando;
  String? get error => _error;
  ResumenBd? get resumen => _resumen;
  List<EstadisticaNodo> get estadisticas => List.unmodifiable(_estadisticas);
  List<Lectura> get lecturas => List.unmodifiable(_lecturas);

  /// Lecturas que cumplen el filtro actual, no las de la pagina.
  int get total => _total;
  int get pagina => _pagina;
  String? get dispositivo => _dispositivo;
  DateTime? get consultadoEn => _consultadoEn;
  bool get vacio => _total == 0 && !_cargando && _error == null;

  int get paginas =>
      _total == 0 ? 1 : (_total + Ajustes.filasPorPagina - 1) ~/ Ajustes.filasPorPagina;

  bool get hayAnterior => _pagina > 0;
  bool get haySiguiente => (_pagina + 1) * Ajustes.filasPorPagina < _total;

  /// Numero de fila global de la primera lectura de la pagina (1-indexado).
  int get primeraFila => _total == 0 ? 0 : _pagina * Ajustes.filasPorPagina + 1;
  int get ultimaFila =>
      (_pagina * Ajustes.filasPorPagina + _lecturas.length).clamp(0, _total);

  /// Nodos presentes en la base, para poblar el desplegable de filtro.
  List<String> get dispositivosConocidos =>
      [for (final e in _estadisticas) e.dispositivo];

  // ----------------------------------------------------------------- acciones

  /// Carga todo lo que muestra la vista: resumen, agregados y primera pagina.
  Future<void> cargar() async {
    _cargando = true;
    _error = null;
    _avisar();

    try {
      // En paralelo: son tres consultas independientes contra la misma API.
      final resultados = await Future.wait([
        _api.resumenBd(),
        _api.estadisticas(),
        _api.totalLecturas(dispositivo: _dispositivo),
        _api.lecturas(
          desplazamiento: _pagina * Ajustes.filasPorPagina,
          dispositivo: _dispositivo,
        ),
      ]);

      if (_liberado) return;
      _resumen = resultados[0] as ResumenBd;
      _estadisticas = resultados[1] as List<EstadisticaNodo>;
      _total = resultados[2] as int;
      _lecturas = resultados[3] as List<Lectura>;
      _consultadoEn = DateTime.now();
      _error = null;
    } catch (error) {
      _error = 'No se pudo consultar ${_api.urlBase}: $error';
      debugPrint('Explorador de BD: $error');
    } finally {
      _cargando = false;
      _avisar();
    }
  }

  /// Recarga solo la tabla; el resumen y los agregados no cambian al paginar.
  Future<void> _cargarPagina() async {
    _cargando = true;
    _avisar();
    try {
      final lecturas = await _api.lecturas(
        desplazamiento: _pagina * Ajustes.filasPorPagina,
        dispositivo: _dispositivo,
      );
      if (_liberado) return;
      _lecturas = lecturas;
      _consultadoEn = DateTime.now();
      _error = null;
    } catch (error) {
      _error = 'No se pudo cargar la pagina: $error';
    } finally {
      _cargando = false;
      _avisar();
    }
  }

  Future<void> paginaSiguiente() async {
    if (!haySiguiente || _cargando) return;
    _pagina++;
    await _cargarPagina();
  }

  Future<void> paginaAnterior() async {
    if (!hayAnterior || _cargando) return;
    _pagina--;
    await _cargarPagina();
  }

  /// Cambia el filtro por nodo y vuelve a la primera pagina.
  ///
  /// Hay que recontar: el total depende del filtro y, sin recontar, la
  /// paginacion quedaria apuntando a filas que ya no existen.
  Future<void> filtrarPor(String? dispositivo) async {
    if (_dispositivo == dispositivo) return;
    _dispositivo = dispositivo;
    _pagina = 0;
    _cargando = true;
    _avisar();
    try {
      final total = await _api.totalLecturas(dispositivo: dispositivo);
      final lecturas = await _api.lecturas(dispositivo: dispositivo);
      if (_liberado) return;
      _total = total;
      _lecturas = lecturas;
      _consultadoEn = DateTime.now();
      _error = null;
    } catch (error) {
      _error = 'No se pudo aplicar el filtro: $error';
    } finally {
      _cargando = false;
      _avisar();
    }
  }

  void _avisar() {
    if (_liberado) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _liberado = true;
    _api.cerrar();
    super.dispose();
  }
}
