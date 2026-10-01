#!/usr/bin/env bash
# =============================================================================
# FitCore MRR — demonstração ponta a ponta do data product e do circuit breaker
#
#   ./scripts/run_demo.sh            roda todos os cenários
#   ./scripts/run_demo.sh contract   roda só um cenário
#                                    (clean|contract|bridge|schema|semantic|anomaly)
#
# Cada cenário grava o log completo em evidencias/<nn>_<cenario>.log
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DBT_DIR="$ROOT/dbt_project"
EVID="$ROOT/evidencias"
MART_SQL="$DBT_DIR/models/marts/fct_mrr_monthly.sql"
BRIDGE_SQL="$DBT_DIR/models/intermediate/int_mrr_bridge_monthly.sql"
export DBT_PROFILES_DIR="$DBT_DIR"
mkdir -p "$EVID"

# Garantia: qualquer interrupção restaura fontes e SQL originais
cleanup() {
  python "$ROOT/scripts/inject_corruption.py" --restore >/dev/null 2>&1 || true
  [[ -f "$MART_SQL.bak" ]] && mv "$MART_SQL.bak" "$MART_SQL"
  [[ -f "$BRIDGE_SQL.bak" ]] && mv "$BRIDGE_SQL.bak" "$BRIDGE_SQL"
  return 0
}
trap cleanup EXIT

banner() { printf "\n\033[1;36m=== %s ===\033[0m\n%s\n\n" "$1" "$2"; }
build()  { (cd "$DBT_DIR" && dbt build "$@"); }
snap()   { python "$ROOT/scripts/consumer_snapshot.py" "$1"; }

clean() {
  banner "00 | LINHA DE BASE" "Dados íntegros: todos os testes passam e os marts são publicados."
  python "$ROOT/scripts/generate_data.py"
  (cd "$DBT_DIR" && dbt deps --quiet && dbt seed --quiet)
  build
  snap "linha de base"
}

contract() {
  banner "01 | MODEL CONTRACT" "Um desenvolvedor muda o tipo de active_customers para texto no fct_mrr_monthly.
O contrato (enforced: true) recusa o build ANTES de substituir a tabela."
  cp "$MART_SQL" "$MART_SQL.bak"
  sed -i 's/cast(active_customers as integer)/cast(active_customers as varchar)/' "$MART_SQL"
  grep -n "active_customers as varchar" "$MART_SQL"
  build --select fct_mrr_monthly
  mv "$MART_SQL.bak" "$MART_SQL"
  snap "após quebra de contrato (deve ser idêntico à linha de base)"
}

bridge() {
  banner "02 | REGRA CONTÁBIL — REGRESSÃO DE LÓGICA NA PONTE DE MRR" "Um desenvolvedor inverte o sinal da contração no cálculo da ponte.
Schema e tipos continuam corretos (o contrato não pega), mas a ponte deixa de fechar.
O teste singular falha na intermediate e o fct_mrr_monthly não é republicado."
  snap "antes"
  cp "$BRIDGE_SQL" "$BRIDGE_SQL.bak"
  sed -i "s/when movement_type = 'contraction'  then -mrr_delta/when movement_type = 'contraction'  then mrr_delta/" "$BRIDGE_SQL"
  grep -n "'contraction'" "$BRIDGE_SQL"
  build --select +fct_mrr_monthly
  mv "$BRIDGE_SQL.bak" "$BRIDGE_SQL"
  (cd "$DBT_DIR" && dbt show --inline "select month_start, bridge_gap from audit.assert_mrr_bridge_reconciles order by 1 desc" --limit 5) || true
  snap "depois (fct_mrr_monthly deve estar idêntico)"
}

schema() {
  banner "03 | CIRCUIT BREAKER — QUEBRA DE SCHEMA NA ORIGEM" "O sistema de pagamentos passa a enviar amount_paid como texto ('R\$ 189,05').
O teste na fonte falha e todo o ramo de pagamentos é bloqueado. O ramo de MRR, que não depende de pagamentos, segue normalmente."
  snap "antes"
  python "$ROOT/scripts/inject_corruption.py" --scenario schema
  build
  snap "depois (fct_invoices deve estar idêntico)"
  python "$ROOT/scripts/inject_corruption.py" --restore
}

semantic() {
  banner "04 | CIRCUIT BREAKER — DADOS SEMANTICAMENTE INVÁLIDOS" "Faturas duplicadas e valores negativos chegam com o schema correto.
Os testes do staging falham (severity: error) e intermediate + marts ficam SKIPPED."
  snap "antes"
  python "$ROOT/scripts/inject_corruption.py" --scenario semantic
  build
  snap "depois (marts devem estar idênticos)"
  python "$ROOT/scripts/inject_corruption.py" --restore
}

anomaly() {
  banner "05 | SOFT GATE — ANOMALIA ESTATÍSTICA" "Faturas mensais do último mês fechado com valor dobrado. Nenhuma regra linha a linha é violada.
O teste de desvios-padrão móveis (severity: warn) alerta, mas o pipeline segue: pico pode ser legítimo e pede análise humana."
  python "$ROOT/scripts/inject_corruption.py" --scenario anomaly
  build
  python "$ROOT/scripts/inject_corruption.py" --restore
  build --quiet  # devolve os marts ao estado íntegro
}

# Terminal colorido; arquivo de evidência sem códigos ANSI
run() { "$1" 2>&1 | tee >(sed 's/\x1b\[[0-9;]*m//g' > "$EVID/$2_$1.log"); }

case "${1:-all}" in
  clean)    run clean 00 ;;
  contract) run contract 01 ;;
  bridge)   run bridge 02 ;;
  schema)   run schema 03 ;;
  semantic) run semantic 04 ;;
  anomaly)  run anomaly 05 ;;
  all)      run clean 00; run contract 01; run bridge 02; run schema 03; run semantic 04; run anomaly 05 ;;
  *) echo "uso: $0 [clean|contract|bridge|schema|semantic|anomaly|all]"; exit 1 ;;
esac
