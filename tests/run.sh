#!/usr/bin/env bash
# =============================================================================
# Arnes de pruebas de GitVersion.yml
#
# Construye un repo git sintetico en un directorio temporal, reproduce la
# topologia de ramas real y compara la version calculada contra la esperada.
#
# Uso:   ./tests/run.sh
# Salida: 0 si todo pasa, 1 al primer fallo.
#
# Requiere Docker. No necesita .NET ni GitVersion instalado localmente.
# =============================================================================
set -uo pipefail

GITVERSION_IMAGE="gittools/gitversion:6.8.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../GitVersion.yml"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass_count=0
fail_count=0

REPO="$(mktemp -d)"
trap 'rm -rf "$REPO"' EXIT

# --- helpers -----------------------------------------------------------------

git_q() { git -C "$REPO" "$@" >/dev/null 2>&1; }

# Invoca GitVersion sobre el repo sintetico.
#   /nocache  evita que se escriba .git/gitversion_cache (que ademas queda como
#             root al venir del contenedor) y garantiza recalculo en cada paso.
gitversion() {
  local repo="$1" var="$2"
  docker run --rm -v "$repo:/repo" "$GITVERSION_IMAGE" /repo /nocache /showvariable "$var" 2>&1 | tail -1
}

# Version calculada por GitVersion para el estado actual del repo.
version() { gitversion "$REPO" SemVer; }

# Solo la parte major.minor.patch, ignorando el preleanzamiento.
mmp() { gitversion "$REPO" MajorMinorPatch; }

# Etiqueta de preleanzamiento (vacia en main, nombre de la rama en ramas de trabajo).
label() { gitversion "$REPO" PreReleaseLabel; }

# check <descripcion> <esperado> <obtenido>
check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf "  %sPASS%s  %-52s %s\n" "$GREEN" "$RESET" "$desc" "$actual"
    ((pass_count++))
  else
    printf "  %sFAIL%s  %-52s esperado=%s obtenido=%s\n" "$RED" "$RESET" "$desc" "$expected" "$actual"
    ((fail_count++))
  fi
}

# Crea una rama de trabajo, le pone un commit y la mergea con --no-ff usando el
# mensaje que genera git por defecto.
#   work_merge <rama> <rama-destino>
work_merge() {
  local branch="$1" target="$2"
  git_q checkout "$target"
  git_q checkout -b "$branch"
  git_q commit --allow-empty -m "trabajo en $branch"
  git_q checkout "$target"
  git_q merge --no-ff "$branch" -m "Merge branch '$branch' into $target"
}

# Igual, pero con un mensaje de merge en el formato que genera cada plataforma.
#   work_merge_msg <rama> <rama-destino> <mensaje>
work_merge_msg() {
  local branch="$1" target="$2" msg="$3"
  git_q checkout "$target"
  git_q checkout -b "$branch"
  git_q commit --allow-empty -m "trabajo en $branch"
  git_q checkout "$target"
  git_q merge --no-ff "$branch" -m "$msg"
}

section() { printf "\n%s%s%s\n" "$YELLOW" "$1" "$RESET"; }

# --- comprobaciones previas --------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then
  echo "${RED}ERROR${RESET}: hace falta docker para correr estas pruebas." >&2
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "${RED}ERROR${RESET}: no encuentro GitVersion.yml en $CONFIG" >&2
  exit 1
fi

printf "%sImagen:%s %s\n" "$DIM" "$RESET" "$GITVERSION_IMAGE"
printf "%sRepo:  %s %s\n" "$DIM" "$RESET" "$REPO"

# --- montaje del repo sintetico ----------------------------------------------

git init -q -b main "$REPO"
git_q config user.email "arnes@ejemplo.local"
git_q config user.name  "Arnes de pruebas"
git_q config commit.gpgsign false
cp "$CONFIG" "$REPO/GitVersion.yml"
git_q add GitVersion.yml
git_q commit -m "chore: configuracion inicial de GitVersion"
git_q tag v0.1.0

# =============================================================================
section "Linea base"
# =============================================================================

check "1. main recien etiquetado v0.1.0" "0.1.0" "$(version)"

# =============================================================================
section "Incrementos por rama mergeada a main"
# =============================================================================

work_merge "feat/perfil-de-usuario" main
check "2. feat/* sube minor" "0.2.0" "$(mmp)"

work_merge "docs/manual-de-uso" main
check "3. docs/* NO sube la version" "0.2.0" "$(mmp)"

work_merge "cicd/cachear-dependencias" main
check "4. cicd/* NO sube la version" "0.2.0" "$(mmp)"

work_merge "spike/prueba-de-concepto" main
check "5. rama fuera de convencion NO sube la version" "0.2.0" "$(mmp)"

