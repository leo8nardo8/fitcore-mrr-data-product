"""
Injeta dados corrompidos nas fontes raw para demonstrar o circuit breaker.

Cenários:
  schema   - o sistema de pagamentos passa a enviar amount_paid como TEXTO
             no formato brasileiro ("R$ 199,90"). Quebra de interface.
  semantic - faturas duplicadas (reprocessamento) e valores negativos
             (estorno lançado como fatura). Schema intacto, conteúdo inválido.
  anomaly  - faturas de planos mensais do último mês fechado com valor dobrado
             (ex.: bug de reajuste). Cada valor isolado continua plausível;
             só o agregado é anômalo.

Uso:
  python scripts/inject_corruption.py --scenario semantic
  python scripts/inject_corruption.py --restore
"""
from __future__ import annotations

import argparse
import shutil
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
BACKUP = RAW / "_backup"
FILES = ["customers", "subscriptions", "invoices", "payments"]


def backup() -> None:
    BACKUP.mkdir(exist_ok=True)
    for f in FILES:
        if not (BACKUP / f"{f}.parquet").exists():
            shutil.copy2(RAW / f"{f}.parquet", BACKUP / f"{f}.parquet")


def restore() -> None:
    if not BACKUP.exists():
        print("Nada a restaurar.")
        return
    for f in FILES:
        shutil.copy2(BACKUP / f"{f}.parquet", RAW / f"{f}.parquet")
    shutil.rmtree(BACKUP)
    print("Fontes raw restauradas para a versão íntegra.")


def schema() -> None:
    df = pd.read_parquet(RAW / "payments.parquet")
    df["amount_paid"] = df["amount_paid"].map(
        lambda v: "R$ " + f"{v:,.2f}".replace(",", "X").replace(".", ",").replace("X", "."))
    df.to_parquet(RAW / "payments.parquet", index=False)
    print(f"[schema] payments.amount_paid convertido para texto. Ex.: {df['amount_paid'].iloc[0]!r}")


def semantic() -> None:
    df = pd.read_parquet(RAW / "invoices.parquet")
    dupes = df.sample(40, random_state=7)
    neg_idx = df.sample(15, random_state=11).index
    df.loc[neg_idx, "amount"] = -df.loc[neg_idx, "amount"]
    df = pd.concat([df, dupes], ignore_index=True)
    df.to_parquet(RAW / "invoices.parquet", index=False)
    print(f"[semantic] {len(dupes)} faturas duplicadas e {len(neg_idx)} valores negativos injetados.")


def anomaly() -> None:
    df = pd.read_parquet(RAW / "invoices.parquet")
    today = datetime.now(ZoneInfo("America/Sao_Paulo")).date()  # mesmo fuso do dbt_date
    month_end = today.replace(day=1)                       # exclusivo
    month_start = (month_end - timedelta(days=1)).replace(day=1)
    issued = pd.to_datetime(df["issued_date"]).dt.date
    # Só faturas de planos mensais (< R$ 1.000): dobradas, continuam abaixo do
    # teto do catálogo, então NENHUMA regra linha a linha é violada.
    mask = (issued >= month_start) & (issued < month_end) & (df["amount"] < 1000)
    df.loc[mask, "amount"] = (df.loc[mask, "amount"] * 2).round(2)
    df.to_parquet(RAW / "invoices.parquet", index=False)
    print(f"[anomaly] {int(mask.sum())} faturas mensais de {month_start:%m/%Y} "
          "com valor dobrado (cada uma ainda dentro da faixa válida).")


def main() -> None:
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--scenario", choices=["schema", "semantic", "anomaly"])
    g.add_argument("--restore", action="store_true")
    args = ap.parse_args()
    if args.restore:
        restore()
        return
    backup()
    {"schema": schema, "semantic": semantic, "anomaly": anomaly}[args.scenario]()


if __name__ == "__main__":
    main()
