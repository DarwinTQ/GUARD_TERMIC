import 'package:flutter/foundation.dart';

/// Un indice tal y como lo tiene creado MongoDB.
@immutable
class IndiceColeccion {
  const IndiceColeccion({required this.nombre, required this.campos});

  final String nombre;

  /// Formato `campo:orden`, con 1 ascendente y -1 descendente.
  final List<String> campos;

  factory IndiceColeccion.desdeApi(Map<String, dynamic> json) =>
      IndiceColeccion(
        nombre: (json['nombre'] as String?) ?? '',
        campos: ((json['campos'] as List?) ?? const []).cast<String>(),
      );

  String get descripcion => campos.join(', ');
}

/// Estado de una coleccion: cuantos documentos tiene y cuanto ocupa.
@immutable
class ColeccionBd {
  const ColeccionBd({
    required this.nombre,
    required this.documentos,
    required this.indices,
    this.bytes,
    this.bytesIndices,
  });

  final String nombre;
  final int documentos;
  final List<IndiceColeccion> indices;

  /// `null` si el despliegue no permite `collStats`.
  final int? bytes;
  final int? bytesIndices;

  factory ColeccionBd.desdeApi(Map<String, dynamic> json) => ColeccionBd(
        nombre: (json['nombre'] as String?) ?? '',
        documentos: (json['documentos'] as num?)?.toInt() ?? 0,
        bytes: (json['bytes'] as num?)?.toInt(),
        bytesIndices: (json['bytes_indices'] as num?)?.toInt(),
        indices: ((json['indices'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(IndiceColeccion.desdeApi)
            .toList(),
      );

  /// Tamaño medio por documento, util para estimar cuanto crecera la serie.
  double? get bytesPorDocumento =>
      (bytes == null || documentos == 0) ? null : bytes! / documentos;
}

/// Respuesta de `GET /bd/resumen`.
@immutable
class ResumenBd {
  const ResumenBd({
    required this.baseDatos,
    required this.colecciones,
    this.servidor,
  });

  final String baseDatos;
  final String? servidor;
  final List<ColeccionBd> colecciones;

  factory ResumenBd.desdeApi(Map<String, dynamic> json) => ResumenBd(
        baseDatos: (json['base_datos'] as String?) ?? '',
        servidor: json['servidor'] as String?,
        colecciones: ((json['colecciones'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ColeccionBd.desdeApi)
            .toList(),
      );

  int get totalDocumentos =>
      colecciones.fold(0, (suma, c) => suma + c.documentos);

  int? get totalBytes {
    final valores = [
      for (final coleccion in colecciones)
        if (coleccion.bytes != null) coleccion.bytes!,
    ];
    if (valores.isEmpty) return null;
    return valores.reduce((a, b) => a + b);
  }
}
