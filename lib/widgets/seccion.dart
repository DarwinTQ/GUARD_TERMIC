import 'package:flutter/material.dart';

/// Bloque con titulo, explicacion opcional y contenido.
///
/// Cada vista se compone de secciones de estas para que todas las pantallas
/// tengan el mismo ritmo vertical y la misma jerarquia tipografica.
class Seccion extends StatelessWidget {
  const Seccion({
    required this.titulo,
    required this.hijo,
    this.descripcion,
    this.acciones = const [],
    super.key,
  });

  final String titulo;
  final String? descripcion;
  final Widget hijo;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: tema.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (descripcion != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      descripcion!,
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: tema.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (acciones.isNotEmpty)
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: acciones),
          ],
        ),
        const SizedBox(height: 14),
        hijo,
      ],
    );
  }
}

/// Rejilla fluida de tarjetas KPI.
///
/// Reparte el ancho disponible en columnas de al menos [anchoMinimo] px en
/// lugar de fijar un numero de columnas: la misma vista sirve para un movil
/// en vertical y para un monitor de 27 pulgadas.
class RejillaKpi extends StatelessWidget {
  const RejillaKpi({
    required this.tarjetas,
    this.anchoMinimo = 190,
    this.separacion = 12,
    super.key,
  });

  final List<Widget> tarjetas;
  final double anchoMinimo;
  final double separacion;

  @override
  Widget build(BuildContext context) {
    if (tarjetas.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, restricciones) {
        final disponible = restricciones.maxWidth;
        final columnas =
            (disponible / (anchoMinimo + separacion)).floor().clamp(1, 6);
        final ancho =
            (disponible - separacion * (columnas - 1)) / columnas;

        return Wrap(
          spacing: separacion,
          runSpacing: separacion,
          children: [
            for (final tarjeta in tarjetas)
              SizedBox(width: ancho, child: tarjeta),
          ],
        );
      },
    );
  }
}

/// Contenedor con borde para graficos y tablas.
class Panel extends StatelessWidget {
  const Panel({
    required this.hijo,
    this.relleno = const EdgeInsets.all(16),
    super.key,
  });

  final Widget hijo;
  final EdgeInsets relleno;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      padding: relleno,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tema.dividerColor.withValues(alpha: 0.6)),
        color: tema.colorScheme.surface,
      ),
      child: hijo,
    );
  }
}
