with current_sub as (
    select *
    from {{ ref('int_subscriptions_enriched') }}
    where end_date is null
),

history as (
    select
        customer_id,
        min(start_date) as first_subscription_date,
        count(*)        as subscriptions_count
    from {{ ref('int_subscriptions_enriched') }}
    group by 1
)

select
    c.customer_id,
    c.gym_name,
    c.cnpj,
    c.city,
    c.state,
    h.first_subscription_date,
    h.subscriptions_count,
    cs.plan_id                       as current_plan_id,
    coalesce(cs.mrr_amount, 0)       as current_mrr,
    cs.subscription_id is not null   as is_active
from {{ ref('stg_fitcore__customers') }} as c
left join history as h on c.customer_id = h.customer_id
left join current_sub as cs on c.customer_id = cs.customer_id
