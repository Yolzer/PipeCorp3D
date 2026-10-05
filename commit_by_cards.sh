#!/usr/bin/env bash
# =====================================================================
# PipeCorp3D :: commit_by_cards.sh
# Splits the current working tree into one GitFlow feature branch + commit
# per Trello card, merged into develop with --no-ff, then cuts release 1.0.0.
# Run from the REPO ROOT in Git Bash:   bash commit_by_cards.sh
# Safe to re-run: cards with nothing new are skipped.
# =====================================================================
set -uo pipefail

# --- locate the Godot project (the folder that contains the project.godot FILE) ---
GODOT_FILE=$(find . -name project.godot -type f -not -path "*/node_modules/*" -not -path "*/.godot/*" | head -1)
if [[ -z "$GODOT_FILE" ]]; then echo "✘ project.godot not found"; exit 1; fi
G=$(dirname "$GODOT_FILE"); G=${G#./}
echo "Godot project: $G"

# --- safety: .gitignore must protect secrets and build output ---
touch .gitignore
for rule in "**/.godot/" "node_modules/" "backend/dist/" ".env" "*.pem" "*.tmp"; do
  grep -qxF "$rule" .gitignore || echo "$rule" >> .gitignore
done
git rm -r -q --cached --ignore-unmatch backend/.env "backend/keys/*.pem" >/dev/null 2>&1 || true

# --- helpers ---
# add files by NAME anywhere inside the Godot project (folders differ between machines)
add_godot() { for name in "$@"; do
  while IFS= read -r f; do git add -- "$f"; done < <(find "$G" -name "$name" -not -path "*/.godot/*")
done; }
# add paths if they exist
add_path() { for p in "$@"; do [[ -e "$p" ]] && git add -- "$p"; done; return 0; }

# card <branch> <commit message> <commands that stage files...>
card() {
  local branch="$1" msg="$2"; shift 2
  git checkout -q develop
  git checkout -q -B "$branch"
  "$@"
  if git diff --cached --quiet; then
    echo "· skip  $branch (nothing new)"
    git checkout -q develop; git branch -q -D "$branch"
    return
  fi
  git commit -q -m "$msg"
  git checkout -q develop
  git merge -q --no-ff "$branch" -m "Merge branch '$branch' into develop"
  echo "✔ $branch"
}

# --- start on develop ---
git rev-parse --verify -q develop >/dev/null || git checkout -q -b develop
git checkout -q develop

card feature/repo-gitflow "chore(repo): estructura GitFlow, .gitignore y .gitattributes

Trello: Configuración Inicial del Repositorio (GitFlow)" \
  add_path .gitignore .gitattributes README.md commit_by_cards.sh

card feature/db-modelo-er "feat(db): modelo E-R normalizado, DDL y datos semilla

Trello: Modelado E-R y Script SQL Base
- 10 tablas, dominios, enums, CHECK e índices parciales (PostgreSQL 16)
- Diagramas Mermaid: E-R y Mapa de Actores" \
  add_path database/01_schema.sql database/04_seed.sql docs/diagrams

card feature/db-siss-economia "feat(db): triggers y procedimientos de jurisdicción SISS y economía

Trello: BD: Lógica SISS y Economía (SP + Triggers)
- 7 triggers (presupuesto, FSM, ledger append-only, bancarrota, capacidad, SISS)
- 12 procedimientos almacenados con bloqueo de fila (READ COMMITTED)
- Suite run_tests.sh: 15/15 incluida concurrencia" \
  add_path database

card feature/api-auth-jwt "feat(api): NestJS + TypeORM QueryRunner + autenticación JWT RS256

Trello: API REST: Setup y Autenticación (NestJS)
- Pool limitado, transacciones READ COMMITTED, filtro SQLSTATE PC001-PC007
- Hash scrypt, guard RS256 con lista blanca de algoritmos
- 8 pruebas unitarias + 12 e2e (alg-confusion, alg:none, enumeración)" \
  bash -c 'cd backend 2>/dev/null || exit 0
    for p in package.json package-lock.json tsconfig.json tsconfig.build.json nest-cli.json .env.example .gitignore README.md \
             scripts src/main.ts src/app.module.ts src/app.setup.ts src/config src/database src/auth src/profile src/health \
             test/auth.e2e-spec.ts test/jest-e2e.json keys/.gitkeep; do [[ -e "$p" ]] && git add -- "$p"; done; true'

card feature/godot-player-controller "feat(godot): PlumberEntity + PlayerController (separación Input/Lógica)

Trello: Motor 3D: Player Controller Base / Refactor: Separación Input-Lógica
- La entidad nunca lee Input; el controlador posee la entidad (MP-Ready)
- SignalBus tipado como frontera de futuros RPC" \
  add_godot PlumberEntity.gd PlayerController.gd SignalBus.gd

card feature/godot-grid-sockets "feat(godot): grilla determinista de sockets con autoridad GridManager

Trello: Motor 3D: Sistema de Grilla (Sockets) / Sistema de Interacción (Raycast)
- Coordenadas Vector3i, registro único por id y celda, doble ocupación bloqueada" \
  add_godot GridSocket.gd GridManager.gd GridMath.gd ItemCodes.gd

card feature/godot-test-suite "test(godot): suite headless G01-G10 y Doctor de diagnóstico

Tipado estricto en modo Error; 28/28 aprobadas" \
  add_godot test_runner.gd TestRunner.tscn doctor.gd Doctor.tscn run_tests_windows.ps1

card feature/api-game-endpoints "feat(api): endpoints del bucle de juego

Trello: API REST: Endpoints de Juego (Tickets, Inventario, Vehículos)
- Tickets con presupuesto automático y compra de materiales transaccional
- Completar trabajo (nota S-F), derivación y multa SISS, costo de vida
- 15 pruebas e2e del bucle completo" \
  add_path backend/src/game backend/test/game.e2e-spec.ts backend/src/profile

card feature/godot-api-client "feat(godot): ApiClient, JobSession y clases de datos tipadas

Trello: Integración Cliente-Servidor (Godot HTTP) / API Fetch: Sincronización de Perfil
- HTTP por acción (no por tubería), Bearer RS256, errores PCxxx al HUD
- Pruebas de integración contra API simulada (24/24)" \
  add_godot ApiClient.gd JobSession.gd JsonUtil.gd PlayerProfile.gd TicketData.gd JobResult.gd \
            test_integration.gd TestIntegration.tscn mock_api.py TestEnv.gd

card feature/godot-save-binary "feat(godot): persistencia local binaria con FileAccess

Trello: Persistencia Local: Snapshot de Sesión (FileAccess binario)
- Formato PC3D versionado con checksum y escritura atómica (sin JSON)" \
  add_godot SaveService.gd

card feature/godot-siss-zone "feat(godot): zona roja SISS interactuable (capa 4)

Trello: Motor 3D: Sistema de Interacción (Raycast) — ítem SISS → API" \
  add_godot SissZone.gd SissZone.tscn test_siss_zone.gd TestSissZone.tscn

card feature/ui-integration "feat(ui): HUD, teléfono virtual, menús e integración con SignalBus

Trello: HUD Base / UX-UI Menú Principal / Teléfono virtual
- Rutas de nodos corregidas, teclas [T] [F] [C], capas de dibujo
- Prueba de humo de UI (22/22)" \
  bash -c 'G="'"$G"'"; for n in HUD.gd MainMenu.gd main_menu.gd virtual_phone.gd job_result_screen.gd HUD.tscn main_menu.tscn MainMenu.tscn VirtualPhone.tscn JobResultScreen.tscn GameOverScreen.tscn test_ui_smoke.gd TestUISmoke.tscn; do
    find "$G" -name "$n" -not -path "*/.godot/*" -exec git add -- {} \; ; done; true'

card feature/career-coop "feat(godot): Nueva Carrera auditable y control local multi-gasfíter

- Game Over irreversible en BD; nueva carrera = nueva cuenta (historial preservado)
- CareerStore binario; [C] alterna posesión entre PlumberEntity" \
  add_godot CareerStore.gd game_over_screen.gd

card feature/level-assets "chore(godot): nivel, escenas, assets IA y configuración del proyecto" \
  add_path "$G"

card feature/misc "chore: archivos restantes del proyecto" \
  bash -c 'git add -A'

# --- GitFlow release: develop -> main + tag ---
git rev-parse --verify -q main >/dev/null || git branch -q main develop
git checkout -q -B release/1.0.0 develop
git checkout -q main
git merge -q --no-ff release/1.0.0 -m "Release 1.0.0 (MVP)"
git tag -f -a v1.0.0-mvp -m "PipeCorp3D MVP: bucle completo, SISS, persistencia, multi-gasfíter" >/dev/null
git checkout -q develop
git merge -q --no-ff release/1.0.0 -m "Merge release/1.0.0 back into develop" 2>/dev/null || true
git branch -q -d release/1.0.0

echo
git log --oneline --graph --all -40
echo
echo "Next: git push origin develop main --tags"