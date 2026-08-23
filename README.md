# BoraSet

Copiloto de treino adaptativo em tempo real. App mobile (Flutter, Android + iOS) que responde
continuamente a uma pergunta:

> **Qual é o melhor exercício para eu fazer agora?**

Sem parceria com academia, sem sensores em aparelho, sem QR Code. Funciona em qualquer academia,
com os dados do próprio usuário e o que foi registrado durante o treino.

Quando algo dá errado no meio da sessão — aparelho ocupado, equipamento inexistente, pouco tempo,
exercício que a pessoa não sabe fazer — o app reorganiza o restante do treino **sem destruir a
lógica original da sessão**.

---

## Estado atual

Fase de modelagem de domínio. Ainda não há app Flutter; há o **núcleo de domínio em Dart puro**
e as **bases de dados** que o alimentam.

```
app/                              Flutter (Android + iOS)
  lib/main.dart                   boot: catálogo + banco, locale, RTL
  lib/src/data/repository.dart    carrega catálogo + pacote de idioma
  lib/src/data/store.dart         SQLite local — histórico, cargas, perfil
  lib/src/ui/theme.dart           cor, tipografia, escala de espaçamento
  lib/src/ui/widgets.dart         componentes próprios (nav, chip, card, linha)
  lib/src/ui/app_shell.dart       Treino · Programa · Biblioteca · Histórico
  lib/src/ui/workout_screen.dart  a tela de treino
  lib/src/ui/program_screen.dart  divisão, objetivo, nível, equipamento + prévia
  lib/src/ui/library_screen.dart  193 exercícios e 30 técnicas, buscáveis
  lib/src/ui/history_screen.dart  treinos passados + barra de calibração
  lib/src/ui/help_sheet.dart      o popup (técnica + justificativa do motor)
  assets/data/                    FONTE ÚNICA dos dados — catálogo e idiomas

packages/boraset_domain/lib/src/
  catalog.dart      eixos de movimento, score de compatibilidade, filtros
  session.dart      SessionBlock, ExerciseSlot, SetRecord, BusyRegistry
  engine.dart       contrato do WorkoutDecisionEngine
  strategies.dart   os seis degraus da escada de adaptação
  progression.dart  progressão de carga + matemática de anilha por país
  program.dart      monta a ficha a partir do catálogo (divisões, volume, deload)
  presentation.dart o que a tela mostra: tom, aviso, e quando calar

app/assets/data/
  catalog/exercises.core.json     193 exercícios · 14 eixos · 1.980 equivalências
  catalog/techniques.core.json     30 técnicas · categoria e frequência
  l10n/exercises.<locale>.json     nomes por idioma (18 idiomas)
  l10n/techniques.<locale>.json    ajuda por idioma (18 idiomas)
  l10n/ui_strings.json             rótulos de UI — uma vez por idioma
  locales.json                     manifesto de cobertura de tradução
```

## Rodando

```bash
cd packages/boraset_domain && dart test      # 28 testes — motor, escada, anilha
cd app && flutter test                       # 48 testes — dados, banco, gerador e telas
cd app && flutter run                        # Android / iOS / web
```

---

## Decisões de arquitetura

**76 testes, e cada um corresponde a uma afirmação sobre o produto.** Se a afirmação
estiver errada, o teste quebra. Foi assim que apareceram um `Timer.periodic` que
reconstruía a tela 60 vezes por minuto para não mudar nada, uma colisão de nome em
polonês entre dois exercícios de músculos diferentes, e um `ORDER BY logged_at` sem
desempate — que devolvia a carga da sessão errada para quem treinasse duas vezes no
mesmo dia.

**O histórico existe para fechar o laço da estimativa.** Sem ele o app fica preso em
"20–30 min" para sempre. Cada série cronometrada empurra a confiança de `coldStart`
para `calibrating` (12 séries) e depois `personalized` (40) — e a tela de histórico
mostra essa barra, para que a incerteza seja algo que se resolve treinando em vez de
um defeito silencioso.

