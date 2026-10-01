"""
Gerador de dados sintéticos da FitCore (SaaS B2B de gestão de academias).

Produz as fontes "raw" em parquet consumidas pelo projeto dbt:
customers, subscriptions, invoices e payments. O catálogo de planos
é um seed estático do dbt (dbt_project/seeds/plans.csv).

Premissas de negócio (documentadas no README):
- A FitCore cobra as academias (B2B); não há dados de alunos.
- Planos mensais faturam todo mês no dia de aniversário; anuais, uma vez por ano.
- Mudanças de plano (upgrade/downgrade) e cancelamentos ocorrem na renovação
  do ciclo de cobrança: a assinatura antiga termina e uma nova começa na mesma data.
- Descontos negociados ficam na assinatura e valem para todas as faturas dela.
- Aquisição com sazonalidade de academias: pico em janeiro e março, vale em dezembro.

Semente fixa: mesma semente + mesma data de corte = mesmos dados.
Por padrão a data de corte é ONTEM, para que os testes estatísticos com
janela relativa à data atual (dbt-expectations) sempre tenham dados recentes.
"""
from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / "data" / "raw"
PLANS_SEED = ROOT / "dbt_project" / "seeds" / "plans.csv"

START = date(2023, 1, 1)
AS_OF = datetime.now(ZoneInfo("America/Sao_Paulo")).date() - timedelta(days=1)  # sobrescrito por --as-of

# Sazonalidade de novas academias por mês (1 = média)
SEASONALITY = {1: 1.6, 2: 1.1, 3: 1.4, 4: 1.0, 5: 0.9, 6: 0.8,
               7: 0.9, 8: 1.0, 9: 1.0, 10: 0.9, 11: 0.8, 12: 0.5}

MONTHLY_CHURN = 0.015
MONTHLY_UPGRADE = 0.012
MONTHLY_DOWNGRADE = 0.005
ANNUAL_CHURN_AT_RENEWAL = 0.10
REACTIVATION_PROB = 0.25  # chance de uma academia churnada voltar algum dia

TIERS = ["starter", "pro", "enterprise"]
CITIES = [("Porto Alegre", "RS"), ("Caxias do Sul", "RS"), ("Florianópolis", "SC"),
          ("Curitiba", "PR"), ("São Paulo", "SP"), ("Campinas", "SP"),
          ("Belo Horizonte", "MG"), ("Rio de Janeiro", "RJ"), ("Goiânia", "GO"),
          ("Recife", "PE"), ("Salvador", "BA"), ("Fortaleza", "CE")]
GYM_WORDS = ["Iron", "Vida", "Force", "Pulse", "Move", "Corpo", "Atlas", "Ritmo",
             "Arena", "Fênix", "Titan", "Equilíbrio", "Energia", "Fit", "Prime"]
GYM_SUFFIX = ["Academia", "Fitness", "Studio", "Box", "Gym", "Centro Esportivo"]


def load_plans() -> dict[str, dict]:
    with open(PLANS_SEED, newline="", encoding="utf-8") as f:
        return {r["plan_id"]: {**r, "list_price": float(r["list_price"])}
                for r in csv.DictReader(f)}


