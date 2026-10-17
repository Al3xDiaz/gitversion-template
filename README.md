# Plantilla de GitVersion

Configuración reutilizable de [GitVersion](https://gitversion.net/) para calcular la versión
SemVer a partir del historial de git, sin escribir el número a mano. Se copia dentro de otros
repos: un `GitVersion.yml` más fragmentos de CI para GitHub Actions y GitLab CI.

El flujo es `<tipo>/* → main`: el tipo de la rama que se mergea a `main` decide el incremento
(`feat/*` sube minor, `refactor/*` major, `hotfix/*` patch; `docs/*` y `cicd/*` no suben nada).
Requiere merge commits reales: un squash o rebase merge no sube la versión. Reglas, instalación
y la nota de diseño están en [`docs/guia-completa.md`](docs/guia-completa.md); la suite completa
corre con `./tests/run.sh`.

## Probar el flujo a mano

Pasos para ejecutar uno a uno, en orden, como notebook (Jupyter con kernel bash, Runme, etc.).
Cada bloque es independiente: no usa variables ni funciones de otro, solo la carpeta
`/tmp/gitversion-demo`, así que funciona aunque cada celda corra en un shell nuevo. Necesita
Docker. El primer bloque debe ejecutarse desde la raíz de este repo.

### 0. Preparar el comando `version`

```bash
cat > /tmp/gv-version <<'EOF'
#!/usr/bin/env bash
docker run --rm -v "$PWD:/repo" gittools/gitversion:6.8.2 /repo /nocache /showvariable SemVer | tail -1
EOF
chmod +x /tmp/gv-version
```

### 1. Crear el repo temporal con `main`

Repo nuevo fuera de este, con la configuración de la plantilla y el tag `v0.1.0`.

```bash
rm -rf /tmp/gitversion-demo && mkdir /tmp/gitversion-demo || exit 1
cp GitVersion.yml /tmp/gitversion-demo/ || exit 1   # debe correr desde la raíz de este repo
cd /tmp/gitversion-demo || exit 1
git init -q -b main
git config user.name prueba && git config user.email prueba@ejemplo.local
git add . && git commit -qm "config inicial" && git tag v0.1.0
/tmp/gv-version
```

Esperado: `0.1.0`

### 2. Crear la rama `feat/*` con dos commits

```bash
cd /tmp/gitversion-demo || exit 1
git checkout -q -b feat/perfil-de-usuario
echo uno > test.txt && git add . && git commit -qm "agrega test.txt"
echo dos >> test.txt && git commit -qam "modifica test.txt"
/tmp/gv-version
```

Esperado: `0.2.0-perfil-de-usuario.1`

### 2b. (Opcional) Rama de fix: sube patch

Sale de `main` mientras la `feat/*` sigue sin mergear. Ojo: el prefijo es `hotfix/`; una rama
`fix/…` no está en la convención y no subiría nada. Si te lo saltas, el resto sigue igual.

```bash
cd /tmp/gitversion-demo || exit 1
git checkout -q main
git checkout -q -b hotfix/sesion-expirada
echo arreglo > fix.txt && git add . && git commit -qm "corrige sesion expirada"
/tmp/gv-version
git checkout -q main
git merge -q --no-ff --no-edit hotfix/sesion-expirada
git branch -qd hotfix/sesion-expirada
/tmp/gv-version
```

Esperado: `0.1.1-sesion-expirada.1` en la rama y `0.1.1` tras mergear (patch). Al mergear después
la `feat/*` del paso 3 sigue dando `0.2.0`, porque GitVersion aplica el mayor incremento desde el
último tag, no la suma.

### 3. Mergear a `main`

Con commit de merge (`--no-ff`); un squash no subiría la versión.

```bash
cd /tmp/gitversion-demo || exit 1
git checkout -q main
git merge -q --no-ff --no-edit feat/perfil-de-usuario
/tmp/gv-version
```

Esperado: `0.2.0`

### 4. Borrar la rama origen

```bash
cd /tmp/gitversion-demo || exit 1
git branch -qd feat/perfil-de-usuario
/tmp/gv-version
```

Esperado: `0.2.0` (la versión no depende de que la rama siga existiendo)

### 5. Limpiar (opcional)

```bash
rm -rf /tmp/gitversion-demo /tmp/gv-version
```