**O motor é uma função pura.** `Decision decide(EngineInput input)`. Sem I/O, sem relógio, sem
Flutter. O tempo decorrido entra por injeção (`input.elapsed`) — nunca `DateTime.now()`. Isso
torna cada cenário de decisão um teste de tabela, sem emulador.

**Equivalência é função, não tabela.** 193 exercícios dariam 37 mil pares para autorar à mão.
Em vez disso, cada exercício carrega seus eixos e o score sai calculado:

| eixo | peso |
|---|---|
| padrão de movimento | 35 |
| músculo primário | 22 |
| escalabilidade de carga | 15 |
| composto/isolador | 7 |
| músculos secundários | 6 |
| empurrar/puxar | 6 |
| plano | 5 |
| lateralidade | 4 |

**Equipamento não entra no score.** Equipamento é filtro de disponibilidade, aplicado depois.
Misturar os dois penalizaria justamente a troca de equipamento, que é o motivo de existir a
substituição. São três funções independentes:

```
compatibilidade(A, B)      biomecânica  — não sabe de academia nem do usuário
disponível(B, academia)    equipamento  — não sabe de biomecânica
aceito(B, usuário)         preferências — não sabe de nenhum dos dois
```

**A escada de adaptação é uma lista.** A ordem é a política; mudar a política é reordenar a lista:

```
1. reordenar        adianta outro bloco. custo zero de volume.
2. adiar            marca para reavaliar. "ocupado" expira em 8 min.
3. substituir       troca por equivalente viável.
4. reduzir volume   tira série do acessório, nunca da âncora.
5. supersérie       funde dois blocos. preserva o volume inteiro.
6. remover          último recurso.
```

**Justificativa é dado estruturado, não texto.** `Rationale { RationaleCode code; Map facts; }`.
A UI monta a frase. Foi essa decisão que fez o motor nascer independente de idioma — nenhuma
linha do engine precisa de tradução.

**Progressão respeita o ferro que existe.** Sugerir "+2,5 kg" nos EUA é sugerir uma
anilha que não existe na parede de lá. O arredondamento depende do país *e* do
equipamento — barra sobe de par em par, halter pula de denominação em denominação,
stack de máquina anda de placa em placa. Três matemáticas diferentes, e o `+100%`
que um stack de 5 kg impõe vira aviso, não sugestão.

**As fichas são geradas, não embarcadas.** O app não traz o programa de ninguém: monta
o dia na hora, a partir do catálogo, escolhendo cada exercício por padrão de movimento,
grupo alvo, equipamento disponível e nível — com a familiaridade como desempate.

As divisões (Full Body 3x, Upper/Lower 4x, ABC 3x, Push/Pull/Legs 6x) são estrutura
pública de treinamento. Os parâmetros vieram da mineração estatística das 60 planilhas:
mediana de 7 exercícios por dia, ~3,3 séries por exercício, faixa 10–15 nos acessórios
e 6–12 nas âncoras, descanso concentrado em 40/60/75 s, técnica em ~65% das vagas, e uma
curva de volume que sobe nas semanas 4–6, **recua nas 7–9** e vai ao pico nas 10–12.
Aquele recuo é um deload — e é o que separa uma periodização de "somar série até quebrar".

Isso é regularidade de como se estrutura um treino. As fichas específicas, que são
produto pago de terceiro, não estão neste repositório e não vão para o app.

**A interface não usa componente de estoque.** `NavigationBar` com pílula,
`SegmentedButton`, `FilterChip`, `ListTile`, `ExpansionTile`, `AppBar` — todos têm
assinatura visual reconhecível, e juntos fazem qualquer app parecer o mesmo app.
`widgets.dart` traz substitutos próprios: barra inferior com traço em vez de pílula,
controle segmentado com indicador que desliza num trilho único, etiqueta retangular
em vez de cápsula, linha de lista sem métrica fixa, expansível sem o chevron do
Material. Números usam `FontFeature.tabularFigures()` — sem isso o cronômetro "pula"
a cada segundo, porque os dígitos têm larguras diferentes.

