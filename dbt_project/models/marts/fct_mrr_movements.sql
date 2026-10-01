-- Detalhe dos movimentos de MRR por academia (somente meses com mudança).
-- Permite auditar qualquer número da ponte mensal até o cliente.
select
    m.customer_id,
    c.gym_name,
    m.month_start,
    m.movement_type,
    m.opening_mrr,
    m.closing_mrr,
    m.mrr_delta
from {{ ref('int_mrr_by_customer_month') }} as m
inner join {{ ref('stg_fitcore__customers') }} as c
    on m.customer_id = c.customer_id
where m.movement_type not in ('retained', 'inactive')
