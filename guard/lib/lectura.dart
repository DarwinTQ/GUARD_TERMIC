class Lectura {
  final String id;
  final String dispositivo;
  final double sensor1;
  final double sensor2;
  final DateTime fecha;

  Lectura({
    required this.id,
    required this.dispositivo,
    required this.sensor1,
    required this.sensor2,
    required this.fecha,
  });

  factory Lectura.fromJson(Map<String, dynamic> j) => Lectura(
        id: j['id'] ?? '',
        dispositivo: j['dispositivo'] ?? '',
        sensor1: (j['sensor1'] as num).toDouble(),
        sensor2: (j['sensor2'] as num).toDouble(),
        fecha: DateTime.parse(j['fecha']).toLocal(),
      );
}
