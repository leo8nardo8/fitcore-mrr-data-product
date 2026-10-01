"""
"Visão do consumidor": impressão digital dos marts que os dashboards leem.

Imprime contagem, soma e um hash do conteúdo de cada mart. Rodado antes e
depois de uma injeção de dados corrompidos, prova que o mart NÃO foi tocado
quando o circuit breaker abre (hash idêntico).
"""
import hashlib
import sys
from pathlib import Path

import duckdb

DB = Path(__file__).resolve().parents[1] / "data" / "fitcore.duckdb"

QUERIES = {
    "marts.fct_mrr_monthly": ("closing_mrr", "month_start"),
    "marts.fct_invoices": ("amount", "invoice_id"),
}


def main() -> None:
    label = sys.argv[1] if len(sys.argv) > 1 else "snapshot"
    con = duckdb.connect(str(DB), read_only=True)
    print(f"--- Visão do consumidor ({label}) ---")
    for table, (measure, order_col) in QUERIES.items():
        rows, total = con.sql(f"select count(*), sum({measure}) from {table}").fetchone()
        content = con.sql(f"select * from {table} order by {order_col}").fetchall()
        digest = hashlib.md5(repr(content).encode()).hexdigest()[:12]
        print(f"{table:<24} linhas={rows:>6,}  soma({measure})={total:>14,.2f}  hash={digest}")
    con.close()


if __name__ == "__main__":
    main()
