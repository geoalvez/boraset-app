/// O popup de ajuda.
///
/// Uma superfície, três origens: exercício, técnica e justificativa do motor.
/// Foi essa unificação que fez a explicação do motor caber sem UI nova.
///
/// Duas camadas, porque são dois usuários:
///   resumo    ≤140 caracteres. Meio de treino, mão suando, 4 segundos.
///   seções    biblioteca, sofá de domingo. "Erro comum" aberto por padrão.
library;

import 'package:boraset_domain/boraset_domain.dart';
import 'package:flutter/material.dart';

import '../data/repository.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> showTechniqueHelp(
  BuildContext context,
  BorasetData data,
  String slug, {
  bool expanded = false,
}) {
  final t = data.techniques[slug];
  if (t == null) return Future.value();
  return bsSheet(
    context,
    _TechniqueSheet(data: data, topic: t, startExpanded: expanded),
    tall: expanded,
  );
}

Future<void> showDecisionHelp(
  BuildContext context,
  BorasetData data,
  List<Rationale> rationale,
) =>
    bsSheet(context, _DecisionSheet(data: data, rationale: rationale));

class _TechniqueSheet extends StatefulWidget {
  final BorasetData data;
  final TechniqueHelp topic;
  final bool startExpanded;
  const _TechniqueSheet({
    required this.data,
    required this.topic,
    required this.startExpanded,
  });

  @override
  State<_TechniqueSheet> createState() => _TechniqueSheetState();
}

class _TechniqueSheetState extends State<_TechniqueSheet> {
  late bool _open = widget.startExpanded;

  @override
  Widget build(BuildContext context) {
    final t = widget.topic;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(t.name,
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall
                          ?.copyWith(fontSize: 22)),
                ),
                _Freq(t.occurrences),
              ],
            ),
            const SizedBox(height: 14),

            // Aviso de segurança: nunca dispensável, sempre acima do resumo.
            if (t.hasCaution) ...[
              BsBanner(text: t.caution!),
              const SizedBox(height: 14),
            ],

            // Camada 1 — o que o usuário lê no meio da série.
            Text(t.summary,
                style: const TextStyle(fontSize: 16, height: 1.5, color: kText)),

            if (!_open && t.sections.isNotEmpty) ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => setState(() => _open = true),
                behavior: HitTestBehavior.opaque,
                child: const Row(
                  children: [
                    Text('Ver mais',
                        style: TextStyle(
                            color: kGo, fontSize: 13.5, fontWeight: FontWeight.w600)),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: kGo),
                  ],
                ),
              ),
            ],

            // Camada 2 — biblioteca.
            if (_open) ...[
              const SizedBox(height: 6),
              const Divider(),
              for (final key in widget.data.sectionOrder)
                if ((t.sections[key] ?? '').isNotEmpty)
                  BsExpand(
                    // O rótulo vem de ui_strings.json: uma vez por idioma.
                    label: widget.data.sectionLabels[key] ?? key,
                    // "Erro comum" é a parte que as pessoas realmente leem.
                    initiallyOpen: key == 'mistake',
                    child: Text(t.sections[key]!,
                        style: const TextStyle(
                            fontSize: 14.5, height: 1.55, color: kMuted)),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Quantas vezes a técnica aparece no material de origem. Dá noção de o quão
/// central ela é, sem precisar explicar.
class _Freq extends StatelessWidget {
  final int n;
  const _Freq(this.n);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: kSurfaceHi,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: kLine),
        ),
        child: Text('$n×',
            style: const TextStyle(
                color: kFaint, fontSize: 11.5, fontFeatures: kTabular)),
      );
}

/// A terceira ajuda: por que o motor mexeu no treino.
///
/// O texto é montado AQUI, a partir de `RationaleCode` + `facts`. O motor
/// nunca produziu uma frase — foi isso que o deixou independente de idioma.
class _DecisionSheet extends StatelessWidget {
  final BorasetData data;
  final List<Rationale> rationale;
  const _DecisionSheet({required this.data, required this.rationale});

  String _sentence(Rationale r) {
    String ex(Object? slug) => data.nameOf('$slug');
    return switch (r.code) {
      RationaleCode.equipmentBusyDeferred =>
        'Você marcou o aparelho como ocupado. Adiantei outro exercício e volto '
            'a sugerir este em ${r.facts['retryAfterMinutes'] ?? 6} minutos.',
      RationaleCode.equipmentBusyRepeatedSoSubstituted =>
        'O aparelho continuou ocupado. Troquei ${ex(r.facts['from'])} por '
            '${ex(r.facts['to'])} — ${r.facts['compatibility']}% de compatibilidade '
            'de movimento.',
      RationaleCode.equipmentMissingInThisGym =>
        'Esta academia não tem o equipamento. ${ex(r.facts['to'])} trabalha o '
            'mesmo padrão de movimento.',
      RationaleCode.userAvoidsExercise =>
        'Você pediu para trocar. ${ex(r.facts['to'])} mantém o mesmo alvo.',
      RationaleCode.userDoesNotKnowExercise =>
        'Troquei por ${ex(r.facts['to'])}, que trabalha o mesmo padrão e é mais '
            'simples de executar.',
      RationaleCode.timeShortReducedVolume =>
        'Tirei uma série de ${ex(r.facts['slug'])} porque o treino estava '
            '${((r.facts['overrunSeconds'] as num? ?? 0) / 60).round()} min acima do '
            'seu tempo. É um acessório — os exercícios principais ficaram intactos.',
      RationaleCode.timeShortMergedSuperset =>
        'Juntei dois exercícios em supersérie e economizei '
            '${((r.facts['savedSeconds'] as num? ?? 0) / 60).round()} min sem tirar '
            'nenhuma série.',
      RationaleCode.timeShortDroppedAccessory =>
        'Removi ${ex(r.facts['slug'])}. Foi o último recurso: reordenar, reduzir '
            'volume e supersérie já não davam conta do tempo restante.',
      RationaleCode.patternAlreadyCoveredThisSession =>
        'Você já fez dois exercícios do mesmo padrão de movimento hoje.',
      RationaleCode.noViableSubstituteLadderExhausted =>
        'Não há substituto viável e não dá para reorganizar mais. A decisão é sua.',
      RationaleCode.onTrackNoChange =>
        'Nada mudou. O treino está no plano e dentro do tempo.',
    };
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Caption('Por que mudou'),
              const SizedBox(height: 14),
              for (final r in rationale)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 3,
                        height: 34,
                        margin: const EdgeInsetsDirectional.only(end: 13, top: 3),
                        decoration: BoxDecoration(
                          color: kGo.withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: Text(_sentence(r),
                            style: const TextStyle(
                                fontSize: 15, height: 1.5, color: kText)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}
