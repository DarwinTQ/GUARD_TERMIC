import 'package:flutter/material.dart';

/// Cifra destacada del dashboard (nodos activos, latencia media, etc.).
///
/// Es la forma correcta para un unico numero: graficar un solo valor obliga
/// al ojo a leer una escala para recuperar un dato que ya cabe en pantalla.
///
/// El numero va en color de texto, nunca en el de una serie. Cuando hay
/// estado, lo llevan el punto de color y su etiqueta juntos: asi nadie
/// depende del color para enterarse.
class TarjetaKpi extends StatelessWidget {
  const TarjetaKpi({
    required this.titulo,
    required this.valor,
    this.unidad,
    this.detalle,
    this.icono,
    this.colorEstado,
    this.etiquetaEstado,
    super.key,
  });

  final String titulo;
  final String valor;
  final String? unidad;
  final String? detalle;
  final IconData? icono;

  /// Color de estado (bueno / alerta / critico). Requiere [etiquetaEstado].
  final Color? colorEstado;
  final String? etiquetaEstado;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final atenuado = tema.colorScheme.onSurfaceVariant;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: tema.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icono != null) ...[
                  Icon(icono, size: 15, color: atenuado),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    titulo,
                    style: tema.textTheme.labelMedium?.copyWith(color: atenuado),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    valor,
                    style: tema.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (unidad != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    unidad!,
                    style: tema.textTheme.bodySmall?.copyWith(color: atenuado),
                  ),
                ],
              ],
            ),
            if (colorEstado != null && etiquetaEstado != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colorEstado,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    etiquetaEstado!,
                    style: tema.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            if (detalle != null) ...[
              const SizedBox(height: 6),
              Text(
                detalle!,
                style: tema.textTheme.bodySmall?.copyWith(color: atenuado),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
