/// Peças de interface do BoraSet.
///
/// Substituem os componentes de estoque do Material, que têm assinatura
/// visual reconhecível: NavigationBar com pílula, SegmentedButton com
/// contorno duplo, FilterChip arredondado, ListTile com métricas fixas.
///
/// Todos aqui usam `EdgeInsetsDirectional` e `start`/`end`. Nunca left/right:
/// árabe, hebraico, persa e urdu invertem a tela inteira.
library;

import 'package:flutter/material.dart';

import 'theme.dart';

// ---------------------------------------------------------------------------
// Estrutura
// ---------------------------------------------------------------------------

/// Cabeçalho com título grande, sem elevação e sem AppBar.
///
/// O AppBar do Material reserva 56px de chrome e centraliza no iOS. Aqui o
/// título é conteúdo: alinhado ao texto abaixo, no mesmo eixo de leitura.
class BsHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  const BsHeader(this.title, {super.key, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 12, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.displaySmall
                      ?.copyWith(fontSize: 26)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 5),
                    Text(subtitle!,
                        style: const TextStyle(color: kMuted, fontSize: 13.5, height: 1.35)),
                  ],
                ],
              ),
            ),
            if (action != null) Padding(
              padding: const EdgeInsetsDirectional.only(start: 8, top: 2),
              child: action,
            ),
          ],
        ),
      );
}

/// Rótulo pequeno em caixa alta. Ancora cada seção sem gastar peso visual.
class Caption extends StatelessWidget {
  final String text;
  final Color? color;
  const Caption(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      );
}

/// Superfície padrão: fundo, borda de 1px, raio consistente.
class BsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background, border;
  final VoidCallback? onTap;

  const BsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.background,
    this.border,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? kSurface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: border ?? kLine),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kRadius),
      child: body,
    );
  }
}

/// Faixa de aviso. Cor carrega o tom; o ícone carrega a urgência.
class BsBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color tone;
  const BsBanner({
    super.key,
    required this.text,
    this.icon = Icons.warning_amber_rounded,
    this.tone = kWarn,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(kRadiusSm),
          border: Border.all(color: tone.withValues(alpha: .32)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: tone, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: tone, fontSize: 13.5, height: 1.45)),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Controles
// ---------------------------------------------------------------------------

/// Controle segmentado com trilho e indicador deslizante.
///
/// O SegmentedButton do Material desenha contorno em cada segmento e um
/// check na seleção — vira uma fileira de botões. Aqui é um trilho só, e a
/// seleção é um bloco que desliza.
class BsSegmented<T> extends StatelessWidget {
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  const BsSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final keys = options.keys.toList();
    final index = keys.indexOf(value).clamp(0, keys.length - 1);
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 8) / keys.length;
        return Container(
          height: 44,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: kSurfaceHi,
            borderRadius: BorderRadius.circular(kRadiusSm),
            border: Border.all(color: kLineSoft),
          ),
          child: Stack(
            children: [
              AnimatedPositionedDirectional(
                duration: const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                start: w * index,
                child: Container(
                  width: w,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kSurfaceTop,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: kLine),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final k in keys)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(k),
                        child: Center(
                          child: Text(
                            options[k]!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: k == value ? FontWeight.w600 : FontWeight.w500,
                              color: k == value ? kText : kMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Etiqueta selecionável. Retangular com cantos suaves, não a pílula do
/// Material — pílula puxa o olho para a forma em vez do texto.
class BsChip extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final Color? tone;
  final VoidCallback? onTap;

  const BsChip({
    super.key,
    required this.label,
    this.selected = false,
    this.icon,
    this.tone,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = tone ?? kGo;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsetsDirectional.fromSTEB(11, 8, 11, 8),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: .12) : kSurfaceHi,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: selected ? c.withValues(alpha: .45) : kLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? c : kMuted),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? c : kMuted,
                )),
          ],
        ),
      ),
    );
  }
}

