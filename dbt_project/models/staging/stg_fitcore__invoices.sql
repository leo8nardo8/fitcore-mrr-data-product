select
    cast(invoice_id as varchar)            as invoice_id,
    cast(subscription_id as varchar)       as subscription_id,
    cast(customer_id as varchar)           as customer_id,
    try_cast(issued_date as date)          as issued_date,
    try_cast(period_start as date)         as period_start,
    try_cast(period_end as date)           as period_end,
    -- try_cast: valores fora do tipo viram nulo e são barrados pelo teste not_null,
    -- em vez de derrubar o pipeline com erro de conversão sem diagnóstico.
    try_cast(amount as decimal(14, 2))     as amount,
    upper(trim(currency))                  as currency,
    lower(trim(status))                    as status
from {{ source('fitcore_raw', 'invoices') }}
