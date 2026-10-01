select
    cast(payment_id as varchar)              as payment_id,
    cast(invoice_id as varchar)              as invoice_id,
    try_cast(paid_at as date)                as paid_at,
    try_cast(amount_paid as decimal(14, 2))  as amount_paid,
    lower(trim(payment_method))              as payment_method
from {{ source('fitcore_raw', 'payments') }}
