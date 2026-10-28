import 'package:flutter/material.dart';

/// Una serie de un grafico: su nombre, su color y -opcionalmente- su valor
/// actual, que hace de etiqueta directa sin tener que poner un numero sobre
/// cada punto.
@immutable
class EntradaLeyenda {
  const EntradaLeyenda({
    required this.nombre,
    required this.color,
    this.valor,
  });

  final String nombre;
  final Color color;
  final String? valor;
}

/// Leyenda compartida por todos los graficos de la app.
///
/// Siempre presente cuando hay dos o mas series: el color nunca es el unico
/// dato que distingue una serie de otra. El texto va en color de texto, no
/// en el de la serie; quien lleva la identidad es la marca de color.
class LeyendaSeries extends StatelessWidget {
  const LeyendaSeries({
    required this.entradas,
    this.alineacion = MainAxisAlignment.center,
    super.key,
  });

  final List<EntradaLeyenda> entradas;
  final MainAxisAlignment alineacion;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Wrap(
      alignment: alineacion == MainAxisAlignment.start
          ? WrapAlignment.start
          : WrapAlignment.center,
      spacing: 18,
      runSpacing: 6,
      children: [
        for (final entrada in entradas)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 3,
                decoration: BoxDecoration(
                  color: entrada.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                entrada.nombre,
                style: tema.textTheme.bodySmall?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                ),
              ),
              if (entrada.valor != null) ...[
                const SizedBox(width: 6),
                Text(
                  entrada.valor!,
                  style: tema.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}
