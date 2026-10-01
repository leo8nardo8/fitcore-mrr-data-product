-- Regra de MRR (documentada no README):
--   plano mensal -> preço de lista
--   plano anual  -> preço de lista / 12
--   em ambos, aplica-se o desconto negociado da assinatura.
select
    s.subscription_id,
    s.customer_id,
    s.plan_id,
    p.tier,
    p.billing_period,
    s.status,
    s.start_date,
    s.end_date,
    s.discount_pct,
    p.list_price,
    cast(round(
        case p.billing_period when 'annual' then p.list_price / 12 else p.list_price end
        * (1 - s.discount_pct), 2
    ) as decimal(14, 2)) as mrr_amount
from {{ ref('stg_fitcore__subscriptions') }} as s
inner join {{ ref('stg_fitcore__plans') }} as p
    on s.plan_id = p.plan_id
