-- Ponte de MRR mensal (cálculo).
--
-- Decisão de desenho: o MRR de FECHAMENTO é calculado de forma INDEPENDENTE
-- dos movimentos, direto da foto das assinaturas ativas no fim do mês.
-- Os movimentos vêm da comparação cliente a cliente (int_mrr_by_customer_month).
-- O teste singular tests/assert_mrr_bridge_reconciles.sql confronta os dois
-- caminhos AQUI, na intermediate: se a ponte não fechar, o fct_mrr_monthly
-- (interface pública) nem chega a ser reconstruído.

with movements as (
    select
        month_start,
        sum(opening_mrr)                                                     as opening_mrr,
        sum(case when movement_type = 'new'          then mrr_delta else 0 end)  as new_mrr,
        sum(case when movement_type = 'reactivation' then mrr_delta else 0 end)  as reactivation_mrr,
        sum(case when movement_type = 'expansion'    then mrr_delta else 0 end)  as expansion_mrr,
        sum(case when movement_type = 'contraction'  then -mrr_delta else 0 end) as contraction_mrr,
        sum(case when movement_type = 'churn'        then -mrr_delta else 0 end) as churned_mrr
    from {{ ref('int_mrr_by_customer_month') }}
    group by 1
),

closing_snapshot as (
    select
        m.month_start,
        coalesce(sum(s.mrr_amount), 0)   as closing_mrr,
        count(distinct s.customer_id)    as active_customers
    from {{ ref('int_month_spine') }} as m
    left join {{ ref('int_subscriptions_enriched') }} as s
        on  s.start_date <= m.month_end
        and (s.end_date is null or s.end_date > m.month_end)
    group by 1
)

select
    c.month_start,
    coalesce(mv.opening_mrr, 0)      as opening_mrr,
    coalesce(mv.new_mrr, 0)          as new_mrr,
    coalesce(mv.reactivation_mrr, 0) as reactivation_mrr,
    coalesce(mv.expansion_mrr, 0)    as expansion_mrr,
    coalesce(mv.contraction_mrr, 0)  as contraction_mrr,
    coalesce(mv.churned_mrr, 0)      as churned_mrr,
    c.closing_mrr,
    c.active_customers
from closing_snapshot as c
left join movements as mv
    on c.month_start = mv.month_start
