-- MRR de cada academia na foto de fim de mês e classificação do movimento
-- em relação ao mês anterior. É a fonte dos MOVIMENTOS da ponte de MRR.
with first_month as (
    select customer_id, date_trunc('month', min(start_date))::date as first_month
    from {{ ref('int_subscriptions_enriched') }}
    group by 1
),

customer_months as (
    select f.customer_id, m.month_start, m.month_end
    from first_month as f
    inner join {{ ref('int_month_spine') }} as m
        on m.month_start >= f.first_month
),

mrr_snapshot as (
    select
        cm.customer_id,
        cm.month_start,
        coalesce(sum(s.mrr_amount), 0) as mrr
    from customer_months as cm
    left join {{ ref('int_subscriptions_enriched') }} as s
        on  s.customer_id = cm.customer_id
        and s.start_date <= cm.month_end
        and (s.end_date is null or s.end_date > cm.month_end)
    group by 1, 2
),

with_history as (
    select
        customer_id,
        month_start,
        mrr,
        coalesce(lag(mrr) over w, 0) as prev_mrr,
        -- já teve MRR em algum mês anterior? (distingue new de reactivation)
        coalesce(max(mrr) over (
            partition by customer_id order by month_start
            rows between unbounded preceding and 1 preceding
        ), 0) > 0 as had_mrr_before
    from mrr_snapshot
    window w as (partition by customer_id order by month_start)
)

select
    customer_id,
    month_start,
    cast(prev_mrr as decimal(14, 2)) as opening_mrr,
    cast(mrr as decimal(14, 2))      as closing_mrr,
    case
        when prev_mrr = 0 and mrr > 0 and not had_mrr_before then 'new'
        when prev_mrr = 0 and mrr > 0 then 'reactivation'
        when prev_mrr > 0 and mrr = 0 then 'churn'
        when mrr > prev_mrr then 'expansion'
        when mrr < prev_mrr then 'contraction'
        when mrr > 0 then 'retained'
        else 'inactive'
    end as movement_type,
    cast(mrr - prev_mrr as decimal(14, 2)) as mrr_delta
from with_history