def add_months(d: date, n: int) -> date:
    m = d.month - 1 + n
    return date(d.year + m // 12, m % 12 + 1, d.day)  # dias sempre <= 28


def cnpj(rng: np.random.Generator) -> str:
    """CNPJ com dígitos verificadores válidos, no formato XX.XXX.XXX/XXXX-XX."""
    base = list(rng.integers(0, 10, 8)) + [0, 0, 0, 1]
    for weights in ([5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2],
                    [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]):
        s = sum(d * w for d, w in zip(base, weights)) % 11
        base.append(0 if s < 2 else 11 - s)
    d = "".join(map(str, base))
    return f"{d[:2]}.{d[2:5]}.{d[5:8]}/{d[8:12]}-{d[12:]}"


@dataclass
class Sub:
    subscription_id: str
    customer_id: str
    plan_id: str
    start_date: date
    end_date: date | None
    discount_pct: float
    status: str


def simulate(seed: int) -> dict[str, pd.DataFrame]:
    rng = np.random.default_rng(seed)
    plans = load_plans()
    plan_of = lambda tier, period: f"{tier}_{period}"

    customers, subs = [], []
    sub_seq = 0

    def new_sub(cust_id, plan_id, start, discount):
        nonlocal sub_seq
        sub_seq += 1
        s = Sub(f"SUB-{sub_seq:06d}", cust_id, plan_id, start, None, discount, "active")
        subs.append(s)
        return s

    # 1) Aquisição de academias mês a mês, com crescimento e sazonalidade
    cust_seq = 0
    month = START
    while month <= AS_OF:
        months_elapsed = (month.year - START.year) * 12 + month.month - START.month
        expected = 9 * (1.025 ** months_elapsed) * SEASONALITY[month.month]
        for _ in range(rng.poisson(expected)):
            cust_seq += 1
            day = int(rng.integers(1, 29))
            start = date(month.year, month.month, day)
            if start > AS_OF:
                continue
            city, uf = CITIES[rng.integers(len(CITIES))]
            cid = f"GYM-{cust_seq:05d}"
            customers.append({
                "customer_id": cid,
                "gym_name": f"{rng.choice(GYM_WORDS)} {rng.choice(GYM_SUFFIX)} {cust_seq}",
                "cnpj": cnpj(rng),
                "city": city, "state": uf,
                "created_at": start.isoformat(),
            })
            tier = rng.choice(TIERS, p=[0.55, 0.35, 0.10])
            period = "annual" if rng.random() < 0.25 else "monthly"
            discount = float(rng.choice([0, 0, 0, 0.05, 0.10, 0.15]))
            new_sub(cid, plan_of(tier, period), start, discount)
        month = add_months(month, 1)

    # 2) Ciclo de vida: a cada renovação, decidir churn / upgrade / downgrade
    i = 0
    while i < len(subs):
        s = subs[i]
        i += 1
        plan = plans[s.plan_id]
        step = 12 if plan["billing_period"] == "annual" else 1
        renewal = add_months(s.start_date, step)
        while renewal <= AS_OF:
            r = rng.random()
            tier_idx = TIERS.index(plan["tier"])
            if plan["billing_period"] == "annual":
                p_churn, p_up, p_down = ANNUAL_CHURN_AT_RENEWAL, 0.08, 0.03
            else:
                p_churn, p_up, p_down = MONTHLY_CHURN, MONTHLY_UPGRADE, MONTHLY_DOWNGRADE
            if r < p_churn:
                s.end_date, s.status = renewal, "canceled"
                if rng.random() < REACTIVATION_PROB:
                    back = add_months(renewal, int(rng.integers(2, 10)))
                    if back <= AS_OF:
                        new_sub(s.customer_id, s.plan_id, back, s.discount_pct)
                break
            if r < p_churn + p_up and tier_idx < 2:
                s.end_date, s.status = renewal, "replaced"
                new_sub(s.customer_id, plan_of(TIERS[tier_idx + 1], plan["billing_period"]),
                        renewal, s.discount_pct)
                break
            if r < p_churn + p_up + p_down and tier_idx > 0:
                s.end_date, s.status = renewal, "replaced"
                new_sub(s.customer_id, plan_of(TIERS[tier_idx - 1], plan["billing_period"]),
                        renewal, s.discount_pct)
                break
            renewal = add_months(renewal, step)

    # 3) Faturas: uma por ciclo enquanto a assinatura está ativa
    invoices, payments = [], []
    inv_seq = pay_seq = 0
    for s in subs:
        plan = plans[s.plan_id]
        step = 12 if plan["billing_period"] == "annual" else 1
        period_start = s.start_date
        while period_start <= AS_OF and (s.end_date is None or period_start < s.end_date):
            inv_seq += 1
            period_end = add_months(period_start, step) - timedelta(days=1)
            amount = round(plan["list_price"] * (1 - s.discount_pct), 2)
            inv_id = f"INV-{inv_seq:07d}"
            days_open = (AS_OF - period_start).days
            r = rng.random()
            if r < 0.93 or days_open > 60:
                delay = int(rng.integers(0, 6)) if r < 0.85 else int(rng.integers(6, 30))
                paid_at = period_start + timedelta(days=delay)
                if paid_at <= AS_OF:
                    pay_seq += 1
                    payments.append({
                        "payment_id": f"PAY-{pay_seq:07d}", "invoice_id": inv_id,
                        "paid_at": paid_at.isoformat(), "amount_paid": amount,
                        "payment_method": str(rng.choice(["pix", "boleto", "cartao"],
                                                         p=[0.5, 0.3, 0.2])),
                    })
                    status = "paid"
                else:
                    status = "open"
            else:
                status = "overdue" if days_open > 10 else "open"
            invoices.append({
                "invoice_id": inv_id, "subscription_id": s.subscription_id,
                "customer_id": s.customer_id, "issued_date": period_start.isoformat(),
                "period_start": period_start.isoformat(), "period_end": period_end.isoformat(),
                "amount": amount, "currency": "BRL", "status": status,
            })
            period_start = add_months(period_start, step)

    subs_df = pd.DataFrame([{
        "subscription_id": s.subscription_id, "customer_id": s.customer_id,
        "plan_id": s.plan_id, "status": s.status,
        "start_date": s.start_date.isoformat(),
        "end_date": s.end_date.isoformat() if s.end_date else None,
        "discount_pct": s.discount_pct,
    } for s in subs])

    return {
        "customers": pd.DataFrame(customers),
        "subscriptions": subs_df,
        "invoices": pd.DataFrame(invoices),
        "payments": pd.DataFrame(payments),
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--as-of", type=date.fromisoformat, default=AS_OF,
                    help="data de corte (AAAA-MM-DD); padrão: ontem")
    args = ap.parse_args()
    globals()["AS_OF"] = args.as_of
    print(f"Gerando dados de {START} a {AS_OF} (seed={args.seed})")

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    for name, df in simulate(args.seed).items():
        df.to_parquet(RAW_DIR / f"{name}.parquet", index=False)
        print(f"  {name:<14} {len(df):>7,} linhas -> data/raw/{name}.parquet")


if __name__ == "__main__":
    main()
