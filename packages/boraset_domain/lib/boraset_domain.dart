/// BoraSet — núcleo de domínio.
///
/// Regra da casa: nada aqui importa `package:flutter`. Se um dia importar,
/// o motor deixou de ser testável em `dart test` e a separação morreu.
///
/// Como as peças se encaixam:
///
///   catalog.dart      o que um exercício É — eixos de movimento e o score de
///                     compatibilidade entre eles. Não sabe de academia nem
///                     de usuário.
///   session.dart      o que está acontecendo AGORA — blocos, séries, carga
///                     registrada, e o que está ocupado.
///   engine.dart       o contrato: decide(EngineInput) -> Decision. Função pura.
///   strategies.dart   COMO adaptar — os seis degraus, um por classe. A ordem
///                     da lista é a política.
///   progression.dart  quanto peso sugerir da próxima vez, arredondado para a
///                     anilha que existe naquele país.
///   presentation.dart o que a tela deve MOSTRAR — tom, aviso, e quando calar.
///                     "sugerir +100% é perigoso" é regra de treino, não de
///                     layout; por isso mora aqui e tem teste.
///
/// Nenhum texto voltado ao usuário mora aqui. `Rationale` carrega código e
/// fatos; a frase é montada na UI, no idioma dela.
library boraset_domain;

export 'src/catalog.dart';
export 'src/session.dart';
export 'src/engine.dart';
export 'src/strategies.dart';
export 'src/progression.dart';
export 'src/presentation.dart';