**A tela não decide sozinha o que é perigoso.** "Sugerir +100% de carga" é regra de
treino, não de layout. Por isso `presentation.dart` — pure Dart, com teste — decide o
tom (`suggest` / `suggestWithCaution` / `withhold`) e a tela só renderiza. Numa polia
de 5 kg o menor aumento possível é dobrar a carga: o app não sugere número ali, explica
e manda progredir por repetição.

**Rótulo de seção mora uma vez por idioma.** O texto da biblioteca é `sections.{what,
how, when, mistake}`; os títulos vivem em `ui_strings.json`. Traduzir markdown com
títulos embutidos traduziria "O que é" 510 vezes.

**Identidade e idioma vivem separados.** O núcleo do catálogo não tem uma palavra traduzível;
nomes e textos moram em pacotes por locale. Um idioma novo custa ~41 KB em vez de ~376 KB.

---

## Base de exercícios

Extraída de 60 planilhas de treino distintas (83 arquivos, 23 duplicatas removidas por hash de
conteúdo). Os PDFs de origem contêm hyperlinks por exercício e por técnica; os *slugs* desses
links funcionaram como oráculo de normalização, resolvendo sinônimos que nenhuma regra textual
alcançaria — `dumbbell-press-inclinado-supino-inclinado-com-halteres` diz, na própria fonte, que
os dois nomes são o mesmo exercício.

```
83 arquivos      →  60 conteúdos únicos
5.381 links      →  219 slugs de exercício + 32 de técnica
371 nomes brutos →  193 exercícios canônicos   (96,5% de cobertura do corpus)
32 slugs         →   30 técnicas canônicas     (2.684 ocorrências)
```

O campo `occurrences` de cada registro é a frequência no corpus. Ele nunca entra no score de
compatibilidade — serve como critério de desempate: entre dois substitutos igualmente bons,
o motor prefere o que a pessoa mais provavelmente já viu.

**Os PDFs de origem não estão neste repositório.** São material de terceiros, com dados pessoais
no rodapé. Nenhum nome comercial, nome de profissional, URL de plataforma ou dado pessoal foi
incorporado aos artefatos.

---

## Idiomas

18 locales com **100% das técnicas** no resumo curto (o texto que aparece no popup durante o
treino) e os três avisos de segurança obrigatórios em todos eles.

```
                            exercícios   resumo   biblioteca   avisos
os 18 idiomas                  100%       100%       100%       3/3
```

pt-BR · en · es · fr · de · it · nl · pl · tr · id · vi · ru · ja · ko · zh-Hans · hi · ar · th

3.281 nomes de exercício e 2.160 seções de biblioteca, sem lacuna, sem colisão de
nome dentro de um idioma, e sem contaminação de alfabeto entre pacotes.

Regra do manifesto: **o app não oferece um idioma cuja cobertura de técnica não esteja em 100%.**
Explicação faltando no meio do treino é pior que idioma faltando.

Os pacotes não-pt-BR estão marcados `needs_native_review: true`. `aliases` está vazio de
propósito em todos eles — apelido é gíria local de academia, não tradução, e inventar isso seria
pior que deixar em branco.

---

## O que falta

- Revisão nativa dos 17 idiomas gerados (`needs_native_review: true`)
- `aliases` por idioma — apelido é gíria local de academia, não tradução
- Sincronização com backend (o schema já tem `synced_at`, mas nada sincroniza)
- Tela de perfil: nível, objetivo e equipamentos da academia ainda não são editáveis
- iOS não foi gerado (precisa de macOS); web compila mas o SQLite local não roda lá
- Ingestão automatizada de novas planilhas para o catálogo

## Não é

Ferramenta de organização e acompanhamento de treino. **Não substitui avaliação médica ou
profissional** quando esta for necessária.
