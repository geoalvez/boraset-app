/// Casca do app: Treino · Biblioteca · Histórico.
///
/// As três telas ficam vivas (IndexedStack) porque sair do treino para
/// consultar a biblioteca e voltar não pode perder a sessão em andamento.
library;

import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../data/store.dart';
import 'history_screen.dart';
import 'library_screen.dart';
import 'theme.dart';
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

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            WorkoutScreen(data: widget.data, store: widget.store),
            LibraryScreen(data: widget.data),
            // key força recarregar o histórico ao voltar para a aba.
            HistoryScreen(key: ValueKey(_tab), store: widget.store),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          backgroundColor: kSurface,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.fitness_center_outlined),
              selectedIcon: Icon(Icons.fitness_center),
              label: 'Treino',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Biblioteca',
            ),
            NavigationDestination(
              icon: Icon(Icons.timeline_outlined),
              selectedIcon: Icon(Icons.timeline),
              label: 'Histórico',
            ),
          ],
        ),
      );
}
