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
packages/boraset_domain/lib/src/
  catalog.dart      eixos de movimento, score de compatibilidade, filtros
  session.dart      SessionBlock, ExerciseSlot, SetRecord, BusyRegistry
  engine.dart       contrato do WorkoutDecisionEngine
  strategies.dart   os seis degraus da escada de adaptação
  progression.dart  progressão de carga + matemática de anilha por país

_bmad-output/boraset/data/
  catalog/exercises.core.json     193 exercícios · 13 eixos · 1.980 equivalências
  catalog/techniques.core.json     30 técnicas · categoria e frequência
  l10n/exercises.<locale>.json     nomes por idioma (18 idiomas)
  l10n/techniques.<locale>.json    ajuda por idioma (18 idiomas)
  locales.json                     manifesto de cobertura de tradução
```

---

## Decisões de arquitetura

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
                      exercícios   técnicas (resumo)   técnicas (texto longo)
pt-BR                     100%           100%                  100%
en es fr de it nl pl
tr id vi ru ja ko
zh-Hans hi ar th          100%           100%                    0%
```

3.281 nomes de exercício traduzidos, 193 por idioma, sem lacuna e sem colisão
de nome dentro de um mesmo idioma.

Regra do manifesto: **o app não oferece um idioma cuja cobertura de técnica não esteja em 100%.**
Explicação faltando no meio do treino é pior que idioma faltando.

Os pacotes não-pt-BR estão marcados `needs_native_review: true`. `aliases` está vazio de
propósito em todos eles — apelido é gíria local de academia, não tradução, e inventar isso seria
pior que deixar em branco.

---

## O que falta

- Texto longo das técnicas fora do pt-BR (o resumo curto já está em todos)
- Revisão nativa dos 17 idiomas gerados (`needs_native_review: true`)
- `aliases` por idioma — apelido é gíria local de academia, não tradução
- App Flutter: telas, persistência local, sincronização
- Ingestão automatizada de novas planilhas para o catálogo

## Não é

Ferramenta de organização e acompanhamento de treino. **Não substitui avaliação médica ou
profissional** quando esta for necessária.
