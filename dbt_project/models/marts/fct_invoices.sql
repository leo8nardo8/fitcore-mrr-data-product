with payments as (
    select
        invoice_id,
        sum(amount_paid) as amount_paid,
        min(paid_at)     as first_paid_at
    from {{ ref('stg_fitcore__payments') }}
    group by 1
)

select
    i.invoice_id,
    i.customer_id,
    i.subscription_id,
    s.plan_id,
    s.tier,
    s.billing_period,
    i.issued_date,
    i.period_start,
    i.period_end,
    s.list_price,
    s.discount_pct,
    i.amount,
    cast(coalesce(p.amount_paid, 0) as decimal(14, 2))           as amount_paid,
    -- razão líquido/lista: monitora a política comercial de descontos
    cast(round(i.amount / s.list_price, 4) as decimal(6, 4))     as net_to_list_ratio,
    i.status                                                     as invoice_status,
    p.first_paid_at                                              as paid_at,
    cast(date_diff('day', i.issued_date, p.first_paid_at) as integer) as days_to_pay
from {{ ref('stg_fitcore__invoices') }} as i
inner join {{ ref('int_subscriptions_enriched') }} as s
    on i.subscription_id = s.subscription_id
left join payments as p
    on i.invoice_id = p.invoice_id
