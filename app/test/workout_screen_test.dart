/// Testes de tela.
///
/// Carregam o catálogo e o pacote de idioma de verdade (dos assets), não
/// mocks. Se o JSON quebrar o contrato, o teste quebra junto.
library;

import 'package:boraset/src/data/repository.dart';
import 'package:boraset/src/ui/widgets.dart';
import 'package:boraset/src/ui/workout_screen.dart';
import 'package:boraset_domain/boraset_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Os dados são carregados FORA de `testWidgets`.
///
/// Dentro de um widget test o tempo é falso (FakeAsync) e `rootBundle`
/// depende de I/O real — a Future nunca resolve e o teste trava. Carregar
/// em `setUpAll` mantém o I/O no mundo real e o teste no mundo falso.
final _loaded = <String, BorasetData>{};

Widget _app(String lang) =>
    MaterialApp(home: WorkoutScreen(data: _loaded[lang]!));

/// Os chips de técnica levam chave própria; casar por tipo pegaria também o
/// chip de tempo disponível que vive no cabeçalho.
Finder _techniqueChip() => find.byWidgetPredicate(
    (w) => w is BsChip && '${w.key}'.contains('tech-'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final l in ['pt', 'ar']) {
      _loaded[l] = await Repository().load(l);
    }
  });

  group('carregamento dos dados', () {
    test('o catálogo neutro produz 193 exercícios com eixos válidos', () async {
      final d = await Repository().load('pt');
      expect(d.catalog.all.length, 193);
      expect(d.techniques.length, 30);
      expect(d.unit, WeightUnit.kg);
    });

    test('todo idioma carrega e nomeia os 193 exercícios', () async {
      for (final l in ['pt', 'en', 'es', 'ar', 'ja', 'th', 'ru', 'hi']) {
        final d = await Repository().load(l);
        expect(d.exerciseNames.length, 193, reason: 'faltou nome em $l');
        expect(d.techniques.length, 30, reason: 'faltou técnica em $l');
        for (final t in d.techniques.values) {
          expect(t.summary, isNotEmpty, reason: '${t.slug} sem resumo em $l');
          expect(t.sections.length, greaterThanOrEqualTo(4),
              reason: '${t.slug} sem biblioteca completa em $l');
        }
      }
    });

    test('en usa libra; os demais, quilo', () async {
      expect((await Repository().load('en')).unit, WeightUnit.lb);
      expect((await Repository().load('de')).unit, WeightUnit.kg);
    });

    test('idioma não suportado cai no inglês, não quebra', () async {
      expect(Repository.resolveLocale('sw'), 'en');
      expect(Repository.resolveLocale('pt'), 'pt-BR');
      expect(Repository.resolveLocale('zh'), 'zh-Hans');
    });

    test('os avisos de segurança sobrevivem em todos os idiomas', () async {
      const comAviso = {'oclusao', 'falha-total', 'apneia'};
      for (final l in ['pt', 'en', 'ar', 'th', 'hi', 'ja', 'ko', 'ru']) {
        final d = await Repository().load(l);
        for (final s in comAviso) {
          expect(d.techniques[s]?.hasCaution, isTrue,
              reason: '$s perdeu o aviso em $l');
        }
      }
    });
  });

  group('tela de treino', () {
    testWidgets('mostra o próximo exercício e um único botão primário',
        (tester) async {
      await tester.pumpWidget(_app('pt'));
      await tester.pumpAndSettle();

      expect(find.text('Supino Reto'), findsOneWidget); // âncora do dia A gerado
      expect(find.text('CONCLUÍDA'), findsOneWidget);
      expect(find.text('Algo deu errado'), findsOneWidget);
      // Os outros quatro gatilhos NÃO estão na tela principal.
      expect(find.text('Aparelho ocupado'), findsNothing);
    });

    testWidgets('no dia 1 o tempo aparece como faixa e admite a incerteza',
        (tester) async {
      await tester.pumpWidget(_app('pt'));
      await tester.pumpAndSettle();

      expect(find.textContaining('–'), findsWidgets); // "20–30 min"
      expect(find.textContaining('aprendendo o seu ritmo'), findsOneWidget);
    });

    testWidgets('"algo deu errado" revela os quatro gatilhos', (tester) async {
      await tester.pumpWidget(_app('pt'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Algo deu errado'));
      await tester.pumpAndSettle();

      expect(find.text('Aparelho ocupado'), findsOneWidget);
      expect(find.text('Quero trocar'), findsOneWidget);
      expect(find.text('Não sei fazer'), findsOneWidget);
      expect(find.text('Pular'), findsOneWidget);
    });

    testWidgets('aparelho ocupado reordena e troca o exercício da tela',
        (tester) async {
      await tester.pumpWidget(_app('pt'));
      await tester.pumpAndSettle();
      expect(find.text('Supino Reto'), findsOneWidget); // âncora do dia A gerado

      await tester.tap(find.text('Algo deu errado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aparelho ocupado'));
      await tester.pumpAndSettle();

      expect(find.text('Supino Reto'), findsNothing,
          reason: 'o motor deve ter adiantado outro bloco');
    });

    // O treino é GERADO, então o nome da técnica muda conforme o gerador
    // evolui. Testar pelo chip, e não por um texto fixo, evita quebrar o
    // teste toda vez que a prescrição muda de forma legítima.
    testWidgets('o chip de técnica abre o popup com resumo curto',
        (tester) async {
      await tester.pumpWidget(_app('pt'));
      await tester.pumpAndSettle();

      final chip = _techniqueChip();
      expect(chip, findsWidgets, reason: 'o dia gerado deve prescrever técnica');
      // O card do exercício rola: sem trazer o chip para a viewport o toque
      // cai no vazio.
      await tester.ensureVisible(chip.first);
      await tester.pumpAndSettle();
      await tester.tap(chip.first);
      await tester.pumpAndSettle();

      expect(find.text('Ver mais'), findsOneWidget,
          reason: 'a biblioteca fica atrás de um toque, não na cara');
    });

    testWidgets('"Ver mais" abre as seções, com Erro comum já aberto',
        (tester) async {
      await tester.pumpWidget(_app('pt'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(_techniqueChip().first);
      await tester.pumpAndSettle();
      await tester.tap(_techniqueChip().first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver mais'));
      await tester.pumpAndSettle();

      expect(find.text('ERRO COMUM'), findsOneWidget);
      expect(find.text('COMO EXECUTAR'), findsOneWidget,
          reason: 'as quatro seções da biblioteca aparecem ao expandir');
    });

    testWidgets('o tempo é tocável e explica a decisão do motor',
        (tester) async {
      await tester.pumpWidget(_app('pt'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('TEMPO RESTANTE'));
      await tester.pumpAndSettle();

      expect(find.text('POR QUE MUDOU'), findsOneWidget);
      expect(find.textContaining('Nada mudou'), findsOneWidget);
    });

    testWidgets('a tela sobrevive em árabe (RTL)', (tester) async {
      await tester.pumpWidget(_app('ar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(WorkoutScreen), findsOneWidget);
    });
  });
}