check "6. main da la version limpia, sin sufijo" "0.2.0" "$(version)"
check "7. main no lleva etiqueta de preleanzamiento" "" "$(label)"

# =============================================================================
section "Version parado en una rama de trabajo"
# =============================================================================

git_q checkout -b feat/pantalla-de-ajustes main
git_q commit --allow-empty -m "trabajo en feat/pantalla-de-ajustes"
check "8. la rama de trabajo lleva su nombre como etiqueta" "pantalla-de-ajustes" "$(label)"
git_q checkout main
git_q branch -D feat/pantalla-de-ajustes

# =============================================================================
section "El tag cierra el ciclo de version"
# =============================================================================
# GitVersion aplica el MAXIMO incremento acumulado desde el ultimo tag, una sola
# vez. Es la semantica correcta de SemVer -- tres feat desde la ultima release
# son un unico salto de minor, no tres -- pero implica que el tag sobre main es
# lo que abre un ciclo nuevo. Sin el, todo se sigue acumulando contra v0.1.0.

git_q tag v0.2.0
check "9. tras etiquetar, main se queda en la version publicada" "0.2.0" "$(version)"

# =============================================================================
section "Hotfix y back-merges"
# =============================================================================

work_merge "hotfix/fuga-de-sesiones" main
check "10. hotfix/* sube patch" "0.2.1" "$(mmp)"

# Back-merge hacia una rama de trabajo: el mensaje menciona feat/* como DESTINO,
# no como origen. No debe contar como incremento.
git_q checkout -b feat/exportar-datos main
git_q commit --allow-empty -m "trabajo en feat/exportar-datos"
git_q merge --no-ff main -m "Merge branch 'main' into 'feat/exportar-datos'"
git_q checkout main
git_q merge --no-ff feat/exportar-datos -m "Merge branch 'feat/exportar-datos' into main"
check "11. back-merge main -> feat/* no cuenta doble" "0.3.0" "$(mmp)"

# =============================================================================
section "Formatos de mensaje de las plataformas"
# =============================================================================

git_q tag v0.3.0

work_merge_msg "feat/exportar-a-csv" main \
  "Merge pull request #42 from mi-org/feat/exportar-a-csv"
check "12. mensaje de PR de GitHub sube minor" "0.4.0" "$(mmp)"

git_q tag v0.4.0

work_merge_msg "refactor/capa-de-datos" main \
  "Merge branch 'refactor/capa-de-datos' into 'main'"
check "13. mensaje de MR de GitLab sube major" "1.0.0" "$(mmp)"

# =============================================================================
section "Squash merge (limitacion conocida)"
# =============================================================================
# Un squash no deja commit de merge, asi que el nombre de la rama desaparece y
# el incremento no ocurre. Por eso la guia (docs/guia-completa.md) exige merge commits.

git_q tag v1.0.0

git_q checkout -b feat/no-deberia-contar
git_q commit --allow-empty -m "trabajo en feat/no-deberia-contar"
git_q checkout main
git_q merge --squash feat/no-deberia-contar
git_q commit --allow-empty -m "feat: no deberia contar (squashed)"
check "14. squash NO incrementa (por eso se prohibe)" "1.0.0" "$(mmp)"

# =============================================================================
section "Repo sin ningun tag"
# =============================================================================

REPO_NOTAG="$(mktemp -d)"
git init -q -b main "$REPO_NOTAG"
git -C "$REPO_NOTAG" config user.email "arnes@ejemplo.local"
git -C "$REPO_NOTAG" config user.name "Arnes de pruebas"
cp "$CONFIG" "$REPO_NOTAG/GitVersion.yml"
git -C "$REPO_NOTAG" add GitVersion.yml >/dev/null 2>&1
git -C "$REPO_NOTAG" commit -q -m "chore: inicial" >/dev/null 2>&1
git -C "$REPO_NOTAG" checkout -q -b feat/primera
git -C "$REPO_NOTAG" commit -q --allow-empty -m "trabajo"
git -C "$REPO_NOTAG" checkout -q main
git -C "$REPO_NOTAG" merge --no-ff -q feat/primera -m "Merge branch 'feat/primera' into main"
notag_version="$(gitversion "$REPO_NOTAG" MajorMinorPatch)"
rm -rf "$REPO_NOTAG"
check "15. sin ningun tag, arranca y aplica el minor" "0.1.0" "$notag_version"

# =============================================================================

printf "\n%s%d pasaron%s, " "$GREEN" "$pass_count" "$RESET"
if (( fail_count > 0 )); then
  printf "%s%d fallaron%s\n\n" "$RED" "$fail_count" "$RESET"
  exit 1
fi
printf "0 fallaron\n\n"
exit 0
