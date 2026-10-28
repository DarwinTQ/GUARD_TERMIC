/// Formateo de numeros, tiempos y tamaños para la interfaz.
///
/// Todo en un sitio para que la misma magnitud se lea igual en todas las
/// vistas: un intervalo de 4,8 s no puede aparecer como "4.80 s" en una
/// pantalla y como "4800 ms" en otra.
///
/// Sin `intl`: la app no necesita localizacion, solo una convencion fija.
class Formato {
  const Formato._();

  static String _dos(int valor) => valor.toString().padLeft(2, '0');

  /// `14:05:09`
  static String hora(DateTime fecha) =>
      '${_dos(fecha.hour)}:${_dos(fecha.minute)}:${_dos(fecha.second)}';

  /// `28/10 14:05:09`
  static String fechaHora(DateTime fecha) =>
      '${_dos(fecha.day)}/${_dos(fecha.month)} ${hora(fecha)}';

  /// `28/10/2026 14:05:09`
  static String fechaCompleta(DateTime fecha) =>
      '${_dos(fecha.day)}/${_dos(fecha.month)}/${fecha.year} ${hora(fecha)}';

  /// Milisegundos con un decimal: `12.4 ms`.
  static String milisegundos(double? valor, {String sinDato = '--'}) =>
      valor == null ? sinDato : '${valor.toStringAsFixed(1)} ms';

  /// Duracion con la unidad que mejor se lee a cada escala.
  ///
  /// Por debajo de un segundo se habla en ms (una latencia de 0,012 s no se
  /// interpreta de un vistazo); por encima de un minuto, en minutos.
  static String duracion(Duration? valor, {String sinDato = '--'}) {
    if (valor == null) return sinDato;
    final ms = valor.inMilliseconds;
    if (ms.abs() < 1000) return '$ms ms';
    if (ms.abs() < 60000) return '${(ms / 1000).toStringAsFixed(2)} s';
    final minutos = valor.inMinutes;
    final segundos = valor.inSeconds.remainder(60).abs();
    if (minutos.abs() < 60) return '$minutos m ${_dos(segundos)} s';
    final horas = valor.inHours;
    return '$horas h ${_dos(valor.inMinutes.remainder(60).abs())} m';
  }

  /// Duracion con signo explicito, para desvios respecto a un valor nominal.
  static String desvio(Duration? valor, {String sinDato = '--'}) {
    if (valor == null) return sinDato;
    final signo = valor.isNegative ? '-' : '+';
    return '$signo${duracion(Duration(microseconds: valor.inMicroseconds.abs()))}';
  }

  /// `hace 4 s`, `hace 2 m 10 s`, `nunca`.
  static String hace(DateTime? instante, {String sinDato = 'nunca'}) {
    if (instante == null) return sinDato;
    final transcurrido = DateTime.now().difference(instante);
    if (transcurrido.isNegative) return 'ahora';
    if (transcurrido.inSeconds < 1) return 'ahora';
    if (transcurrido.inSeconds < 60) return 'hace ${transcurrido.inSeconds} s';
    if (transcurrido.inMinutes < 60) {
      return 'hace ${transcurrido.inMinutes} m '
          '${_dos(transcurrido.inSeconds.remainder(60))} s';
    }
    if (transcurrido.inHours < 24) return 'hace ${transcurrido.inHours} h';
    return 'hace ${transcurrido.inDays} d';
  }

  /// Tamaño legible: `1.4 MB`.
  static String bytes(int? valor, {String sinDato = 'n/d'}) {
    if (valor == null) return sinDato;
    const unidades = ['B', 'KB', 'MB', 'GB', 'TB'];
    var numero = valor.toDouble();
    var indice = 0;
    while (numero >= 1024 && indice < unidades.length - 1) {
      numero /= 1024;
      indice++;
    }
    final decimales = indice == 0 ? 0 : 1;
    return '${numero.toStringAsFixed(decimales)} ${unidades[indice]}';
  }

  /// Enteros grandes con separador de millares: `12 480`.
  ///
  /// Espacio fino y no punto: en una tabla de lecturas, `12.480` se confunde
  /// con un decimal de temperatura.
  static String entero(int valor) {
    final texto = valor.abs().toString();
    final partes = <String>[];
    for (var fin = texto.length; fin > 0; fin -= 3) {
      final inicio = fin - 3 < 0 ? 0 : fin - 3;
      partes.insert(0, texto.substring(inicio, fin));
    }
    return '${valor < 0 ? '-' : ''}${partes.join(' ')}';
  }

  /// Temperatura con un decimal: `36.4 °C`.
  static String grados(double? valor, {String sinDato = '--'}) =>
      valor == null ? sinDato : '${valor.toStringAsFixed(1)} °C';

  /// Porcentaje con un decimal: `99.2 %`.
  static String porcentaje(double? valor, {String sinDato = '--'}) =>
      valor == null ? sinDato : '${valor.toStringAsFixed(1)} %';
}