/// A ação principal. Uma por tela — se houver duas, uma delas não era.
class BsButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loud;
  const BsButton(this.label, {super.key, this.onPressed, this.loud = true});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: loud ? 58 : 50,
        child: Material(
          color: loud ? kGo : kSurfaceHi,
          borderRadius: BorderRadius.circular(kRadius),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(kRadius),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: loud ? 16 : 14.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: loud ? 0.9 : 0.2,
                  color: loud ? kInk : kText,
                ),
              ),
            ),
          ),
        ),
      );
}

/// Ação discreta. Texto, sem caixa — o oposto visual do BsButton.
class BsQuiet extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const BsQuiet(this.label, {super.key, this.onPressed});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: Text(label,
                style: const TextStyle(
                    color: kMuted, fontSize: 13.5, fontWeight: FontWeight.w500)),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Listas
// ---------------------------------------------------------------------------

/// Linha de lista. Substitui o ListTile, que impõe altura e paddings fixos
/// e não deixa a densidade acompanhar o conteúdo.
class BsRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading, trailing;
  final VoidCallback? onTap;
  final bool divider;

  const BsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          decoration: divider
              ? const BoxDecoration(
                  border: Border(bottom: BorderSide(color: kLineSoft)))
              : null,
          padding: const EdgeInsetsDirectional.fromSTEB(20, 13, 20, 13),
          child: Row(
            children: [
              if (leading != null) Padding(
                padding: const EdgeInsetsDirectional.only(end: 13),
                child: leading,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w500, height: 1.3)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: kFaint, fontSize: 12.5, height: 1.35)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) Padding(
                padding: const EdgeInsetsDirectional.only(start: 12),
                child: trailing,
              ),
            ],
          ),
        ),
      );
}

/// Bloco expansível sem o ExpansionTile — que anima a rotação de um chevron
/// do Material e reserva altura fixa no cabeçalho.
class BsExpand extends StatefulWidget {
  final String label;
  final Widget child;
  final bool initiallyOpen;
  const BsExpand({
    super.key,
    required this.label,
    required this.child,
    this.initiallyOpen = false,
  });

  @override
  State<BsExpand> createState() => _BsExpandState();
}

class _BsExpandState extends State<BsExpand> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  Expanded(child: Caption(widget.label)),
                  AnimatedRotation(
                    turns: _open ? .5 : 0,
                    duration: const Duration(milliseconds: 170),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 17, color: kFaint),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 170),
            sizeCurve: Curves.easeOutCubic,
            crossFadeState:
                _open ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(width: double.infinity, child: widget.child),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      );
}

// ---------------------------------------------------------------------------
// Navegação
// ---------------------------------------------------------------------------

/// Barra inferior própria: ícone, rótulo e um traço de 2px sobre o item
/// ativo. O NavigationBar do Material desenha uma pílula atrás do ícone —
/// é a marca visual mais reconhecível do framework.
class BsNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final List<(IconData, IconData, String)> items;
  const BsNav({
    super.key,
    required this.index,
    required this.onChanged,
    required this.items,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: kSurface,
          border: Border(top: BorderSide(color: kLine)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 170),
                            height: 2,
                            width: i == index ? 20 : 0,
                            margin: const EdgeInsets.only(bottom: 9),
                            decoration: BoxDecoration(
                              color: kGo,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Icon(i == index ? items[i].$2 : items[i].$1,
                              size: 21, color: i == index ? kText : kFaint),
                          const SizedBox(height: 4),
                          Text(items[i].$3,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight:
                                    i == index ? FontWeight.w600 : FontWeight.w500,
                                color: i == index ? kText : kFaint,
                              )),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

/// Folha inferior consistente: fundo, raio, alça e limite de altura.
Future<T?> bsSheet<T>(BuildContext context, Widget child, {bool tall = false}) =>
    showModalBottomSheet<T>(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: .62),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: kLine),
      ),
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * (tall ? .84 : .7),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34, height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: kLine, borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
