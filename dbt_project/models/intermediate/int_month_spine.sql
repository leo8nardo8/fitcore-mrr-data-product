-- Uma linha por mês da série de MRR. month_end é a data da "foto" do MRR.
-- A série vai até o último mês com faturamento; se esse mês ainda está em
-- curso, o fechamento representa o MRR corrente.
with bounds as (
    select date_trunc('month', max(issued_date))::date as last_month
    from {{ ref('stg_fitcore__invoices') }}
),

months as (
    select unnest(generate_series(
        date '{{ var("mrr_start_month") }}',
        (select last_month from bounds),
        interval 1 month
    ))::date as month_start
)

select
    month_start,
    last_day(month_start) as month_end
from months
