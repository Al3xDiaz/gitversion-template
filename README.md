# Plantilla de GitVersion

Configuración reutilizable de [GitVersion](https://gitversion.net/) para obtener versionado
SemVer automático a partir del historial de git, sin mantener el número de versión a mano.

Se copia dentro de otros repositorios. No es una aplicación ni una librería: no tiene build
propio ni suite de tests de producto.

## Reglas de versionado

El **incremento** lo decide la rama que se mergea. La **etiqueta** la decide la rama en la que
estás parado.

| Rama de trabajo | Efecto al mergear | | Rama de larga vida | Versión |
|---|---|---|---|---|
| `feat/*` | minor | | `development` | `1.2.0-beta.7` |
| `refactor/*` | major | | `staging` | `1.2.0-rc.2` |
| `hotfix/*` | patch | | `main` | `1.2.0` |
| `docs/*` | sin cambio | | | |
| `cicd/*` | sin cambio | | | |
| cualquier otro nombre | sin cambio | | | |

Las promociones `development → staging → main` no incrementan: propagan el número ya
calculado. Los back-merges (`main → development`) tampoco.

El orden de precedencia SemVer queda correcto: `1.2.0-beta.7` < `1.2.0-rc.2` < `1.2.0`.

## Instalación en un repo consumidor

1. Copia `GitVersion.yml` a la raíz del repositorio.
2. Copia el fragmento de CI que corresponda:
   - GitHub Actions → `ci/github-actions/gitversion.yml` a `.github/workflows/gitversion.yml`
   - GitLab CI → `ci/gitlab-ci/gitversion.yml` a `ci/gitversion.yml` y añádelo con `include:`
3. Configura la protección de rama según la sección siguiente. **No es opcional.**
4. Pon un tag inicial en `main`: `git tag v0.1.0 && git push origin v0.1.0`.

## Requisito obligatorio: merge commits

El mecanismo lee el nombre de la rama del **mensaje del commit de merge**
(`Merge branch 'feat/x' into development`). Un **squash merge o un rebase merge borran esa
información y la versión no sube.**

En el repo consumidor hay que permitir solo merge commits hacia `development`:

- **GitHub** → Settings → General → Pull Requests: deja marcado únicamente
  *Allow merge commits*. Desmarca *Allow squash merging* y *Allow rebase merging*.
- **GitLab** → Settings → Merge requests → Merge method: *Merge commit*. Y desmarca
  *Squash commits when merging*.

Están soportados los tres formatos de mensaje que se dan en la práctica:

```
git plano    Merge branch 'feat/x' into development
GitHub PR    Merge pull request #42 from mi-org/feat/x
GitLab MR    Merge branch 'feat/x' into 'development'
```

Los regex están anclados a la rama **origen**, así que un back-merge hacia una rama de trabajo
(`Merge branch 'development' into 'feat/x'`) no dispara un incremento por error.

## El tag cierra el ciclo de versión

GitVersion aplica el **máximo** incremento acumulado desde el último tag, una sola vez. Tres
`feat/*` desde la última publicación son un único salto de minor, no tres — que es la
semántica correcta de SemVer, porque lo que se versiona son *releases*, no commits.

La consecuencia práctica: **etiquetar `main` al publicar es lo que abre un ciclo nuevo.** Sin
tag, todo se sigue acumulando contra el anterior, y un `hotfix/*` posterior a un `feat/*`
seguiría dando `0.2.0` en vez de `0.2.1`, porque `max(minor, patch) = minor`.

El tag lo pone el proceso de release —una persona, o un job de publicación aparte—, nunca el
job de CI que calcula la versión. Ese job es de solo lectura por diseño.

```bash
git checkout main && git pull
git tag "v$(dotnet-gitversion /showvariable MajorMinorPatch)"
git push origin --tags
```

## Consumir la versión

| Variable | Ejemplo | Para qué |
|---|---|---|
| `SemVer` | `1.2.0-beta.7` | tags de git, tags de imagen, artefactos |
| `MajorMinorPatch` | `1.2.0` | el número pelado, sin preleanzamiento |
| `FullSemVer` / `InformationalVersion` | `1.2.0-beta.7+Branch.x.Sha.abc` | trazabilidad |

Usa `SemVer`. `FullSemVer` e `InformationalVersion` incluyen `+metadata`, y el `+` **no es un
carácter válido en un tag de Docker**.

GitVersion no produce el prefijo `v`: vive en el tag de git y la configuración ya lo absorbe
con `tag-prefix`. Si lo quieres en la salida, constrúyelo en el consumidor como `v${SEMVER}`.

## Pruebas

```bash
./tests/run.sh
```

Levanta un repo git sintético en un directorio temporal, reproduce la topología de ramas real
y compara las versiones calculadas contra las esperadas. Cubre 18 escenarios: los incrementos
por tipo de rama, la promoción a través de las tres ramas de larga vida, back-merges, los tres
formatos de mensaje de merge, el comportamiento del squash y un repo sin ningún tag.

Solo necesita Docker. **Córrelo siempre que cambies `GitVersion.yml` o subas la versión
fijada de GitVersion.**

## Probar a mano

```bash
# Con Docker, sin instalar nada
docker run --rm -v "$PWD:/repo" gittools/gitversion:6.8.2 /repo /nocache

# Una sola variable
docker run --rm -v "$PWD:/repo" gittools/gitversion:6.8.2 /repo /nocache /showvariable SemVer

# Con .NET instalado
dotnet tool install -g GitVersion.Tool
dotnet-gitversion
```

`/nocache` evita que el contenedor deje un `.git/gitversion_cache` propiedad de root.

---

## Nota de diseño: por qué no se usa `TrunkBased` / `Mainline`

La forma aparentemente natural de implementar "el incremento lo decide la rama mergeada" es la
estrategia `Mainline` del workflow `TrunkBased/preview1`, que es la única que GitVersion
documenta para ese propósito
([discusión #4217](https://github.com/GitTools/GitVersion/discussions/4217)).

Se descartó tras probarla contra GitVersion 6.8.2. Tiene dos defectos bloqueantes:

1. **Crash con ramas mainline encadenadas.** Mergear una rama `is-main-branch: true` dentro de
   otra lanza `NotImplementedException`. El código lo tiene explícitamente sin implementar:
   en `MainlineVersionStrategy.HandleMergeCommit`, si la rama mergeada y la actual son ambas
   mainline, lanza. Eso descarta de raíz la cadena `development → staging → main`.

2. **No acumula: la versión retrocede.** Tras un merge de `feat/*` (`0.1.0` → `0.2.0`), un
   merge posterior de una rama con `increment: None` devuelve `0.1.0`, perdiendo el salto
   anterior. Reproducible también con commits normales y con `+semver: none`. Rompe
   directamente el requisito de que `docs/*` y `cicd/*` no muevan la versión.

Además el propio workflow está marcado como *preview*, así que su configuración puede cambiar
entre versiones menores.

**La alternativa que usa esta plantilla** es el mecanismo `commit-message-incrementing`, que
lleva años en producción y no es preview. El nombre de la rama mergeada ya está dentro del
mensaje del commit de merge, así que en vez de pedirle a `Mainline` que lo interprete, se
ajustan los regex de bump (`major-version-bump-message` y compañía) para que lo lean ellos.
Mismo resultado, sobre código estable.

Por eso la versión de GitVersion está **fijada exactamente** en los dos fragmentos de CI y en
el arnés: `gittools/gitversion:6.8.2`. Para subirla, cambia el pin en los tres sitios y corre
`./tests/run.sh`.
