# Handoff — Plantilla de GitVersion con versionado dirigido por ramas

_Generado: 2026-09-12_

## 1. Objetivo

Crear una plantilla reutilizable de GitVersion (`GitVersion.yml` + fragmentos de CI para
GitHub Actions y GitLab CI) que se copie dentro de otros repos y calcule la versión SemVer
sola, a partir del historial de git.

Reglas pedidas:

- El **incremento** lo decide la rama que se mergea: `feat/*` → minor, `refactor/*` → major,
  `hotfix/*` → patch, `docs/*` y `cicd/*` → sin cambio.
- ~~La etiqueta la decide la rama actual (`development` → beta, `staging` → rc)~~ **Obsoleto
  (2026-10-16):** el flujo se simplificó a `<tipo>/* → main`. `main` da la versión limpia y las
  ramas de trabajo llevan su nombre como etiqueta. Ya no existen `development` ni `staging`.

El problema de fondo: dejar de tocar el número de versión a mano, sin que el equipo tenga que
recordar escribir nada especial en los commits — la señal debe salir del nombre de la rama,
que ya existe.

Restricción explícita del usuario: **el CI no escribe en el repo.** El job de CI es de solo
lectura; el versionado no puede depender de que un pipeline cree tags.

## 2. Estado en que terminó

**Funcionando y verificado.** El arnés de pruebas pasa 18/18 escenarios contra
`gittools/gitversion:6.8.2`:

    ./tests/run.sh     # 18 pasaron, 0 fallaron

Cubre: incrementos por tipo de rama, promoción a través de las tres ramas de larga vida,
back-merges (incluido el caso trampa de un back-merge *hacia* una rama `feat/*`), los tres
formatos de mensaje de merge (git plano, PR de GitHub, MR de GitLab), el comportamiento del
squash y un repo sin ningún tag.

Pendiente de decisión del usuario, no de trabajo: ver sección 5.

## 3. Archivos y cambios

El proyecto **no es un repositorio git**, así que no hay commits que referenciar. Todo lo de
abajo son archivos nuevos salvo `CLAUDE.md`.

| Archivo | Cambio |
|---|---|
| `GitVersion.yml` | **Nuevo.** La configuración. Los regex de bump leen el nombre de la rama origen del mensaje del commit de merge. Comentado con el porqué de cada decisión no obvia. |
| `ci/github-actions/gitversion.yml` | **Nuevo.** Workflow reutilizable. `fetch-depth: 0`, checkout de la rama real en PRs, salidas `semVer` y `majorMinorPatch`. Sin permisos de escritura. |
| `ci/gitlab-ci/gitversion.yml` | **Nuevo.** Job `include`-able. `GIT_DEPTH: 0`, checkout de la rama real en MRs, expone `SEMVER` vía artefacto dotenv. |
| `tests/run.sh` | **Nuevo.** Arnés de 18 escenarios sobre un repo git sintético en un temporal. Solo requiere Docker. |
| `README.md` | **Nuevo.** Doc para el repo consumidor + nota de diseño explicando por qué no se usa `Mainline`. |
| `CLAUDE.md` | **Reescrito.** Antes describía el repo como vacío. Ahora documenta la estructura real y la convención de edición. |

Decisiones de diseño que conviene no revertir sin leer la sección 4:

- **`workflow: GitFlow/v1`** como base, no `TrunkBased/preview1`.
- **Las claves de rama reutilizan los nombres del workflow** (`develop`, `feature`, `hotfix`).
  Inventar claves nuevas (`development:`, `staging:`) hace que convivan con las heredadas y
  ganen las del workflow — costó un ciclo de depuración descubrirlo.
- **`main` usa `mode: ContinuousDeployment`.** Es lo único que produce el `1.2.0` limpio; con
  `ContinuousDelivery` sale `1.2.0-8` y con `ManualDeployment` sale `1.2.0-1`.
- **La imagen está fijada en tres sitios** (los dos fragmentos de CI y el arnés). Si se sube,
  hay que cambiarla en los tres y correr las pruebas.

