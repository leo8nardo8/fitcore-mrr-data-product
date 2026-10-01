/*
  INTEGRIDADE CRUZADA faturas x pagamentos: o total pago de uma fatura não
  pode exceder o valor faturado. Excesso indica pagamento duplicado ou
  vinculado à fatura errada, o que infla caixa e distorce inadimplência.
  Roda sobre o staging para barrar o problema antes dos marts (shift-left).
*/
select
    i.invoice_id,
    i.amount                as invoiced,
    sum(p.amount_paid)      as paid,
    sum(p.amount_paid) - i.amount as excess
from {{ ref('stg_fitcore__invoices') }} as i
inner join {{ ref('stg_fitcore__payments') }} as p
    on i.invoice_id = p.invoice_id
group by i.invoice_id, i.amount
having sum(p.amount_paid) > i.amount + 0.01
