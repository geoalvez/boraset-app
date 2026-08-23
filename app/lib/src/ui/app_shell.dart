/// Casca do app: Treino · Programa · Biblioteca · Histórico.
///
/// As quatro telas ficam vivas (IndexedStack) porque sair do treino para
/// consultar a biblioteca e voltar não pode perder a sessão em andamento.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../data/store.dart';
import 'history_screen.dart';
import 'library_screen.dart';
import 'program_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'workout_screen.dart';

class AppShell extends StatefulWidget {
  final BorasetData data;
  final WorkoutStore store;
  const AppShell({super.key, required this.data, required this.store});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  /// Muda quando o programa é reconfigurado, para a tela de treino se refazer
  /// do zero em vez de continuar exibindo a divisão antiga.
  int _programVersion = 0;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: kSystemChrome,
        child: Scaffold(
          body: IndexedStack(
            index: _tab,
            children: [
              WorkoutScreen(
                key: ValueKey('workout-$_programVersion'),
                data: widget.data,
                store: widget.store,
              ),
              ProgramScreen(
                data: widget.data,
                store: widget.store,
                onChanged: () => setState(() => _programVersion++),
              ),
              LibraryScreen(data: widget.data),
              // key força recarregar o histórico ao voltar para a aba.
              HistoryScreen(key: ValueKey('hist-$_tab'), store: widget.store),
            ],
          ),
          bottomNavigationBar: BsNav(
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
            items: const [
              (Icons.bolt_outlined, Icons.bolt, 'Treino'),
              (Icons.tune_outlined, Icons.tune, 'Programa'),
              (Icons.menu_book_outlined, Icons.menu_book, 'Biblioteca'),
              (Icons.show_chart_outlined, Icons.show_chart, 'Histórico'),
            ],
          ),
        ),
      );
}
