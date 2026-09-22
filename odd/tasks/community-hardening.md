# Feature: community-hardening (aprendizajes del ecosistema de forks)

Goal: incorporar al fork las piezas que los demás forks de
`mskelton/tree-sitter-mql5` han demostrado, con trazabilidad explícita de la
inspiración para agradecimientos futuros.

Contexto: censo del 2026-09-21 sobre los 9 forks del upstream. Los 4 clones
intactos (`marceloneppel`, `az49xcl`, `bytesoverflow`, `riodelphino`) y
`iisaka51` (0 commits) no aportan. Los activos y su valor se detallan por
tarea. Nota de licencias: mskelton es ISC y los forks no tocaron el LICENSE
(salvo MichalBPL, que declara MIT en sus adiciones) — cualquier código
inspirado/copiado exige atribución: ver T6.

## Tareas

- [ ] T1 Regla `export_specifier` (`void f() export { }`)
      Inspiration: hydralynxtrading-a11y/tree-sitter-mql5
      https://github.com/hydralynxtrading-a11y/tree-sitter-mql5
      (grammar.js, reglas `export_specifier` y `_function_postfix`, push 2026-09-18)
      Criterio: regla de 2 líneas + corpus test con `void f() export {}`;
      verificar que `export` como identificador sigue parseando (sonda);
      suite verde. Status: COMPLETADA — hook `_function_declarator_seq`
      (no existe _function_postfix en el base fijado); commit 0c17959

- [ ] T2 `input_group` con `;` opcional + test de `group` como identificador
      Inspiration: hydralynxtrading-a11y/tree-sitter-mql5
      https://github.com/hydralynxtrading-a11y/tree-sitter-mql5
      (grammar.js: `optional(";")` en `input_group`; nota "group becomes a
      reserved word")
      Criterio: sondea `input group "x";` (si da ERROR, añadir `optional(";")`
      + corpus test); añadir corpus test de `int group = 5;` como tripwire
      (verificado a mano el 2026-09-21: 0 ERROR). Status: COMPLETADA —
      `;` producía MISSING type_identifier; commit 0c17959. Extra: harness
      cuenta MISSING (commit separado)

- [ ] T3 Manejo de encodings en el harness de regresión (UTF-16LE de MetaEditor)
      Inspiration: hydralynxtrading-a11y/tree-sitter-mql5
      https://github.com/hydralynxtrading-a11y/tree-sitter-mql5
      (sweep.ps1: detección UTF-16LE, UTF-8 con/sin BOM; su README documenta
      que MetaEditor mezcla encodings)
      Criterio: run-regression.sh detecta encoding por fichero; UTF-16LE se
      transcodifica (o se reporta explícitamente) antes de parsear; auditoría
      del corpus actual (111 ficheros) y del download-corpus.sh; corpus test
      con un fichero UTF-16LE sintético. Status: COMPLETADA — lib-encoding.sh
      (detect/transcode), run-regression.sh transcodifica en vuelo,
      download-corpus.sh normaliza a UTF-8 en ingest, test-encoding.sh
      self-test + CI step; auditoría corpus 2026-09-22: 111 ficheros (99 UTF-8
      BOM, 12 UTF-8 sin BOM, 0 UTF-16). Commit db36b09

- [ ] T4 Catálogos de builtins MQL (constantes/funciones) + queries generadas
      Inspiration: m0n99/tree-sitter-mql5
      https://github.com/m0n99/tree-sitter-mql5
      (build-highlights.js, queries/mql5/highlights.scm 340 líneas,
      mql5_constants.json 1086 entradas, mql5_functions.json 509; commits
      2026-01-07/09)
      Criterio: generador propio (script JS) que produzca
      queries/mql5/{highlights,locals?}.scm desde catálogos JSON adaptados a
      los nombres de nodo cpp-based; verificar licencia antes de copiar
      catálogos (si no es reutilizable, regenerar desde la documentación
      oficial de MQL5 citando la inspiración estructural). Valor extra:
      clasificación semántica de builtins para el extractor de gortex.
      Status: COMPLETADA — catálogos vendidos (ISC,
      queries/mql5-{constants,functions}.json) + generador
      scripts/build-highlights.js (bloques #any-of? idempotentes entre
      marcadores) + queries/highlights.scm generado + npm run
      build:highlights. Nota: CLI 0.20.8 ignora #any-of? (lo trata como
      siempre-verdadero), así que los bloques usan #match? con alternación
      anclada ^(...)$ (fallback previsto por el criterio de la tarea). Extra:
      predefinidas _* capturadas a mano (ausentes del catálogo upstream).
      Commit 73f6365

- [ ] T5 Migración de base: tree-sitter-cpp moderno + CLI moderna (P2 heredado)
      Inspirations (tres referencias independientes que ya lo hicieron):
      - hydralynxtrading-a11y/tree-sitter-mql5
        https://github.com/hydralynxtrading-a11y/tree-sitter-mql5
        (tree-sitter-cpp 0.23 + CLI 0.26, scanner.c C-only, push 2026-09-18)
      - m0n99/tree-sitter-mql5
        https://github.com/m0n99/tree-sitter-mql5
        (bump del submódulo tree-sitter-cpp + scanner.c C-only, 2026-01)
      - MichalBPL/tree-sitter-mql5
        https://github.com/MichalBPL/tree-sitter-mql5
        (tree-sitter-cpp ^0.23.4 + CLI ^0.25, 2026-03; sin tests: solo referencia)
      Criterio: bump de deps, `tree-sitter generate`, expectativas de corpus
      portadas, `(a = b)` parseando (el tripwire del corpus debe pasar a
      verde y actualizarse), scanner C-only unificado para Node/Rust/Go,
      verificación de ABI/LANGUAGE_VERSION contra el runtime Go de gortex
      ANTES de mergear; `npm run regression` sin regresiones.
      Status: pendiente

- [ ] T6 (opcional) Binding Node con napi-rs + binarios precompilados
      Inspiration: khayashi4337/tree-sitter-mql5
      https://github.com/khayashi4337/tree-sitter-mql5
      (commit 2025-08-24: "Node.jsバインディングをnapi-rsを使用したRust実装に移行")
      Criterio: reemplaza nan/node-gyp por napi-rs con matriz de prebuilds;
      relevante solo si se publica en npm para consumidores de editores.
      Status: pendiente (bloqueado a decisión de publicación npm)

- [ ] T7 ACKNOWLEDGMENTS.md con trazabilidad completa
      Inspiration: (meta-tarea, pedida por el maintainer)
      Criterio: fichero raíz que liste, por contribución adoptada: concepto,
      repo de origen con URL, commit/fecha, y qué se tomó (idea vs. código);
      incluir también mskelton/tree-sitter-mql5 (base ISC) y los PRs #14/#15
      enviados upstream. Actualizarlo al cerrar cada tarea de este documento.
      Status: INICIADO — ACKNOWLEDGMENTS.md creado (base + T1/T2/T3 +
      pendientes T4-T6); nota: PRs #14/#15 resultaron MERGED upstream.

## Notas

- Orden sugerido: T1, T2 (rápidas, corpus-driven) → T3 (riesgo real del
  harness) → T4 → T5 (la grande, con plan propio) → T6 (opcional).
  T7 se va rellenando a medida que se cierran las demás.
- Todo el crédito de ideas va en T7; los commits individuales citan el fork
  de inspiración en el cuerpo.
