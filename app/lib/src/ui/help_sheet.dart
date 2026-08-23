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

Future<void> showTechniqueHelp(
  BuildContext context,
  BorasetData data,
  String slug, {
  bool expanded = false,
}) {
  final t = data.techniques[slug];
  if (t == null) return Future.value();
  return showModalBottomSheet(
    context: context,
    backgroundColor: kSurface,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _TechniqueSheet(data: data, topic: t, startExpanded: expanded),
  );
}

Future<void> showDecisionHelp(
  BuildContext context,
  BorasetData data,
  List<Rationale> rationale,
) =>
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _DecisionSheet(data: data, rationale: rationale),
    );

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
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.name, style: text.titleMedium?.copyWith(fontSize: 21)),
              const SizedBox(height: 12),

              // Aviso de segurança: nunca dispensável, sempre acima do resumo.
              if (t.hasCaution) _CautionBanner(text: t.caution!),

              // Camada 1 — o que o usuário lê no meio da série.
              Text(t.summary, style: text.bodyMedium?.copyWith(fontSize: 16.5)),

              if (!_open && t.sections.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _open = true),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: const Text('Ver mais'),
                ),
              ],

              // Camada 2 — biblioteca.
              if (_open) ...[
                const SizedBox(height: 4),
                for (final key in widget.data.sectionOrder)
                  if (t.sections[key] != null && t.sections[key]!.isNotEmpty)
                    _Section(
                      // O rótulo vem de ui_strings.json: uma vez por idioma.
                      label: widget.data.sectionLabels[key] ?? key,
                      body: t.sections[key]!,
                      // "Erro comum" é a parte que as pessoas realmente leem.
                      initiallyOpen: key == 'mistake',
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CautionBanner extends StatelessWidget {
  final String text;
  const _CautionBanner({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: kWarn.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kWarn.withValues(alpha: .45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: kWarn, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 14, color: kWarn)),
            ),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  final String label, body;
  final bool initiallyOpen;
  const _Section({required this.label, required this.body, this.initiallyOpen = false});

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyOpen,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsetsDirectional.only(bottom: 10),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Caption(label),
          children: [
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
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
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Caption('Por que mudou'),
              const SizedBox(height: 12),
              for (final r in rationale) ...[
                Text(_sentence(r),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 16)),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      );
}
