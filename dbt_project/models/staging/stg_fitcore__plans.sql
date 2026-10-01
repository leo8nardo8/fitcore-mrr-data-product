select
    plan_id,
    plan_name,
    tier,
    billing_period,
    cast(list_price as decimal(14, 2)) as list_price
from {{ ref('plans') }}
