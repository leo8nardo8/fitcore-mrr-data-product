select
    cast(subscription_id as varchar)          as subscription_id,
    cast(customer_id as varchar)              as customer_id,
    cast(plan_id as varchar)                  as plan_id,
    lower(trim(status))                       as status,
    try_cast(start_date as date)              as start_date,
    try_cast(end_date as date)                as end_date,
    try_cast(discount_pct as decimal(5, 4))   as discount_pct
from {{ source('fitcore_raw', 'subscriptions') }}
