select
    cast(customer_id as varchar)  as customer_id,
    trim(gym_name)                as gym_name,
    cast(cnpj as varchar)         as cnpj,
    trim(city)                    as city,
    upper(trim(state))            as state,
    try_cast(created_at as date)  as created_at
from {{ source('fitcore_raw', 'customers') }}