## 4. Intentos fallidos

El camino que la documentación oficial de GitVersion señala para este caso de uso —la
estrategia `Mainline` del workflow `TrunkBased/preview1`, confirmada por un maintainer en la
discusión #4217 como la única que aplica el incremento de la rama *origen* de un merge— **se
probó y se descartó.** Dos defectos bloqueantes en 6.8.2:

1. **Crash con ramas mainline encadenadas.** Mergear una rama `is-main-branch: true` dentro de
   otra lanza `NotImplementedException`. Se localizó la causa en el fuente: en
   `MainlineVersionStrategy.HandleMergeCommit`, si la rama mergeada y la actual son ambas
   mainline, lanza sin más. Descarta de raíz la cadena `development → staging → main`.

2. **No acumula: la versión retrocede.** Tras un merge de `feat/*` (`0.1.0` → `0.2.0`), un
   merge posterior de una rama con `increment: None` devolvía `0.1.0`, perdiendo el salto
   anterior. Rompe directamente el requisito de que `docs/*` y `cicd/*` no muevan el número.

Variantes probadas contra el bug 2, todas fallidas:

- `development` como única mainline, `staging`/`main` con `increment: Inherit` → `0.1.0-rc.1`,
  perdía el minor.
- Solo `main` como mainline → la propagación a través de los dos saltos sí funcionaba
  (`0.2.0-beta` → `0.2.0-rc` → `0.2.0`), pero el bug de `None` seguía apareciendo.
- `development.increment: Patch` en vez de `None` → sin efecto, el disparador es el
  `increment: None` de la rama *mergeada*.
- Integrar `docs/*` como commit plano sin merge commit → también retrocedía, así que no era
  cuestión de la topología del merge.
- `increment: Patch` en la rama `docs` + `+semver: none` en el mensaje → `0.1.1`, seguía
  perdiendo el minor.

**La salida** fue notar que el nombre de la rama ya viaja dentro del mensaje del commit de
merge. En vez de pedirle a la estrategia preview que lo interprete, se ajustaron los regex de
bump (`major-version-bump-message` y compañía) para que lo lean ellos, sobre
`commit-message-incrementing`, que lleva años en producción y no es preview.

Un tropiezo menor que consumió un ciclo: los fragmentos de CI y el arnés dejaban un
`.git/gitversion_cache` propiedad de root (viene del contenedor) que rompía el borrado del
temporal. Se resolvió añadiendo `/nocache` a todas las invocaciones.

## 5. Próximos pasos

1. **Decisión del usuario — `refactor/* → major`.** Quedó tal como se especificó y se confirmó
   explícitamente. Queda anotado que `refactor` significa por definición un cambio que no
   altera el comportamiento observable, así que limpiezas internas queman versiones major
   mientras que un cambio incompatible en una `feat/*` solo sube minor. Una rama `breaking/*`
   sería más fiel. **No cambiar sin que el usuario lo pida.**

2. **Decisión del usuario — `git init`.** El proyecto no es un repositorio git. No se
   inicializó porque no se pidió.

3. **Probar en un repo consumidor real.** Todo está verificado contra un repo sintético. Falta
   el estreno en un repo de verdad, con pipelines de PR/MR reales — que es donde suelen
   aparecer los problemas de HEAD detached que los fragmentos ya intentan cubrir.

4. **Configurar la protección de rama en el repo consumidor.** No es opcional: el mecanismo
   depende de que exista un commit de merge real. Squash y rebase merge lo rompen. Los pasos
   concretos para GitHub y GitLab están en docs/guia-completa.md.

5. **Poner el tag inicial** en `main` del repo consumidor (`git tag v0.1.0`), y entender que
   **etiquetar `main` al publicar es lo que abre un ciclo de versión nuevo**: GitVersion aplica
   el máximo incremento acumulado desde el último tag, una sola vez. Sin tag, un `hotfix/*`
   posterior a un `feat/*` sigue dando `0.2.0`, porque `max(minor, patch) = minor`. El tag lo
   pone el proceso de release, nunca el job de CI.
