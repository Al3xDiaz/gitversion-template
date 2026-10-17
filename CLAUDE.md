# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Propósito

Plantilla de configuración de [GitVersion](https://gitversion.net/) reutilizable: un
`GitVersion.yml` más fragmentos de CI, pensados para copiarse dentro de otros repositorios y
así obtener versionado SemVer automático a partir del historial de git (commits y tags), sin
mantener el número de versión a mano.

No es una aplicación ni una librería: no tiene build propio ni suite de tests de producto.
No inventes comandos de compilación/lint/test para este repo — no aplican. Lo único
ejecutable es `./tests/run.sh`.

## Estructura

- `GitVersion.yml` — configuración canónica de versionado que consumen ambas plataformas.
- `ci/github-actions/gitversion.yml` — workflow reutilizable para GitHub Actions.
- `ci/gitlab-ci/gitversion.yml` — job `include`-able para GitLab CI.
- `tests/run.sh` — arnés de pruebas contra un repo git sintético.
- `README.md` — resumen corto y script de prueba del flujo.
- `docs/guia-completa.md` — documentación completa para el repo consumidor y nota de diseño.

## Cómo funciona (lo no obvio)

Flujo único `<tipo>/* → main` (sin ramas de integración). El incremento lo decide la rama
mergeada a `main` (`feat/*` → minor, `refactor/*` → major, `hotfix/*` → patch, `docs/*` y
`cicd/*` → nada); `main` da siempre la versión limpia y una rama de trabajo lleva su nombre
como etiqueta (`1.2.0-nombre.N`).

Eso **no** se implementa con la estrategia `Mainline` / `TrunkBased/preview1`, que es lo que
la documentación de GitVersion sugiere para este caso. Se probó y tiene dos bugs bloqueantes
en 6.8.2 (crash con mainlines encadenadas, y la versión retrocede tras un merge con
`increment: None`). Está documentado en la nota de diseño al final de `docs/guia-completa.md` — **léela
antes de proponer migrar a `Mainline`.**

En su lugar se usa `commit-message-incrementing`, que es estable: los regex de bump
(`major-version-bump-message` y compañía) leen el nombre de la rama origen directamente del
mensaje del commit de merge. De ahí se derivan dos cosas que hay que respetar al editar:

- Los regex están anclados a la rama **origen** del merge. Si los tocas, mantén esa propiedad
  o un back-merge hacia `feat/*` empezará a subir la versión por error.
- Todo depende de que exista un commit de merge real. El squash rompe el mecanismo; por eso
  la guía completa exige desactivarlo en el repo consumidor.

## Gotcha crítico: profundidad del clon

GitVersion recorre el **historial completo** de commits y tags. Un clon superficial (el
comportamiento por defecto en la mayoría de CI) produce una versión incorrecta o hace que
GitVersion falle. Ambos fragmentos de CI ya lo fuerzan y debe seguir siendo así:

- **GitHub Actions**: `actions/checkout` con `fetch-depth: 0`.
- **GitLab CI**: el job con `GIT_DEPTH: 0`.

## Convención de edición

Al cambiar el esquema de versionado (`GitVersion.yml`), actualiza los fragmentos de CI de
GitHub Actions y de GitLab CI a la vez — el objetivo de la plantilla es que ambas rutas de CI
produzcan la misma versión para el mismo historial — y **corre `./tests/run.sh`**.

La versión de GitVersion está fijada exactamente (`gittools/gitversion:6.8.2`) en tres sitios:
los dos fragmentos de CI y `tests/run.sh`. Si subes el pin, cámbialo en los tres y corre las
pruebas: la configuración depende de comportamientos que ya demostraron ser frágiles entre
versiones.

## Comandos

```bash
# Arnés de pruebas (requiere Docker; no necesita .NET)
./tests/run.sh

# Volcar todas las variables calculadas para el repo actual
docker run --rm -v "$PWD:/repo" gittools/gitversion:6.8.2 /repo /nocache

# Leer una sola variable
docker run --rm -v "$PWD:/repo" gittools/gitversion:6.8.2 /repo /nocache /showvariable SemVer
```

`/nocache` evita que el contenedor deje un `.git/gitversion_cache` propiedad de root en el
workspace, que rompe pasos posteriores.
