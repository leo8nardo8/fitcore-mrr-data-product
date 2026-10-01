-- Ponte de MRR mensal — interface pública do data product (contrato enforced).
-- Só é reconstruída se a reconciliação contábil da int_mrr_bridge_monthly passar.
select
    month_start,
    cast(opening_mrr      as decimal(14, 2)) as opening_mrr,
    cast(new_mrr          as decimal(14, 2)) as new_mrr,
    cast(reactivation_mrr as decimal(14, 2)) as reactivation_mrr,
    cast(expansion_mrr    as decimal(14, 2)) as expansion_mrr,
    cast(contraction_mrr  as decimal(14, 2)) as contraction_mrr,
    cast(churned_mrr      as decimal(14, 2)) as churned_mrr,
    cast(closing_mrr      as decimal(14, 2)) as closing_mrr,
    cast(closing_mrr - opening_mrr as decimal(14, 2)) as net_new_mrr,
    cast(active_customers as integer)        as active_customers
from {{ ref('int_mrr_bridge_monthly') }}
